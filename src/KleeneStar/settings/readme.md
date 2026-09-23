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

The access credential lives an hour (`AccessTokenLifetime`) and every page renews it shortly
before it ends (`sessionrefresh.js` calls `POST /api/auth/refresh`); the refresh credential bounds
the whole sign-in at seven days. Signing out, ending a session on the profile and locking an
account take effect on the next request regardless of the lifetime: KleeneStar checks every
request against the token store and the account's state.

One sign-in serves the core and the portal: a token is bound to the application it was issued
for, and the portal accepts the core's.

## Accounts and passwords

The sign-in checks the password of an internal account against its stored hash. The seeded demo
accounts (`admin`, `alice.engineer`, `marketing.user`, `support.user`) sign in with `kleenestar`;
an installation that keeps them past a demonstration gives them passwords of their own - the
owner on the profile's security page, or through a one-time link an administrator creates in the
identity settings.

External sources are configured under `Plugins:kleenestar.core:Authentication`. An OpenID Connect
source is one entry of `OpenIdConnect`:

```json
"Authentication": {
  "OpenIdConnect": [
    {
      "Key": "entra",
      "Name": "Microsoft Entra ID",
      "Authority": "https://login.microsoftonline.com/<tenant>/v2.0",
      "ClientId": "<client id>",
      "ClientSecret": "<client secret>",
      "RedirectUri": "https://<host>/api/auth/callback?application=<application id>&provider=entra",
      "Provision": false
    }
  ]
}
```

Authority and callback must be https. Without `Provision`, an administrator creates the account
with the source's key as its sign-in, and its first sign-in claims it by verified e-mail address.
Keep the client secret out of the repository, for instance in
`WEBEXPRESS_Plugins__kleenestar.core__Authentication__OpenIdConnect__0__ClientSecret`.

A plugin's file is shipped with its package and never overwritten by a package update; a value
put under the same path in `webexpress.settings.json` overrides it without touching the file.
The files are meant to be versioned in Git, following the architecture's "configuration over
customization" rule.
