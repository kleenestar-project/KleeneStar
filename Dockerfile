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

# listen on every interface and on a port an unprivileged user may bind; the shipped settings
# name http://localhost/ (port 80), which is unreachable from outside a container
ENV WEBEXPRESS_WebExpress__Endpoints__0__Uri=http://*:8080/
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

# everything the application writes lives under data/ (database, token store, search index,
# generated icons) and packages/ (installed plugin packages); both belong to the unprivileged user
USER root
RUN mkdir -p /app/data/db /app/data/tokens /app/packages \
    && chown -R app:app /app/data /app/packages
USER app

VOLUME ["/app/data", "/app/packages"]
ENTRYPOINT ["dotnet", "KleeneStar.dll"]
