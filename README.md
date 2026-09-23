![KleeneStar](https://raw.githubusercontent.com/kleenestar-project/.github/main/docs/assets/img/banner.png)

# KleeneStar - WebServer for Scalable, Plugin-Based Issue Applications

**KleeneStar** (/ˈkleɪni stɑːr/) is the central runtime and integration layer of the **KleeneStar** system. It hosts the core web server and binds all relevant modules into a unified, extensible platform, serving as the main entry point for development, deployment, and collaboration.

Whether you're building a local knowledge base, an issue tracker, or a distributed collaboration platform, **KleeneStar** provides the foundation for scalable, privacy, conscious applications, with full control over infrastructure and semantics.

# Quick Install

The quickest way to get **KleeneStar** up and running - including all required sibling repositories and the **WebExpress** framework packages - is the quick install script. It clones or updates the full workspace, restores the NuGet dependencies (including the **WebExpress** libraries), builds the server and starts it via `dotnet run`.

Prerequisites: [git](https://git-scm.com) and the [.NET 10 SDK](https://dot.net/download).

## Linux, macOS, WSL2, Termux

```
curl -fsSL https://raw.githubusercontent.com/kleenestar-project/KleeneStar/develop/install.sh | bash
```

## Windows (native, PowerShell)

Heads up: Native Windows runs **KleeneStar** without WSL (Windows Subsystem for Linux) - the **WebExpress**-based web server and all plugins work natively. If you'd rather use WSL2, the Linux/macOS one-liner above works there too. Found a bug? Please [file an issue](https://github.com/kleenestar-project/KleeneStar/issues).

Run this in PowerShell:

```
iex (irm https://raw.githubusercontent.com/kleenestar-project/KleeneStar/develop/install.ps1)
```

The script prepares the following layout next to each other and launches the server afterwards:

```
KleeneStar/
├── KleeneStar/           (main repository - the web server you start)
├── KleeneStar.Core/
├── KleeneStar.Model/
├── KleeneStar.Portal/
└── KleeneStar.Templates/
```

Once the script finishes, **KleeneStar** is running and accessible at [http://localhost/kleenestar](http://localhost/kleenestar). To restart it later:

```
cd KleeneStar/KleeneStar/src/KleeneStar
dotnet run
```

Optional environment variables to customize the installation:

| Variable             | Description                                        | Default      |
|----------------------|----------------------------------------------------|--------------|
| `KLEENESTAR_DIR`     | Installation directory                             | `KleeneStar` |
| `KLEENESTAR_BRANCH`  | Branch checked out for all repositories            | `develop`    |
| `KLEENESTAR_NO_RUN`  | Set to `1` to only build and skip starting the app | (unset)      |

## Docker

**KleeneStar** runs as a container. The image is built from the folder that holds the repositories side by side (the host references its siblings), so check them out as the quick install does and build from this repository:

```
cd KleeneStar/KleeneStar
cp .env.example .env        # set KLEENESTAR_SIGNING_KEY
docker compose up --build
```

**KleeneStar** then answers on [http://localhost:8080/kleenestar](http://localhost:8080/kleenestar), the portal on `/portal`.

| Variable (`.env`)        | Description                                                                                          |
|--------------------------|------------------------------------------------------------------------------------------------------|
| `KLEENESTAR_SIGNING_KEY` | Required. Signing key of the sign-in tokens, at least 256 random bits in Base64 (`openssl rand -base64 32`). |
| `KLEENESTAR_PORT`        | Port on the host, default `8080`.                                                                     |

- The database, the token store and the search index live in the volume `kleenestar-data`; `docker compose down -v` removes them and the next start seeds afresh.
- Any setting can be overridden with an environment variable prefixed `WEBEXPRESS_` (for example `WEBEXPRESS_Plugins__kleenestar.core__Database__ConnectionString`); see `src/KleeneStar/settings/readme.md`.
- Without Compose: `docker build -f KleeneStar/Dockerfile --build-context nuget=<feed folder> -t kleenestar .` from the workspace folder.
- In Visual Studio, pick the launch profile **Container (Dockerfile)**; set the environment variable `WEBEXPRESS_FEED` to the feed folder for the image build.

## Demo accounts

A fresh installation is seeded with demo data, including four accounts. All of them sign in with the password **`kleenestar`** (user name or e-mail address):

| User name        | E-mail                          | Group       |
|------------------|---------------------------------|-------------|
| `admin`          | `admin@kleenestar.org`          | Admin       |
| `alice.engineer` | `alice.engineer@kleenestar.org` | Engineering |
| `marketing.user` | `marketer@kleenestar.org`       | Marketing   |
| `support.user`   | `support@kleenestar.org`        | Support     |

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