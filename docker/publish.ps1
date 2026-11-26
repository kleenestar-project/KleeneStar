#requires -Version 5.1
<#
.SYNOPSIS
Builds and pushes the KleeneStar image for linux/amd64 and linux/arm64.

.DESCRIPTION
The build context is the workspace folder that holds the KleeneStar repositories side by side
(set up by ..\install.ps1); the Dockerfile is KleeneStar\Dockerfile inside it.

.PARAMETER Version
Version number of the tag. Default: <Version> of src\KleeneStar\KleeneStar.csproj.

.PARAMETER Suffix
Tag suffix. Default: alpha when -Version is omitted, none when -Version is given.

.PARAMETER Repository
Image name in the registry. Default: rschwarzer/kleenestar.

.PARAMETER Feed
Folder with WebExpress *.nupkg packages that nuget.org does not carry.
Default: $env:WEBEXPRESS_FEED, else docker\feed (empty - everything from nuget.org).

.EXAMPLE
./docker/publish.ps1 -Version 0.0.4
#>
param(
	[string]$Version = '',
	[string]$Suffix = '',
	[string]$Repository = 'rschwarzer/kleenestar',
	[string]$Feed = $(if ($env:WEBEXPRESS_FEED) { $env:WEBEXPRESS_FEED } else { Join-Path $PSScriptRoot 'feed' })
)

$ErrorActionPreference = 'Stop'

function Stop-Publish([string]$Message, [string[]]$Instructions = @()) {
	Write-Host "Error: $Message" -ForegroundColor Red
	foreach ($line in $Instructions) { Write-Host "       $line" }
	exit 1
}

$repo = Split-Path -Parent $PSScriptRoot
$workspace = Split-Path -Parent $repo

if (-not $Version) {
	$csproj = Get-Content -Raw (Join-Path $repo 'src\KleeneStar\KleeneStar.csproj')
	$Version = if ($csproj -match '<Version>([^<]+)</Version>') { $Matches[1] } else { '0.0.4' }
	if (-not $PSBoundParameters.ContainsKey('Suffix')) { $Suffix = 'alpha' }
}
$tag = if ($Suffix) { "$Version-$Suffix" } else { $Version }

# --- prerequisites ----------------------------------------------------------------------------

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
	Stop-Publish 'Docker is not installed.' @('Install Docker Desktop: winget install --id Docker.DockerDesktop -e')
}
$ErrorActionPreference = 'Continue'
& docker buildx version *> $null
if ($LASTEXITCODE -ne 0) {
	Stop-Publish 'The Docker Buildx plugin is missing.' @('It is part of Docker Desktop; reinstall or update Docker Desktop.')
}
& docker info *> $null
if ($LASTEXITCODE -ne 0) {
	Stop-Publish 'The Docker daemon does not answer.' @('Start Docker Desktop and run this script again.')
}

$repos = @('KleeneStar', 'KleeneStar.Model', 'KleeneStar.Core', 'KleeneStar.Portal', 'KleeneStar.Templates',
	'KleeneStar.Automation', 'KleeneStar.Integration', 'KleeneStar.Ldap', 'KleeneStar.Calendar', 'KleeneStar.Poll', 'KleeneStar.Theme', 'KleeneStar.Help', 'KleeneStar.Seeder')
foreach ($name in $repos) {
	if (-not (Test-Path (Join-Path $workspace "$name\src"))) {
		Stop-Publish "The repository $name is missing in $workspace." @(
			'The image is built from all KleeneStar repositories side by side.',
			"Set them up with: $(Join-Path $repo 'install.ps1') -Dir $workspace")
	}
}
if (-not $env:WEBEXPRESS_FEED -and -not $PSBoundParameters.ContainsKey('Feed')) { New-Item -ItemType Directory -Force -Path $Feed | Out-Null }
if (-not (Test-Path $Feed -PathType Container)) {
	Stop-Publish "The package folder '$Feed' does not exist." @('Set -Feed or WEBEXPRESS_FEED to an existing folder (it may be empty).')
}

# --- build and push ---------------------------------------------------------------------------

# The default "docker" driver cannot build multi-platform images.
if (-not (& docker buildx ls | Select-String '^multiarch')) {
	& docker buildx create --name multiarch --driver docker-container | Out-Null
	if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

& docker buildx build `
	--builder multiarch `
	--platform linux/amd64,linux/arm64 `
	--build-context "nuget=$Feed" `
	-f (Join-Path $repo 'Dockerfile') `
	-t "${Repository}:$tag" `
	--push `
	$workspace
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& docker buildx imagetools inspect "${Repository}:$tag"
exit $LASTEXITCODE
