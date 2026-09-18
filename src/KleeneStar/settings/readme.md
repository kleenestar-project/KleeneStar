# Settings

The settings directory is the one place every settings file of a **KleeneStar** installation is
read from: the web server's and those of the installed plugins. Every `.json` file in it is merged
into one configuration, in alphabetical order of the file names, with `webexpress.settings.json`
merged last so that its values win. Environment variables prefixed `WEBEXPRESS_` override every
file (`WEBEXPRESS_WebExpress__Culture`, `WEBEXPRESS_Plugins__kleenestar.core__Database__ConnectionString`).

- `webexpress.settings.json` — the web server: endpoints, culture, Kestrel limits, session, log
  and the `packages`, `assets` and `data` directories.
- `kleenestar.core.settings.json` — the KleeneStar core plugin, under `Plugins:kleenestar.core`:
  the database provider, the provider assembly and the connection string.

A plugin's file is shipped with its package and never overwritten by a package update; a value
put under the same path in `webexpress.settings.json` overrides it without touching the file.
The files are meant to be versioned in Git, following the architecture's "configuration over
customization" rule.
