# Docker

This directory contains the helper files for the KleeneStar container. The `Dockerfile`, its ignore rules (`Dockerfile.dockerignore`) and the `docker-compose.yml` for a build from the sources are located in the repository root.

## Contents

|File           |Purpose
|---------------|-----------------------------------------------------------------------------
|`nuget.config` |NuGet configuration for the build inside the container: nuget.org plus the local feed `/nuget`.
|`feed/`        |Empty placeholder for the local feed. Put WebExpress `*.nupkg` packages here (or point `WEBEXPRESS_FEED` elsewhere) only when nuget.org does not carry the version yet.
|`publish.ps1`  |Builds the image for `linux/amd64` and `linux/arm64` and pushes it as a single tag (PowerShell).
|`publish.sh`   |Same as the PowerShell script, for Linux and macOS (Bash).
|`install.sh`   |Installs KleeneStar as a container on a Linux server (checks, Docker, directories, settings, `.env` with its own signing key, Compose).
|`deinstall.sh` |Removes the container deployment, local service images, Compose file and environment file while preserving the application data.

## Install on a Linux server

Install it directly with curl (as root):

```sh
curl -fsSL https://raw.githubusercontent.com/kleenestar-project/KleeneStar/develop/docker/install.sh | sudo bash
```

With options: `curl -fsSL <url> | sudo KLEENESTAR_PORT=8090 bash`. Alternatively copy the script to the server and run it as root:

```sh
chmod +x install.sh
sudo ./install.sh
```

The script runs on 64 bit Linux (amd64 or arm64, for example Debian, Ubuntu or Raspberry Pi OS). It stops with a message and the command that fixes it when a prerequisite is not met (not Linux, not root, 32 bit system, invalid option, less than 2 GB free, Docker daemon not answering, image not available). It:

- installs Docker Engine and the Compose plugin if they are missing,
- creates `data`, `settings`, `assets` and `packages` under `/opt/kleenestar` by default (`KLEENESTAR_DIR`), owned by UID 1654 (the `app` user of the .NET image) with mode `750`,
- pulls the image and, on the first installation, copies its default settings into `settings/`,
- writes `./.env` with a newly generated signing key (mode `600`), or updates only image, public port and URI in an existing file,
- writes `./docker-compose.yml`, starts the container and waits until it reports healthy (the first start migrates and seeds the database).

Optional environment variables:

|Variable                         |Default                               |Description
|---------------------------------|--------------------------------------|-----------------------------------------
|`KLEENESTAR_DIR`                 |`/opt/kleenestar`                     |Installation directory (absolute path)
|`KLEENESTAR_IMAGE`               |`rschwarzer/kleenestar:0.0.4-alpha`   |Image to run
|`KLEENESTAR_PORT`                |`80`                                  |Host port, mapped to container port `8080`
|`KLEENESTAR_EXTERNAL_URI`        |`http://<hostname>:<port>/`           |Public base URI (without `:80` for port 80)
|`KLEENESTAR_UID`                 |`1654`                                |Numeric user id of the container user
|`KLEENESTAR_SKIP_DOCKER_INSTALL` |                                      |`1` does not try to install Docker

The installation directory defaults to `/opt/kleenestar` regardless of the working directory. Its owner is `root` with mode `755`. The `docker-compose.yml` and `.env` files belong to `root` with modes `644` and `600`, respectively. Container paths remain under `/app`: `data` holds the database, the token store and the search index. For an existing installation elsewhere, pass its directory through `KLEENESTAR_DIR`; the installer does not move existing data.

The signing key of the sign-in tokens is generated per installation and kept in `.env`; the key in the shipped `settings/webexpress.settings.json` is published with the source and is overridden by the environment. Listener, public URI and signing key come from the environment set in `docker-compose.yml` and win over the settings files. Existing settings files are preserved on every run and stay writable for the application (the LDAP plugin saves its connections there).

Afterwards the web interface is available at `http://<hostname>/`; sign in as `admin` with the password `kleenestar` and change it. Update by running the installer again, or with `cd /opt/kleenestar && sudo docker compose pull && sudo docker compose up -d`.

Each installer run updates `KLEENESTAR_IMAGE`, `KLEENESTAR_PORT` and `KLEENESTAR_EXTERNAL_URI` in `.env` from the supplied options or their defaults; the signing key and other settings are preserved. For a custom port, hostname or reverse proxy URL, supply the same options on every run. The public URI must match the address used in the browser so that form submissions, redirects and live requests stay on the same origin.

```sh
sudo KLEENESTAR_PORT=8090 KLEENESTAR_EXTERNAL_URI=https://kleenestar.example.com/ ./install.sh
```

The installer applies a changed environment with `docker compose up -d`; a container restart alone does not apply changed environment variables.

## Uninstall

The uninstaller stops and removes the Compose deployment, its network and local service images using `docker compose down --rmi all`. After successful removal, it deletes `docker-compose.yml` and `.env` (and with it the signing key) from the installation directory. It preserves database, token store, search index, settings, assets and packages. Docker remains installed.

```sh
curl -fsSL https://raw.githubusercontent.com/kleenestar-project/KleeneStar/develop/docker/deinstall.sh | sudo bash
```

For a custom installation directory, use the same `KLEENESTAR_DIR` value used during installation:

```sh
sudo KLEENESTAR_DIR=/path/to/kleenestar bash deinstall.sh
```

A later installation into the same directory reuses the data but generates a new signing key, which signs every user out once.

## Build and run from the sources

```sh
cd KleeneStar
cp .env.example .env        # set KLEENESTAR_SIGNING_KEY (openssl rand -base64 32)
docker compose up -d --build
```

The build context is the workspace folder that holds all KleeneStar repositories side by side (set them up with `install.sh` or `install.ps1` in the repository root). `WEBEXPRESS_FEED` is optional; without it the empty `docker/feed` is used and every package comes from nuget.org.

## Publish a multi-architecture image

A plain `docker build` or the Visual Studio container build only produces an image for the host platform. To publish one tag for amd64 and arm64:

```powershell
./docker/publish.ps1
```

If PowerShell reports that script execution is disabled, run the script with a process-scoped bypass. This does not change the system policy:

```powershell
powershell -ExecutionPolicy Bypass -File ../docker/publish.ps1 -Repository rschwarzer/kleenestar -Version alpha
```

On Linux or macOS use the Bash script. It takes positional arguments `[version] [suffix] [repository]` and reads the feed from `WEBEXPRESS_FEED`:

```sh
chmod +x docker/publish.sh
./docker/publish.sh
```

Parameters of the PowerShell script:

|Parameter     |Default                                           |Description
|--------------|--------------------------------------------------|-----------------------------------------
|`-Version`    |`<Version>` of `src/KleeneStar/KleeneStar.csproj` |Version number of the tag
|`-Suffix`     |`alpha` without `-Version`, else none             |Tag suffix (`-Version 1.0` gives `1.0`, add `-Suffix beta` for `1.0-beta`)
|`-Repository` |`rschwarzer/kleenestar`                           |Image name in the registry
|`-Feed`       |`$env:WEBEXPRESS_FEED`, else `docker/feed`        |Folder with packages nuget.org does not carry

Both scripts check Docker, Buildx, the running daemon and the sibling repositories first. They need a Docker login with write access to the repository (`docker login`). If needed, they create the `multiarch` builder (driver `docker-container`), because the default builder cannot produce multi-platform images. They then push the image and print the manifest. The default tag is `rschwarzer/kleenestar:0.0.4-alpha`, the image `install.sh` runs; after publishing another tag, set `KLEENESTAR_IMAGE` on the next installer run.

Verify the result:

```sh
docker buildx imagetools inspect rschwarzer/kleenestar:0.0.4-alpha
```

The manifest must list `linux/amd64` and `linux/arm64`. The `unknown/unknown` entry is only the attestation manifest and not a separate image.

## Notes

- The build stage runs on the platform of the building machine and produces portable IL, so the arm64 image needs no emulated SDK; only the runtime stage is per platform. On a plain Linux host without Docker Desktop, run `docker run --privileged --rm tonistiigi/binfmt --install arm64` first if the `RUN` steps of the runtime stage fail for arm64.
- The container name (for example in `launchSettings.json`) must not contain a slash. The image name `rschwarzer/kleenestar` is not affected.
- `GET /health` answers `200` once the installation can serve; `docker compose ps` shows the state, the reason for `unhealthy` is in the log.
