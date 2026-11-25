#!/usr/bin/env bash
# Builds and pushes the KleeneStar image for linux/amd64 and linux/arm64.
#
# The build context is the workspace folder that holds the KleeneStar repositories side by side
# (set up by ../install.sh); the Dockerfile is KleeneStar/Dockerfile inside it.
#
# Usage:   ./docker/publish.sh [version] [suffix] [repository]
# Example: ./docker/publish.sh 0.0.4 alpha rschwarzer/kleenestar
# Defaults: version from <Version> of src/KleeneStar/KleeneStar.csproj, repository
#           "rschwarzer/kleenestar". The suffix defaults to "alpha" when the version is omitted
#           and to none when a version is given (an explicit '' also means none).
# Environment: WEBEXPRESS_FEED  folder with WebExpress *.nupkg packages that nuget.org does not
#                               carry (default: docker/feed, empty - everything from nuget.org)
set -euo pipefail

die() {
	printf '\033[1;31mError:\033[0m %s\n' "$1" >&2
	shift
	local line
	for line in "$@"; do printf '       %s\n' "$line" >&2; done
	exit 1
}

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE="$(dirname "$REPO")"

DEFAULT_VERSION="$(sed -n 's:.*<Version>\(.*\)</Version>.*:\1:p' "$REPO/src/KleeneStar/KleeneStar.csproj" | head -n 1)"
VERSION="${1:-${DEFAULT_VERSION:-0.0.4}}"
if [ -z "${1:-}" ]; then DEFAULT_SUFFIX=alpha; else DEFAULT_SUFFIX=''; fi
SUFFIX="${2-$DEFAULT_SUFFIX}"
REPOSITORY="${3:-rschwarzer/kleenestar}"
FEED="${WEBEXPRESS_FEED:-$REPO/docker/feed}"

TAG="$VERSION"
if [ -n "$SUFFIX" ]; then
	TAG="$VERSION-$SUFFIX"
fi

# --- prerequisites ----------------------------------------------------------------------------

command -v docker >/dev/null 2>&1 \
	|| die "Docker is not installed." "Install Docker Desktop or Docker Engine with the Buildx plugin."
docker buildx version >/dev/null 2>&1 \
	|| die "The Docker Buildx plugin is missing." "It is part of Docker Desktop; on Linux: apt-get install docker-buildx-plugin"
docker info >/dev/null 2>&1 \
	|| die "The Docker daemon does not answer." "Start Docker Desktop (or: systemctl start docker) and run this script again."

for repo in KleeneStar KleeneStar.Model KleeneStar.Core KleeneStar.Portal KleeneStar.Templates \
	KleeneStar.Automation KleeneStar.Integration KleeneStar.Ldap KleeneStar.Calendar KleeneStar.Theme KleeneStar.Help KleeneStar.Seeder; do
	[ -d "$WORKSPACE/$repo/src" ] \
		|| die "The repository $repo is missing in $WORKSPACE." \
			"The image is built from all KleeneStar repositories side by side." \
			"Set them up with: $REPO/install.sh --dir $WORKSPACE"
done

[ -n "${WEBEXPRESS_FEED:-}" ] || mkdir -p "$FEED"
[ -d "$FEED" ] || die "The package folder '$FEED' does not exist." "Set WEBEXPRESS_FEED to an existing folder (it may be empty)."

# --- build and push ---------------------------------------------------------------------------

# The default "docker" driver cannot build multi-platform images.
if ! docker buildx ls | grep -q '^multiarch'; then
	docker buildx create --name multiarch --driver docker-container >/dev/null
fi

docker buildx build \
	--builder multiarch \
	--platform linux/amd64,linux/arm64 \
	--build-context "nuget=$FEED" \
	-f "$REPO/Dockerfile" \
	-t "$REPOSITORY:$TAG" \
	--push \
	"$WORKSPACE"

docker buildx imagetools inspect "$REPOSITORY:$TAG"
