#!/usr/bin/env bash
#
# KleeneStar install script for Linux, macOS, WSL2 and Git Bash on Windows.
#
# Clones (or updates) every KleeneStar repository side by side into one workspace folder,
# restores the NuGet packages (the WebExpress framework included) and compiles the whole
# solution: the host, all plugins and the test projects. Every prerequisite is checked first;
# when one is missing the script stops, names it and says how to install it.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/kleenestar-project/KleeneStar/develop/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/kleenestar-project/KleeneStar/develop/install.sh | bash -s -- --run
#   ./install.sh [options]
#
# Options (each has an environment variable of the same meaning):
#   --dir <path>              KLEENESTAR_DIR             Workspace folder (default: ./KleeneStar, or the
#                                                        current folder when it already is a workspace)
#   --branch <name>           KLEENESTAR_BRANCH          Branch of every repository (default: develop)
#   --configuration <name>    KLEENESTAR_CONFIGURATION   Debug, Release or DebugLocal (default: Debug)
#   --with-webexpress         KLEENESTAR_WITH_WEBEXPRESS=1  Also clone the WebExpress framework sources
#                                                        (needed for DebugLocal only)
#   --run                     KLEENESTAR_RUN=1           Start KleeneStar after the build
#   --help                                               Show this help
#
# The whole script is wrapped in main(), which runs only after bash has read the last line,
# so a command reading standard input cannot swallow the rest of a piped script.

main() {
	set -euo pipefail

	local ORG_URL="https://github.com/kleenestar-project"
	local WEBEXPRESS_URL="https://github.com/ReneSchwarzer"
	local REPOS=(
		KleeneStar
		KleeneStar.Model
		KleeneStar.Core
		KleeneStar.Portal
		KleeneStar.Templates
		KleeneStar.Automation
		KleeneStar.Integration
		KleeneStar.Ldap
		KleeneStar.Calendar
		KleeneStar.Theme
		KleeneStar.Help
		KleeneStar.Seeder
	)
	local WEBEXPRESS_REPOS=(WebExpress.WebCore WebExpress.WebIndex WebExpress.WebUI WebExpress.WebApp)
	local DOTNET_MAJOR=10
	local MIN_FREE_MB=3072

	local workspace="${KLEENESTAR_DIR:-}"
	local branch="${KLEENESTAR_BRANCH:-develop}"
	local configuration="${KLEENESTAR_CONFIGURATION:-Debug}"
	local with_webexpress="${KLEENESTAR_WITH_WEBEXPRESS:-0}"
	local run="${KLEENESTAR_RUN:-0}"

	# --- output -----------------------------------------------------------------

	local c_green="" c_yellow="" c_red="" c_bold="" c_reset=""
	if [ -t 1 ]; then
		c_green=$'\033[0;32m'; c_yellow=$'\033[0;33m'; c_red=$'\033[0;31m'
		c_bold=$'\033[1m'; c_reset=$'\033[0m'
	fi
	info() { printf '%s==>%s %s\n' "$c_green" "$c_reset" "$*"; }
	warn() { printf '%s==> %s%s\n' "$c_yellow" "$*" "$c_reset" >&2; }
	fail() {
		printf '\n%sERROR: %s%s\n' "$c_red" "$1" "$c_reset" >&2
		shift
		local line
		for line in "$@"; do printf '       %s\n' "$line" >&2; done
		printf '\n' >&2
		exit 1
	}

	usage() { sed -n '2,24p' "${BASH_SOURCE[0]:-}" 2>/dev/null | sed 's/^# \{0,1\}//' \
		|| echo "See https://github.com/kleenestar-project/KleeneStar#quick-install"; }

	# --- options ----------------------------------------------------------------

	while [ $# -gt 0 ]; do
		case "$1" in
			--dir) [ $# -ge 2 ] || fail "--dir needs a value."; workspace="$2"; shift 2 ;;
			--dir=*) workspace="${1#*=}"; shift ;;
			--branch) [ $# -ge 2 ] || fail "--branch needs a value."; branch="$2"; shift 2 ;;
			--branch=*) branch="${1#*=}"; shift ;;
			--configuration|-c) [ $# -ge 2 ] || fail "--configuration needs a value."; configuration="$2"; shift 2 ;;
			--configuration=*) configuration="${1#*=}"; shift ;;
			--with-webexpress) with_webexpress=1; shift ;;
			--run) run=1; shift ;;
			-h|--help) usage; exit 0 ;;
			*) fail "Unknown option '$1'." "Run the script with --help to list the options." ;;
		esac
	done

	case "$configuration" in
		Debug|Release) ;;
		DebugLocal) with_webexpress=1 ;;
		*) fail "Unknown configuration '$configuration'." "Use Debug, Release or DebugLocal." ;;
	esac

	# --- platform hints ---------------------------------------------------------

	local os="linux" distro=""
	case "$(uname -s)" in
		Darwin) os="macos" ;;
		MINGW*|MSYS*|CYGWIN*) os="windows" ;;
		*)
			if [ -r /etc/os-release ]; then
				distro="$(. /etc/os-release; echo "${ID:-} ${ID_LIKE:-}")"
			fi
			;;
	esac

	# Prints the commands that install a missing piece on this platform.
	# $1: git | sdk | runtime
	hint() {
		case "$os:$1" in
			windows:git) echo "Install it with:  winget install --id Git.Git -e" ;;
			windows:sdk) echo "Install it with:  winget install --id Microsoft.DotNet.SDK.$DOTNET_MAJOR -e" ;;
			windows:runtime) echo "Install it with:  winget install --id Microsoft.DotNet.AspNetCore.$DOTNET_MAJOR -e" ;;
			macos:git) echo "Install it with:  xcode-select --install   (or: brew install git)" ;;
			macos:sdk|macos:runtime)
				echo "Install the .NET $DOTNET_MAJOR SDK (it carries the runtime) from https://dot.net/download"
				echo "or with:  brew install --cask dotnet-sdk@$DOTNET_MAJOR" ;;
			linux:*)
				local pkg
				case "$1" in
					git) pkg="git" ;;
					sdk) pkg="dotnet-sdk-$DOTNET_MAJOR.0" ;;
					runtime) pkg="aspnetcore-runtime-$DOTNET_MAJOR.0" ;;
				esac
				case " $distro " in
					*" ubuntu "*|*" debian "*) echo "Install it with:  sudo apt-get update && sudo apt-get install -y $pkg" ;;
					*" fedora "*|*" rhel "*|*" centos "*) echo "Install it with:  sudo dnf install -y $pkg" ;;
					*" arch "*)
						case "$1" in
							git) echo "Install it with:  sudo pacman -S git" ;;
							*) echo "Install it with:  sudo pacman -S dotnet-sdk aspnet-runtime" ;;
						esac ;;
					*" alpine "*)
						case "$1" in
							git) echo "Install it with:  sudo apk add git" ;;
							*) echo "Install it with:  sudo apk add dotnet$DOTNET_MAJOR-sdk aspnetcore$DOTNET_MAJOR-runtime" ;;
						esac ;;
					*) echo "Install it with the package manager of your distribution ($pkg)." ;;
				esac
				if [ "$1" != "git" ]; then
					echo "Without a package: curl -fsSL https://dot.net/v1/dotnet-install.sh | bash -s -- --channel $DOTNET_MAJOR.0"
					echo "                   then add ~/.dotnet to PATH and set DOTNET_ROOT=~/.dotnet"
					echo "Details: https://learn.microsoft.com/dotnet/core/install/linux"
				fi
				;;
		esac
	}

	# --- prerequisites ----------------------------------------------------------

	info "Checking prerequisites"

	# git
	command -v git >/dev/null 2>&1 \
		|| fail "git is not installed." "KleeneStar is cloned from GitHub with git." "$(hint git)" "Then run this script again."

	# dotnet - a dotnet-install installation is not on PATH until the shell profile says so
	if ! command -v dotnet >/dev/null 2>&1 && [ -x "$HOME/.dotnet/dotnet" ]; then
		export DOTNET_ROOT="$HOME/.dotnet"
		export PATH="$HOME/.dotnet:$PATH"
		warn "Using the .NET installation in ~/.dotnet (it is not on PATH)."
	fi
	if ! command -v dotnet >/dev/null 2>&1; then
		local IFS=$'\n'
		# shellcheck disable=SC2046
		fail "The .NET SDK is not installed." \
			"KleeneStar needs the .NET $DOTNET_MAJOR SDK (or newer) and the ASP.NET Core $DOTNET_MAJOR runtime." \
			$(hint sdk) "Then open a new terminal and run this script again."
	fi

	local dotnet_out
	if ! dotnet_out="$(dotnet --list-sdks 2>&1)"; then
		fail "dotnet is installed but does not start:" "$dotnet_out" \
			"On Linux this is usually the missing ICU library (libicu); install it with the package manager." \
			"Details: https://learn.microsoft.com/dotnet/core/install/linux"
	fi

	local sdk_ok=0 sdk_line major
	while IFS= read -r sdk_line; do
		major="${sdk_line%%.*}"
		case "$major" in ''|*[!0-9]*) continue ;; esac
		[ "$major" -ge "$DOTNET_MAJOR" ] && sdk_ok=1
	done <<< "$dotnet_out"
	if [ "$sdk_ok" != 1 ]; then
		local IFS=$'\n'
		# shellcheck disable=SC2046
		fail "No .NET SDK $DOTNET_MAJOR or newer found." \
			"Installed SDKs: $(echo "$dotnet_out" | tr '\n' ' ')" \
			$(hint sdk) "Then open a new terminal and run this script again."
	fi

	local runtimes
	runtimes="$(dotnet --list-runtimes 2>/dev/null || true)"
	if ! grep -q "^Microsoft.AspNetCore.App $DOTNET_MAJOR\." <<< "$runtimes"; then
		local IFS=$'\n'
		# shellcheck disable=SC2046
		fail "The ASP.NET Core $DOTNET_MAJOR runtime is not installed." \
			"KleeneStar targets net$DOTNET_MAJOR.0; a newer runtime alone cannot run it." \
			$(hint runtime) "Then run this script again."
	fi

	# network
	export GIT_TERMINAL_PROMPT=0
	if ! git ls-remote --heads "$ORG_URL/KleeneStar.git" >/dev/null 2>&1; then
		fail "GitHub cannot be reached ($ORG_URL)." \
			"Check the internet connection and, behind a proxy, set HTTPS_PROXY (git config --global http.proxy <url>)." \
			"Then run this script again."
	fi
	if command -v curl >/dev/null 2>&1; then
		curl -fsS --max-time 20 -o /dev/null https://api.nuget.org/v3/index.json 2>/dev/null \
			|| fail "nuget.org cannot be reached." \
				"The WebExpress framework and every other package are restored from https://api.nuget.org." \
				"Check the internet connection or the proxy settings, then run this script again."
	fi

	# workspace folder: the current folder when it already is one, else ./KleeneStar
	if [ -z "$workspace" ]; then
		if [ -f "KleeneStar/src/KleeneStar.slnx" ]; then
			workspace="."
		else
			workspace="KleeneStar"
		fi
	fi
	mkdir -p "$workspace" 2>/dev/null \
		|| fail "The folder '$workspace' cannot be created." "Choose another one with --dir <path>."
	workspace="$(cd "$workspace" && pwd)"
	# pointed at the host repository itself: its parent is the workspace
	if [ -d "$workspace/.git" ]; then
		if [ -f "$workspace/src/KleeneStar.slnx" ]; then
			workspace="$(dirname "$workspace")"
		else
			fail "'$workspace' is a git repository, not a workspace folder." \
				"KleeneStar consists of several repositories next to each other." \
				"Choose an empty or new folder with --dir <path>."
		fi
	fi
	[ -w "$workspace" ] || fail "The folder '$workspace' is not writable." "Choose another one with --dir <path>."

	local repos=("${REPOS[@]}")
	[ "$with_webexpress" = 1 ] && repos+=("${WEBEXPRESS_REPOS[@]}")
	local repo
	for repo in "${repos[@]}"; do
		if [ -e "$workspace/$repo" ] && [ ! -d "$workspace/$repo/.git" ] \
			&& [ -n "$(ls -A "$workspace/$repo" 2>/dev/null)" ]; then
			fail "'$workspace/$repo' exists but is no git repository." \
				"Move or delete it, or choose another folder with --dir <path>."
		fi
	done

	# disk space
	local free_kb
	free_kb="$(df -Pk "$workspace" 2>/dev/null | awk 'NR==2 {print $4}')"
	if [ -n "$free_kb" ] && [ "$free_kb" -lt $((MIN_FREE_MB * 1024)) ]; then
		fail "Not enough free disk space in '$workspace': $((free_kb / 1024)) MB." \
			"Sources, packages and build output need about $MIN_FREE_MB MB." \
			"Free some space or choose another folder with --dir <path>."
	fi

	info "git $(git --version | awk '{print $3}'), .NET SDK $(dotnet --version 2>/dev/null)"
	info "Workspace: $workspace (branch: $branch, configuration: $configuration)"

	# --- clone / update ---------------------------------------------------------
	# The repositories reference each other through relative project references
	# (..\..\..\KleeneStar.Core\...), so they must live side by side in one folder.

	clone_or_update() {
		local name="$1" url="$2" dir="$workspace/$1"
		if [ -d "$dir/.git" ]; then
			if [ -n "$(git -C "$dir" status --porcelain --untracked-files=no)" ]; then
				warn "$name has local changes, left as it is"
				return
			fi
			info "Updating $name"
			if ! git -C "$dir" fetch --quiet origin; then
				warn "Could not fetch $name, building the local state"
				return
			fi
			if git -C "$dir" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
				git -C "$dir" checkout --quiet "$branch" 2>/dev/null \
					|| git -C "$dir" checkout --quiet -b "$branch" --track "origin/$branch" \
					|| { warn "Could not check out $branch in $name"; return; }
				git -C "$dir" merge --ff-only --quiet "origin/$branch" \
					|| warn "$name cannot be fast-forwarded to origin/$branch, left as it is"
			else
				warn "$name has no branch '$branch', staying on $(git -C "$dir" branch --show-current)"
			fi
		else
			info "Cloning $name"
			if git ls-remote --exit-code --heads "$url" "$branch" >/dev/null 2>&1; then
				git clone --quiet --branch "$branch" "$url" "$dir" \
					|| fail "Cloning $url failed." "Run the script again; it continues where it stopped."
			else
				warn "$name has no branch '$branch', cloning its default branch"
				git clone --quiet "$url" "$dir" \
					|| fail "Cloning $url failed." "Run the script again; it continues where it stopped."
			fi
		fi
	}

	for repo in "${REPOS[@]}"; do
		clone_or_update "$repo" "$ORG_URL/$repo.git"
	done
	if [ "$with_webexpress" = 1 ]; then
		for repo in "${WEBEXPRESS_REPOS[@]}"; do
			clone_or_update "$repo" "$WEBEXPRESS_URL/$repo.git"
		done
	fi

	# --- restore & build --------------------------------------------------------

	local solution="$workspace/KleeneStar/src/KleeneStar.slnx"
	[ -f "$solution" ] || fail "The solution '$solution' is missing." \
		"The repository KleeneStar is incomplete; delete '$workspace/KleeneStar' and run the script again."

	export DOTNET_CLI_TELEMETRY_OPTOUT="${DOTNET_CLI_TELEMETRY_OPTOUT:-1}"
	export DOTNET_NOLOGO=1

	info "Restoring packages (WebExpress framework included)"
	dotnet restore "$solution" -p:Configuration="$configuration" < /dev/null \
		|| fail "dotnet restore failed (see the output above)." \
			"Check the connection to nuget.org and the package sources (dotnet nuget list source)."

	info "Compiling all projects ($configuration)"
	dotnet build "$solution" --configuration "$configuration" --no-restore < /dev/null \
		|| fail "dotnet build failed (see the output above)." \
			"Report it at https://github.com/kleenestar-project/KleeneStar/issues with the output."

	# --- signing key and start script ---------------------------------------------
	# The shipped settings carry a signing key that is published with the source. Every
	# installation gets a key of its own instead, kept in kleenestar.env in the workspace folder
	# (no repository, so it never blocks an update or lands in a commit) and handed to the server
	# as WEBEXPRESS_WebExpress__Authentication__SigningKey, which wins over the settings files.

	local key_file="$workspace/kleenestar.env"
	if grep -q '^KLEENESTAR_SIGNING_KEY=.\+' "$key_file" 2>/dev/null; then
		info "Keeping the signing key in $key_file"
	else
		info "Generating a signing key of this installation in $key_file"
		local key
		if command -v openssl >/dev/null 2>&1; then
			key="$(openssl rand -base64 32)"
		else
			key="$(head -c 32 /dev/urandom | base64 | tr -d '\n')"
		fi
		[ -n "$key" ] || fail "No signing key could be generated." "Install openssl and run this script again."
		(
			umask 077
			cat > "$key_file" <<KEYFILE
# Generated by install.sh. Signing key of the sign-in tokens of this installation, handed to
# KleeneStar as WEBEXPRESS_WebExpress__Authentication__SigningKey by start.sh. Keep it secret;
# changing it signs every user out.
KLEENESTAR_SIGNING_KEY=$key
KEYFILE
		)
	fi
	chmod 600 "$key_file" 2>/dev/null || true

	local start_script="$workspace/start.sh"
	info "Writing $start_script"
	cat > "$start_script" <<STARTSCRIPT
#!/usr/bin/env bash
# Generated by install.sh - run the installer again instead of editing this file.
# Starts KleeneStar with the signing key of this installation (kleenestar.env). Arguments are
# passed on to 'dotnet run'.
set -euo pipefail
workspace="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
key="\$(sed -n 's/^KLEENESTAR_SIGNING_KEY=//p' "\$workspace/kleenestar.env" 2>/dev/null | tr -d '\r' | head -n 1)"
if [ -z "\$key" ]; then
	echo "ERROR: \$workspace/kleenestar.env carries no KLEENESTAR_SIGNING_KEY; run install.sh again." >&2
	exit 1
fi
export WEBEXPRESS_WebExpress__Authentication__SigningKey="\$key"
# the shipped settings listen on port 80, which needs root on Linux
if [ "\$(uname -s)" = "Linux" ] && [ "\$(id -u)" != 0 ] && [ -z "\${WEBEXPRESS_WebExpress__Endpoints__0__Uri:-}" ]; then
	export WEBEXPRESS_WebExpress__Endpoints__0__Uri="http://localhost:8080/"
	export WEBEXPRESS_WebExpress__ExternalUri="\${WEBEXPRESS_WebExpress__ExternalUri:-http://localhost:8080/}"
fi
cd "\$workspace/KleeneStar/src/KleeneStar"
exec dotnet run -c $configuration "\$@"
STARTSCRIPT
	chmod +x "$start_script"

	# --- done -------------------------------------------------------------------

	local address="http://localhost/"
	if [ "$os" = "linux" ] && [ "$(id -u)" != 0 ]; then
		address="http://localhost:8080/ (port 80 needs root; start.sh moves it to 8080)"
	fi

	printf '\n%sKleeneStar is installed and compiled.%s\n\n' "$c_bold" "$c_reset"
	echo "  Workspace:    $workspace"
	echo "  Start:        \"$start_script\""
	echo "  Address:      $address"
	echo "  Sign in:      admin / kleenestar (change the password after the first sign-in)"
	echo "  Signing key:  $key_file (kept on every run)"
	echo "  IDE / manual: set WEBEXPRESS_WebExpress__Authentication__SigningKey to the key in that file;"
	echo "                without it the published key of the shipped settings is used"
	echo "  Update:       run this script again"
	echo

	if [ "$run" = 1 ]; then
		info "Starting KleeneStar (Ctrl+C stops it)"
		if [ -r /dev/tty ]; then
			exec "$start_script" < /dev/tty
		else
			exec "$start_script"
		fi
	fi
}

main "$@"
