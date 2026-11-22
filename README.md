![KleeneStar](https://raw.githubusercontent.com/kleenestar-project/.github/main/docs/assets/img/banner.png)

# KleeneStar - WebServer for Scalable, Plugin-Based Issue Applications

**KleeneStar** (/ˈkleɪni stɑːr/) is the central runtime and integration layer of the **KleeneStar** system. It hosts the core web server and binds all relevant modules into a unified, extensible platform, serving as the main entry point for development, deployment, and collaboration.

Whether you're building a local knowledge base, an issue tracker, or a distributed collaboration platform, **KleeneStar** provides the foundation for scalable, privacy, conscious applications, with full control over infrastructure and semantics.

# Quick Install

The install script sets **KleeneStar** up in one go: it checks the prerequisites, clones (or updates) every repository side by side into one workspace folder, restores the NuGet packages (the **WebExpress** framework included) and compiles the whole solution, test projects included. When a prerequisite is missing it stops, names it and prints the command that installs it.

Prerequisites, all checked by the script:

- [git](https://git-scm.com)
- the [.NET SDK](https://dot.net/download) 11 or newer and the ASP.NET Core 11 runtime (the .NET 11 SDK carries it)
- access to `github.com` and `api.nuget.org`
- about 3 GB of free disk space

## Linux, macOS, WSL2, Git Bash

```
curl -fsSL https://raw.githubusercontent.com/kleenestar-project/KleeneStar/develop/install.sh | bash
```

Options go after `bash -s --`, for example `... | bash -s -- --dir ~/src/KleeneStar --run`.

## Windows (PowerShell)

**KleeneStar** runs natively on Windows; WSL is not needed. Found a bug? Please [file an issue](https://github.com/kleenestar-project/KleeneStar/issues).

```
irm https://raw.githubusercontent.com/kleenestar-project/KleeneStar/develop/install.ps1 | iex
```

or with curl:

```
curl.exe -fsSL https://raw.githubusercontent.com/kleenestar-project/KleeneStar/develop/install.ps1 -o install.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Run
```

## Result

The script prepares the following layout, generates a signing key of the installation's own and writes a start script beside the repositories:

```
KleeneStar/
├── KleeneStar/              (host - the web server you start)
├── KleeneStar.Model/
├── KleeneStar.Core/
├── KleeneStar.Portal/
├── KleeneStar.Templates/
├── KleeneStar.Automation/
├── KleeneStar.Integration/
├── KleeneStar.Ldap/
├── KleeneStar.Theme/
├── KleeneStar.Help/
├── KleeneStar.Seeder/
├── kleenestar.env           (signing key of this installation)
└── start.sh | start.ps1 + start.cmd
```

Start **KleeneStar** with `KleeneStar/start.sh` (Linux, macOS, Git Bash) or `KleeneStar\start.cmd` (Windows, also by double-click). It then answers on [http://localhost/](http://localhost/); sign in as `admin` with the password `kleenestar` and change it. The shipped settings listen on port 80, which needs root on Linux; `start.sh` moves a non-root start to port 8080.

The signing key of the sign-in tokens in the shipped `settings/webexpress.settings.json` is published with the source. The script therefore generates a key per installation into `kleenestar.env` (readable by the current user only), and the start script hands it to the server as `WEBEXPRESS_WebExpress__Authentication__SigningKey`, which wins over the settings files. The file lies outside every repository, so it never blocks an update or lands in a commit. Starting from an IDE or with a plain `dotnet run`, set that environment variable to the key yourself; otherwise the published key is used.

Running the script again updates every repository that has no local changes, compiles anew and keeps the key.

|Option (`install.sh`)  |Option (`install.ps1`) |Environment variable              |Description                                              | Default
|-----------------------|-----------------------|----------------------------------|---------------------------------------------------------|--------------
|`--dir <path>`         |`-Dir <path>`          |`KLEENESTAR_DIR`                  |Workspace folder                                         | `KleeneStar` (the current folder when it already is a workspace)
|`--branch <name>`      |`-Branch <name>`       |`KLEENESTAR_BRANCH`               |Branch of every repository                               | `develop`
|`--configuration <c>`  |`-Configuration <c>`   |`KLEENESTAR_CONFIGURATION`        |`Debug`, `Release` or `DebugLocal`                       | `Debug`
|`--with-webexpress`    |`-WithWebExpress`      |`KLEENESTAR_WITH_WEBEXPRESS=1`    |Also clone the WebExpress sources (needed for `DebugLocal`) | off
|`--run`                |`-Run`                 |`KLEENESTAR_RUN=1`                |Start **KleeneStar** after the build                     | off

With `irm ... | iex` options are passed as environment variables, for example `$env:KLEENESTAR_RUN = '1'` before the call.

## Docker

On a Linux server (amd64 or arm64), the container installer checks the prerequisites, installs Docker if needed, generates a signing key of the installation's own, pulls the published image and starts it under `/opt/kleenestar`:

```
curl -fsSL https://raw.githubusercontent.com/kleenestar-project/KleeneStar/develop/docker/install.sh | sudo bash
```

Options, uninstall and publishing a multi-architecture image (`docker/publish.sh`, `docker/publish.ps1`) are described in [docker/README.md](docker/README.md).

To build the image from the sources instead: the image is built from the folder that holds the repositories side by side (the host references its siblings), so check them out as the quick install does and build from this repository:

```
cd KleeneStar/KleeneStar
cp .env.example .env        # set KLEENESTAR_SIGNING_KEY
docker compose up --build
```

**KleeneStar** then answers on [http://ks:8080/kleenestar](http://ks:8080/kleenestar), the portal on `/portal`. Add the following entry to the host's `hosts` file (on Windows, open `%SystemRoot%\\System32\\drivers\\etc\\hosts` as administrator) before opening that address:

```
127.0.0.1 ks
```

Docker's container name is `ks`; the `hosts` entry makes that name resolvable from the host browser.

|Variable (`.env`)         |Description
|--------------------------|---------------------------------------------------
|`KLEENESTAR_SIGNING_KEY`  | Required. Signing key of the sign-in tokens, at least 256 random bits in Base64 (`openssl rand -base64 32`).
|`KLEENESTAR_PORT`         | Port on the host, default `8080`.
|`KLEENESTAR_EXTERNAL_URI` | Public base URI for redirects and generated absolute URLs; set this to the reverse proxy or public DNS address.

- The database, the token store and the search index live in the volume `kleenestar-data`; `docker compose down -v` removes them and the next start seeds afresh.
- Any setting can be overridden with an environment variable prefixed `WEBEXPRESS_` (for example `WEBEXPRESS_Plugins__kleenestar.core__Database__ConnectionString`); see `src/KleeneStar/settings/readme.md`.
- The container reports its health: `GET http://ks:8080/health` answers `200` while the installation can serve (initialized, database reachable with the current schema, sign-in configured) and `503` otherwise, the reason going to the server log. `docker compose ps` shows the state; a Kubernetes deployment uses the same endpoint for its startup and readiness probes and `/health/live` for liveness. See [the health concept](https://github.com/kleenestar-project/KleeneStar.Core/blob/main/docs/kleenestar.health.md).
- Without Compose: `docker build -f KleeneStar/Dockerfile -t kleenestar .` from the workspace folder; `--build-context nuget=<folder>` adds packages nuget.org does not carry yet.
- In Visual Studio, pick the launch profile **Container (Dockerfile)**; `WEBEXPRESS_FEED` optionally names such a package folder for the image build.

## Demo accounts

A fresh installation is seeded with demo data, including four accounts. All of them sign in with the password **`kleenestar`** (user name or e-mail address):

|User name        |E-mail                          |Group
|-----------------|--------------------------------|------------
|`admin`          |`admin@kleenestar.org`          |Admin
|`alice.engineer` |`alice.engineer@kleenestar.org` |Engineering
|`marketing.user` |`marketer@kleenestar.org`       |Marketing
|`support.user`   |`support@kleenestar.org`        |Support

The demo password is published with the source. An installation that keeps these accounts beyond a demonstration must give them passwords of their own: the owner changes it under *Profile → Security*, or an administrator creates a one-time password link in the identity settings.

# Legal & Licensing

**KleeneStar** is released under the MIT License, a permissive open-source license that allows reuse, modification, and distribution with minimal restrictions. You're free to use **KleeneStar** in personal, academic, or commercial projects, just include the original copyright notice.

The system is designed to be GDPR-compliant:
- No tracking
- No monetization
- No hidden dependencies
- Full transparency and infrastructure control

**KleeneStar** respects your data and your autonomy. It's built for clarity, not surveillance.

# Contributing

We welcome contributions in many areas:
- Plugin development (C#)
- UI design and frontend components (JS/TS)
- Documentation and onboarding flows
- Semantic modeling and naming conventions

Feel free to fork the repository, open issues, or submit pull requests. For larger contributions, please reach out via kleenestar.project@gmail.com.

# AI transparency notice

Parts of this software, its documentation, and its assets were created with the assistance of AI-based tools, including large language models. AI-assisted contributions are reviewed by the project maintainer before they are included.

---

Become part of the **KleeneStar** community and help shape an open, modular data future.