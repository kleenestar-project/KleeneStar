# syntax=docker/dockerfile:1.7
#
# KleeneStar container image.
#
# The build context is the folder that holds the KleeneStar repositories side by side
# (KleeneStar, KleeneStar.Core, KleeneStar.Model, KleeneStar.Portal, KleeneStar.Templates) - the
# host references its siblings by relative path. docker-compose.yml sets this up; by hand:
#
#   cd <workspace>          # the folder containing KleeneStar/, KleeneStar.Core/, ...
#   docker build -f KleeneStar/Dockerfile --build-context nuget=<folder with WebExpress *.nupkg> -t kleenestar .
#
# WebExpress 2.0.0-alpha is not published on nuget.org. The named build context "nuget" hands the
# folder with its packages (the local feed) to the build; without it the empty stage below stands
# in and the restore only finds what nuget.org has.

# ---------------------------------------------------------------- local package feed
FROM scratch AS nuget

# ---------------------------------------------------------------- base
# the runtime the application runs in; Visual Studio's fast mode starts its debug container from
# this stage with the build output mounted into /app. The aspnet image, not the plain runtime:
# WebExpress serves through Kestrel.
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS base
WORKDIR /app

# Listen on all container interfaces so Docker can forward requests to port 8080. The external
# URI stays separate so a reverse proxy or port mapping never leaks the container address.
ENV WEBEXPRESS_WebExpress__Endpoints__0__Uri=http://0.0.0.0:8080/
ENV WEBEXPRESS_WebExpress__ExternalUri=http://localhost:8080/

# Stopping the container (SIGTERM) lets admitted requests and background work finish instead of
# aborting them: the server answers /health with 503 at once, drains for at most
# ShutdownTimeoutSeconds (30 s by default) and then releases its resources. The runtime has to
# wait longer than that before it kills the process - stop_grace_period in docker-compose.yml,
# terminationGracePeriodSeconds in Kubernetes.
ENV WEBEXPRESS_WebExpress__Shutdown=graceful
EXPOSE 8080
USER app

# ---------------------------------------------------------------- build
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
ARG BUILD_CONFIGURATION=Release
WORKDIR /src

COPY --from=nuget . /nuget/
COPY KleeneStar/docker/nuget.config ./nuget.config

# project files first, so the restore is cached as long as no project file changes
COPY KleeneStar/src/KleeneStar/KleeneStar.csproj KleeneStar/src/KleeneStar/
COPY KleeneStar.Core/src/KleeneStar.Core/KleeneStar.Core.csproj KleeneStar.Core/src/KleeneStar.Core/
COPY KleeneStar.Model/src/KleeneStar.Model/KleeneStar.Model.csproj KleeneStar.Model/src/KleeneStar.Model/
COPY KleeneStar.Model/src/KleeneStar.Model.Sqlite/KleeneStar.Model.Sqlite.csproj KleeneStar.Model/src/KleeneStar.Model.Sqlite/
COPY KleeneStar.Portal/src/KleeneStar.Portal/KleeneStar.Portal.csproj KleeneStar.Portal/src/KleeneStar.Portal/
COPY KleeneStar.Templates/src/KleeneStar.Templates/KleeneStar.Templates.csproj KleeneStar.Templates/src/KleeneStar.Templates/
RUN dotnet restore KleeneStar/src/KleeneStar/KleeneStar.csproj --configfile nuget.config

COPY KleeneStar/src/KleeneStar/ KleeneStar/src/KleeneStar/
COPY KleeneStar.Core/src/KleeneStar.Core/ KleeneStar.Core/src/KleeneStar.Core/
COPY KleeneStar.Model/src/KleeneStar.Model/ KleeneStar.Model/src/KleeneStar.Model/
COPY KleeneStar.Model/src/KleeneStar.Model.Sqlite/ KleeneStar.Model/src/KleeneStar.Model.Sqlite/
COPY KleeneStar.Portal/src/KleeneStar.Portal/ KleeneStar.Portal/src/KleeneStar.Portal/
COPY KleeneStar.Templates/src/KleeneStar.Templates/ KleeneStar.Templates/src/KleeneStar.Templates/

# the Release post-build packaging runs a Windows executable and skips itself in a container
# (DOTNET_RUNNING_IN_CONTAINER, set by this image); see KleeneStar.csproj
RUN dotnet publish KleeneStar/src/KleeneStar/KleeneStar.csproj \
        -c $BUILD_CONFIGURATION \
        --no-restore \
        -o /app/publish \
        -p:UseAppHost=false

# ---------------------------------------------------------------- runtime
FROM base AS final
WORKDIR /app

COPY --from=build --chown=app:app /app/publish .

# everything the application writes lives under data/ (database, token store and search index),
# assets/ (generated assets) and packages/ (installed plugin packages); all belong to the
# unprivileged user
USER root
RUN mkdir -p /app/data/db /app/data/tokens /app/packages /app/assets \
    && chown -R app:app /app/data /app/packages /app/assets
USER app

VOLUME ["/app/data", "/app/packages", "/app/assets"]

# Health: WebExpress answers GET /health on every listener - no sign-in, independent of the
# context path - with 200 while the host runs, every declared application could be created (a
# failed migration or seed fails this) and every health component of the installed plugins
# passes (KleeneStar: database and schema, sign-in settings), and with 503 otherwise; the reason
# is written to the server log, never into the response.
# The aspnet image carries neither curl nor wget, so the probe speaks HTTP through bash's
# /dev/tcp. The longest component budget is 3 s (the database), so the request gets 4 s and
# Docker 5 s. The start period covers the first start, which migrates and seeds the database.
# A port other than 8080 in the endpoint above has to be repeated here.
HEALTHCHECK --interval=30s --timeout=5s --start-period=120s --start-interval=5s --retries=3 \
    CMD ["timeout", "4", "bash", "-c", "exec 3<>/dev/tcp/127.0.0.1/8080 && printf 'GET /health HTTP/1.1\\r\\nHost: 127.0.0.1\\r\\nConnection: close\\r\\n\\r\\n' >&3 && head -n 1 <&3 | grep -q '^HTTP/1\\.[01] 200 '"]

ENTRYPOINT ["/usr/share/dotnet/dotnet", "KleeneStar.dll"]
