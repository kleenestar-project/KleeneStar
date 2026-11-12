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

`WebExpress:Endpoints:*:Uri` is the address Kestrel listens on. `WebExpress:ExternalUri` is the
public base address used for redirects and generated absolute URLs. Set the latter separately when
the application runs in a container or behind a reverse proxy; Docker Compose maps
`KLEENESTAR_EXTERNAL_URI` to `WEBEXPRESS_WebExpress__ExternalUri`. The absolute links KleeneStar
hands out itself - the one-time password reset link - are built on `ExternalUri` as well, so it
has to name the address users actually reach, scheme included.

`WebExpress:Root` decides what the server root `/` answers. The host runs two applications, and
without a choice the framework shows an overview of both; `ApplicationId` sends `/` to KleeneStar.
`"RedirectEnabled": false` brings the overview back.

`WebExpress:Shutdown` is `immediate` unless set: stopping the server aborts running requests. The
container image sets it to `graceful` (`WEBEXPRESS_WebExpress__Shutdown`), which lets admitted
requests finish within `ShutdownTimeoutSeconds` (default 30) - the container runtime has to wait
longer than that before it kills the process.

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
before it ends (WebExpress's `webexpress.webui.session.js` reads the `wx-auth-renew` hint cookie and
calls `POST /api/auth/refresh`); the refresh credential bounds
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

## Mail

`WebExpress:Email` is WebExpress's outgoing mail, shared by every application of the host and
**off** as shipped (`Enabled: false`). Name a mail server in a profile and switch it on, and
KleeneStar mails the one-time password link an administrator creates to the account's e-mail
address - the dialog still shows the link, because a message the server accepted may never
arrive, and says whether sending worked. The System settings then show an Email page (read only).
The settings are read at start; a change needs a restart.

Keep the server's account out of the repository:
`WEBEXPRESS_WebExpress__Email__Profiles__default__UserName` and `…__Password`. `Security` is
`StartTls` (port 587), `SslOnConnect` (465) or `None` (a local relay only; it refuses credentials).
With several replicas, give them a shared `WebExpress:Cluster:StatePath` - the mail delivery
remembers there which links were already sent, so a link is mailed once.

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

LDAP directories and Active Directory come with the `KleeneStar.Ldap` plugin and are configured
under its own id, `Plugins:kleenestar.ldap:Directories`, one entry per directory:

```json
"Plugins": {
  "kleenestar.ldap": {
    "Directories": [
      { "Key": "ad", "Name": "Corporate directory", "Server": "dc01.corp.example.com",
        "UseSsl": true, "BindDnFormat": "{0}@corp.example.com" }
    ]
  }
}
```

Instead of `BindDnFormat`, a directory can be searched by a service account (`ServiceDn`,
`ServicePassword`, `SearchBase`, `SearchFilter`, default `(sAMAccountName={0})`). The accounts are
created with the directory's key as their sign-in - by hand or by the plugin's synchronization.
Keep the service password out of the repository, in
`WEBEXPRESS_Plugins__kleenestar.ldap__Secrets__<key>__ServicePassword` - bound to the connection's
key, not to its position, which moves when an earlier connection is deleted.

The connections are managed on *Settings -> User management -> LDAP connections* (account
administrators only). That page owns the plugin's file `kleenestar.ldap.settings.json` in this
directory: it lists what the file holds, writes every change back into it (keeping its other
sections, not its comments) and the change takes effect without a restart. Configure the
directories either there or in that file, not in `webexpress.settings.json` - entries of the
same list in two files are merged by position. LDAP, StartTLS and LDAPS work on every platform
(a managed client, no native `libldap`); see `KleeneStar.Ldap/docs/kleenestar.ldap.md`.

A plugin's file is shipped with its package and never overwritten by a package update; a value
put under the same path in `webexpress.settings.json` overrides it without touching the file.
The files are meant to be versioned in Git, following the architecture's "configuration over
customization" rule.
