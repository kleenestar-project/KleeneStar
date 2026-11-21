#!/usr/bin/env bash
# Removes the KleeneStar Docker Compose deployment and configuration while preserving the
# application data (database, token store, search index, settings, assets and packages).
#
# Usage: sudo bash deinstall.sh
#        curl -fsSL https://raw.githubusercontent.com/kleenestar-project/KleeneStar/develop/docker/deinstall.sh | sudo bash
# Options (environment variables, all optional):
#   KLEENESTAR_DIR           installation directory (default: /opt/kleenestar)
set -euo pipefail

# Writes a progress message to standard output.
log() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }

# Writes an error message to standard error and exits with a failure status.
die() { printf '\033[1;31mError:\033[0m %s\n' "$*" >&2; exit 1; }

# Removes the deployment after Bash has read the complete function from standard input.
main() {

KLEENESTAR_DIR="${KLEENESTAR_DIR:-/opt/kleenestar}"
log "Checking KleeneStar installation in $KLEENESTAR_DIR"

[ "$(id -u)" -eq 0 ] || die "Run this script as root (e.g. sudo bash deinstall.sh)"
[ -d "$KLEENESTAR_DIR" ] || die "Installation directory does not exist: $KLEENESTAR_DIR"
cd "$KLEENESTAR_DIR"
KLEENESTAR_DIR="$(pwd -P)"
[ -f docker-compose.yml ] || die "No docker-compose.yml found in $KLEENESTAR_DIR. Set KLEENESTAR_DIR to the installation directory."
command -v docker >/dev/null 2>&1 || die "Docker is not installed."
docker compose version >/dev/null 2>&1 || die "The Docker Compose plugin is missing."
docker info >/dev/null 2>&1 || die "The Docker daemon does not answer. Start it with: systemctl start docker"

log "Stopping and removing the KleeneStar Compose deployment and its local images"
docker compose -f docker-compose.yml down --rmi all \
	|| die "Docker Compose could not remove the deployment. Check the Docker service and configuration."

log "Removing docker-compose.yml and .env"
rm -f -- docker-compose.yml .env \
	|| die "Could not remove docker-compose.yml and .env. Check the directory permissions."

cat <<EOF

KleeneStar has been stopped and its Compose deployment and local service images removed.

The docker-compose.yml and .env files have been removed, the signing key with them; a new
installation generates a new one and signs every user out once.
Database, token store, search index, settings, assets and packages have been preserved
in $KLEENESTAR_DIR (data, settings, assets, packages). Delete that directory to remove them too.
Docker remains installed.
EOF

}

main "$@"
