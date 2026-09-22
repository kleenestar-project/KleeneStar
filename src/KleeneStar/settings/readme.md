# Settings

The settings directory is the one place every settings file of a **KleeneStar** installation is
read from: the web server's and those of the installed plugins. Every `.json` file in it is merged
into one configuration, in alphabetical order of the file names, with `webexpress.settings.json`
merged last so that its values win. Environment variables prefixed `WEBEXPRESS_` override every
file (`WEBEXPRESS_WebExpress__Culture`, `WEBEXPRESS_Plugins__kleenestar.core__Database__ConnectionString`).

- `webexpress.settings.json` — the web server: endpoints, culture, Kestrel limits, session, log,
  authentication and the `packages`, `assets` and `data` directories.
- `kleenestar.core.settings.json` — the KleeneStar core plugin, under `Plugins:kleenestar.core`:
  the database provider, the provider assembly and the connection string.

## Authentication

`WebExpress:Authentication` is **required**: the sign-in issues signed tokens instead of keeping
a session on the server, and it refuses to run rather than invent a key per process — one
invented at start-up would sign credentials the next start no longer accepts. The section needs
an issuer, an audience, a `SigningKey` of at least 256 random bits in Base64 and a
`TokenStorePath` for the replay and revocation markers. The key shipped here belongs to this
checkout alone; a deployment generates its own and keeps it out of the repository, for instance
through `WEBEXPRESS_WebExpress__Authentication__SigningKey`.

`RequireHttps` is `false` here because the shipped endpoint is plain http: over it a browser
refuses the `__Host-`-prefixed cookie, the credential never arrives and every request stays
anonymous. An https deployment removes the value and keeps the protected cookie names.

The access credential is given a working day (`AccessTokenLifetime`) rather than the framework's
five minutes, because nothing in the browser renews it yet — the refresh endpoint exists
(`POST /api/auth/refresh`), but no page calls it, so a short-lived credential would sign users
out mid-sentence and without a word.

A plugin's file is shipped with its package and never overwritten by a package update; a value
put under the same path in `webexpress.settings.json` overrides it without touching the file.
The files are meant to be versioned in Git, following the architecture's "configuration over
customization" rule.
