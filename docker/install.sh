#!/usr/bin/env bash
# Installs KleeneStar as a Docker container on a Linux server (64 bit Debian, Ubuntu,
# Raspberry Pi OS or another distribution Docker supports).
#
# The script
#   - checks the prerequisites and installs Docker Engine with the Compose plugin if missing,
#   - creates the installation and data directories with the correct owner and permissions,
#   - copies the default settings out of the image on the first installation,
#   - generates a signing key of this installation's own for new installations and updates the
#     public address in .env,
#   - writes a docker-compose.yml that uses the published image (no local build),
#   - pulls the image, starts the container and waits until it reports healthy.
#
# Usage:   curl -fsSL https://raw.githubusercontent.com/kleenestar-project/KleeneStar/develop/docker/install.sh | sudo bash
#          or: sudo ./install.sh
# Options (environment variables, all optional; with sudo pass them after it:
#          curl -fsSL <url> | sudo KLEENESTAR_PORT=8090 bash):
#   KLEENESTAR_DIR           installation directory                (default: /opt/kleenestar)
#   KLEENESTAR_IMAGE         image to run                          (default: rschwarzer/kleenestar:0.0.3-alpha)
#   KLEENESTAR_PORT          host port                             (default: 80)
#   KLEENESTAR_EXTERNAL_URI  public base URI                       (default: http://<hostname>:<port>/)
#   KLEENESTAR_UID           numeric user id of the container user (default: 1654, the "app" user of .NET images)
#   KLEENESTAR_SKIP_DOCKER_INSTALL=1   do not try to install Docker
set -euo pipefail

# Everything is wrapped in a function so that bash reads the complete script before running it.
# This makes "curl ... | sudo bash" safe (no command can consume the script from stdin).
main() {

KLEENESTAR_DIR="${KLEENESTAR_DIR:-/opt/kleenestar}"
KLEENESTAR_IMAGE="${KLEENESTAR_IMAGE:-rschwarzer/kleenestar:0.0.3-alpha}"
KLEENESTAR_PORT="${KLEENESTAR_PORT:-80}"
KLEENESTAR_UID="${KLEENESTAR_UID:-1654}"
CONTAINER=kleenestar
MIN_FREE_MB=2048

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWarning:\033[0m %s\n' "$*" >&2; }
die()  {
	printf '\033[1;31mError:\033[0m %s\n' "$1" >&2
	shift
	local line
	for line in "$@"; do printf '       %s\n' "$line" >&2; done
	exit 1
}

# --- checks -----------------------------------------------------------------------------------

[ "$(uname -s)" = "Linux" ] \
	|| die "This installer runs on Linux only." \
		"On Windows or macOS use Docker Desktop with the docker-compose.yml of the repository."

[ "$(id -u)" -eq 0 ] \
	|| die "Run this script as root." "curl -fsSL <url> | sudo bash   or   sudo ./install.sh"

case "$(uname -m)" in
	aarch64|arm64|x86_64) ;;
	*) die "Unsupported architecture $(uname -m)." \
		"The image is published for linux/amd64 and linux/arm64; a 64 bit operating system is required." ;;
esac

[[ "$KLEENESTAR_PORT" =~ ^[0-9]+$ ]] && [ "${#KLEENESTAR_PORT}" -le 5 ] \
	&& [ "$((10#$KLEENESTAR_PORT))" -ge 1 ] && [ "$((10#$KLEENESTAR_PORT))" -le 65535 ] \
	|| die "KLEENESTAR_PORT must be a number between 1 and 65535."
[[ "$KLEENESTAR_UID" =~ ^[0-9]+$ ]] || die "KLEENESTAR_UID must be a numeric user id."

case "$KLEENESTAR_DIR" in
	/*) ;;
	*) die "KLEENESTAR_DIR must be an absolute path (got '$KLEENESTAR_DIR')." ;;
esac

# free space on the file system that will hold the installation
PROBE_DIR="$KLEENESTAR_DIR"
while [ ! -d "$PROBE_DIR" ]; do PROBE_DIR="$(dirname "$PROBE_DIR")"; done
FREE_KB="$(df -Pk "$PROBE_DIR" 2>/dev/null | awk 'NR==2 {print $4}')"
if [ -n "$FREE_KB" ] && [ "$FREE_KB" -lt $((MIN_FREE_MB * 1024)) ]; then
	die "Not enough free disk space below $PROBE_DIR: $((FREE_KB / 1024)) MB." \
		"Image, database and search index need about $MIN_FREE_MB MB." \
		"Free some space or choose another directory with KLEENESTAR_DIR."
fi

# --- Docker -----------------------------------------------------------------------------------

if ! command -v docker >/dev/null 2>&1; then
	[ "${KLEENESTAR_SKIP_DOCKER_INSTALL:-0}" = "1" ] \
		&& die "Docker is not installed." "Install Docker Engine: https://docs.docker.com/engine/install/"
	if ! command -v curl >/dev/null 2>&1; then
		if command -v apt-get >/dev/null 2>&1; then
			apt-get update && apt-get install -y --no-install-recommends curl ca-certificates
		else
			die "curl is missing; it is needed to install Docker." "Install curl with the package manager and run this script again."
		fi
	fi
	log "Installing Docker Engine"
	curl -fsSL https://get.docker.com | sh \
		|| die "Docker could not be installed." "Install Docker Engine by hand: https://docs.docker.com/engine/install/"
fi

docker compose version >/dev/null 2>&1 \
	|| die "The Docker Compose plugin is missing." \
		"Install it with: apt-get install docker-compose-plugin   (or: dnf install docker-compose-plugin)"

systemctl enable --now docker >/dev/null 2>&1 || true
docker info >/dev/null 2>&1 \
	|| die "The Docker daemon does not answer." "Start it with: systemctl start docker   and run this script again."

# --- directories and permissions --------------------------------------------------------------

log "Creating directories in $KLEENESTAR_DIR"
mkdir -p "$KLEENESTAR_DIR"/{data,settings,assets,packages}
mkdir -p "$KLEENESTAR_DIR/data/db" "$KLEENESTAR_DIR/data/tokens"
KLEENESTAR_DIR="$(cd "$KLEENESTAR_DIR" && pwd -P)"
chown root:root "$KLEENESTAR_DIR"
chmod 755 "$KLEENESTAR_DIR"

# --- image ------------------------------------------------------------------------------------

log "Pulling $KLEENESTAR_IMAGE"
docker pull "$KLEENESTAR_IMAGE" \
	|| die "The image $KLEENESTAR_IMAGE could not be pulled." \
		"Check the network connection and the image name (KLEENESTAR_IMAGE)." \
		"An image that is not published yet is built and pushed with docker/publish.sh (or publish.ps1)."

# --- default settings -------------------------------------------------------------------------
# The image carries the shipped settings directory. It is copied out on the first installation
# so the files survive container updates (the LDAP plugin, for example, saves its connections
# there). Existing files are preserved; signing key, listener and public address come from the
# environment set in docker-compose.yml and win over the files.

SETTINGS_DIR="$KLEENESTAR_DIR/settings"
if compgen -G "$SETTINGS_DIR/*.json" >/dev/null; then
	log "Keeping existing settings in $SETTINGS_DIR"
else
	log "Copying the default settings out of the image into $SETTINGS_DIR"
	CID="$(docker create "$KLEENESTAR_IMAGE")"
	if ! docker cp "$CID:/app/settings/." "$SETTINGS_DIR/"; then
		docker rm -f "$CID" >/dev/null 2>&1 || true
		die "The default settings could not be copied out of the image."
	fi
	docker rm -f "$CID" >/dev/null
	find "$SETTINGS_DIR" -type f -exec chmod 640 {} +
fi

chown -R "$KLEENESTAR_UID:$KLEENESTAR_UID" "$KLEENESTAR_DIR"/{data,settings,assets,packages}
chmod 750 "$KLEENESTAR_DIR"/{data,settings,assets,packages}

# --- .env -------------------------------------------------------------------------------------

ENV_FILE="$KLEENESTAR_DIR/.env"
PUBLIC_HOST="$(hostname)"
if [ "$KLEENESTAR_PORT" = "80" ]; then
	EXTERNAL_URI="${KLEENESTAR_EXTERNAL_URI:-http://${PUBLIC_HOST}/}"
else
	EXTERNAL_URI="${KLEENESTAR_EXTERNAL_URI:-http://${PUBLIC_HOST}:${KLEENESTAR_PORT}/}"
fi
[[ "$EXTERNAL_URI" != *$'\n'* && "$EXTERNAL_URI" != *$'\r'* ]] \
	|| die "KLEENESTAR_EXTERNAL_URI must not contain line breaks."
[[ "$EXTERNAL_URI" == http://* || "$EXTERNAL_URI" == https://* ]] \
	|| die "KLEENESTAR_EXTERNAL_URI must start with http:// or https:// (got '$EXTERNAL_URI')."

if [ -f "$ENV_FILE" ]; then
	log "Updating image and public address in $ENV_FILE while preserving the signing key and other settings"
	ENV_TEMP="$(mktemp "$KLEENESTAR_DIR/.env.XXXXXX")"
	if ! KS_IMAGE="$KLEENESTAR_IMAGE" KS_PORT="$KLEENESTAR_PORT" KS_URI="$EXTERNAL_URI" awk '
		!/^[[:space:]]*(export[[:space:]]+)?KLEENESTAR_(IMAGE|PORT|EXTERNAL_URI)[[:space:]]*=/ { print }
		END {
			print "KLEENESTAR_IMAGE=" ENVIRON["KS_IMAGE"]
			print "KLEENESTAR_PORT=" ENVIRON["KS_PORT"]
			print "KLEENESTAR_EXTERNAL_URI=" ENVIRON["KS_URI"]
		}
	' "$ENV_FILE" > "$ENV_TEMP"; then
		rm -f -- "$ENV_TEMP"
		die "Could not update $ENV_FILE."
	fi
	mv -f -- "$ENV_TEMP" "$ENV_FILE"
	grep -q '^KLEENESTAR_SIGNING_KEY=.\+' "$ENV_FILE" \
		|| die "$ENV_FILE carries no KLEENESTAR_SIGNING_KEY." \
			"Add one (openssl rand -base64 32) or delete $ENV_FILE to have a new one generated." \
			"A new key signs every user out once."
else
	log "Writing $ENV_FILE with a newly generated signing key"
	if command -v openssl >/dev/null 2>&1; then
		SIGNING_KEY="$(openssl rand -base64 32)"
	else
		SIGNING_KEY="$(head -c 32 /dev/urandom | base64 | tr -d '\n')"
	fi

	umask 077
	cat > "$ENV_FILE" <<EOF
# Generated by install.sh
# Signing key of the sign-in tokens of this installation. Keep it secret; changing it signs
# every user out.
KLEENESTAR_SIGNING_KEY=$SIGNING_KEY
KLEENESTAR_IMAGE=$KLEENESTAR_IMAGE
KLEENESTAR_PORT=$KLEENESTAR_PORT
KLEENESTAR_EXTERNAL_URI=$EXTERNAL_URI
EOF
	umask 022
fi
chmod 600 "$ENV_FILE"
chown root:root "$ENV_FILE"

# --- docker-compose.yml -----------------------------------------------------------------------

COMPOSE_FILE="$KLEENESTAR_DIR/docker-compose.yml"
log "Writing $COMPOSE_FILE"
cat > "$COMPOSE_FILE" <<'EOF'
# Generated by install.sh - run the installer again instead of editing this file.
services:
  kleenestar:
    hostname: ks
    container_name: kleenestar
    image: ${KLEENESTAR_IMAGE:-rschwarzer/kleenestar:0.0.3-alpha}
    ports:
      - "${KLEENESTAR_PORT:-80}:8080"
    environment:
      WEBEXPRESS_WebExpress__Endpoints__0__Uri: http://0.0.0.0:8080/
      WEBEXPRESS_WebExpress__ExternalUri: ${KLEENESTAR_EXTERNAL_URI:-http://localhost:${KLEENESTAR_PORT:-80}/}
      WEBEXPRESS_WebExpress__Authentication__SigningKey: ${KLEENESTAR_SIGNING_KEY:?set KLEENESTAR_SIGNING_KEY in .env}
    volumes:
      - ./data:/app/data
      - ./settings:/app/settings
      - ./assets:/app/assets
      - ./packages:/app/packages
    restart: unless-stopped
    # the image shuts down gracefully and drains for up to 30 s
    stop_grace_period: 45s
EOF
chown root:root "$COMPOSE_FILE"
chmod 644 "$COMPOSE_FILE"

# --- start ------------------------------------------------------------------------------------

cd "$KLEENESTAR_DIR"
log "Starting KleeneStar"
docker compose up -d \
	|| die "The container could not be started." \
		"Is port $KLEENESTAR_PORT already in use? Choose another one with KLEENESTAR_PORT." \
		"Logs: docker compose -f $COMPOSE_FILE logs"

# the first start migrates and seeds the database; the image's health check covers it
log "Waiting until KleeneStar reports healthy (the first start sets up the database)"
STATUS=""
for _ in $(seq 1 60); do
	STATUS="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$CONTAINER" 2>/dev/null || echo missing)"
	case "$STATUS" in
		healthy) break ;;
		unhealthy|exited|dead|missing) break ;;
	esac
	sleep 5
done
docker compose ps

if [ "$STATUS" != "healthy" ]; then
	warn "KleeneStar did not report healthy (state: ${STATUS:-unknown})."
	warn "The reason is in the log: sudo docker compose -f $COMPOSE_FILE logs --tail 100"
fi

cat <<EOF

KleeneStar is installed in $KLEENESTAR_DIR.

  Web interface:  ${EXTERNAL_URI}
  Sign in:        admin / kleenestar (change the password after the first sign-in)
  Logs:           sudo docker compose -f $COMPOSE_FILE logs -f
  Update:         run this installer again, or: cd $KLEENESTAR_DIR && sudo docker compose pull && sudo docker compose up -d
  Stop:           cd $KLEENESTAR_DIR && sudo docker compose down
  Uninstall:      curl -fsSL https://raw.githubusercontent.com/kleenestar-project/KleeneStar/develop/docker/deinstall.sh | sudo bash

The public address must match the address used in the browser; pass the same
KLEENESTAR_PORT and KLEENESTAR_EXTERNAL_URI on every installer run.
EOF

}

main "$@"
