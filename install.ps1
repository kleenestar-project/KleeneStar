<#
.SYNOPSIS
	KleeneStar install script for Windows (Windows PowerShell 5.1 or PowerShell 7).

.DESCRIPTION
	Clones (or updates) every KleeneStar repository side by side into one workspace folder,
	restores the NuGet packages (the WebExpress framework included) and compiles the whole
	solution: the host, all plugins and the test projects. Every prerequisite is checked first;
	when one is missing the script stops, names it and says how to install it.

	Each parameter has an environment variable of the same meaning, which is the way to pass
	options when the script is piped into Invoke-Expression:
	  KLEENESTAR_DIR, KLEENESTAR_BRANCH, KLEENESTAR_CONFIGURATION,
	  KLEENESTAR_WITH_WEBEXPRESS=1, KLEENESTAR_RUN=1

.PARAMETER Dir
	Workspace folder. Default: .\KleeneStar, or the current folder when it already is a workspace.

.PARAMETER Branch
	Branch of every repository. Default: develop.

.PARAMETER Configuration
	Debug, Release or DebugLocal. Default: Debug.

.PARAMETER WithWebExpress
	Also clone the WebExpress framework sources (needed for DebugLocal only).

.PARAMETER Run
	Start KleeneStar after the build.

.EXAMPLE
	irm https://raw.githubusercontent.com/kleenestar-project/KleeneStar/develop/install.ps1 | iex

.EXAMPLE
	curl.exe -fsSL https://raw.githubusercontent.com/kleenestar-project/KleeneStar/develop/install.ps1 -o install.ps1
	powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -Run

.EXAMPLE
	& ([scriptblock]::Create((irm https://raw.githubusercontent.com/kleenestar-project/KleeneStar/develop/install.ps1))) -Dir C:\src\KleeneStar -Run
#>
[CmdletBinding()]
param(
	[string]$Dir = $env:KLEENESTAR_DIR,
	[string]$Branch = $(if ($env:KLEENESTAR_BRANCH) { $env:KLEENESTAR_BRANCH } else { 'develop' }),
	[string]$Configuration = $(if ($env:KLEENESTAR_CONFIGURATION) { $env:KLEENESTAR_CONFIGURATION } else { 'Debug' }),
	[switch]$WithWebExpress = $($env:KLEENESTAR_WITH_WEBEXPRESS -eq '1'),
	[switch]$Run = $($env:KLEENESTAR_RUN -eq '1')
)

# Run through Invoke-Expression, this script shares the caller's session: it must not call
# 'exit' (that would close the window) and must not leave preferences changed. Everything
# therefore happens inside one function, and only a run from a file sets an exit code.
$kleeneStarInstallFromFile = [bool]$MyInvocation.MyCommand.Path

function Invoke-KleeneStarInstall {
	param([string]$Dir, [string]$Branch, [string]$Configuration, [bool]$WithWebExpress, [bool]$Run)

	# native commands report through $LASTEXITCODE; 'Stop' would turn their stderr into errors
	$ErrorActionPreference = 'Continue'
	$ProgressPreference = 'SilentlyContinue'

	$orgUrl = 'https://github.com/kleenestar-project'
	$webExpressUrl = 'https://github.com/ReneSchwarzer'
	$repos = @(
		'KleeneStar',
		'KleeneStar.Model',
		'KleeneStar.Core',
		'KleeneStar.Portal',
		'KleeneStar.Templates',
		'KleeneStar.Automation',
		'KleeneStar.Integration',
		'KleeneStar.Ldap',
		'KleeneStar.Calendar',
		'KleeneStar.Poll',
		'KleeneStar.Theme',
		'KleeneStar.Help',
		'KleeneStar.Seeder'
	)
	$webExpressRepos = @('WebExpress.WebCore', 'WebExpress.WebIndex', 'WebExpress.WebUI', 'WebExpress.WebApp')
	$dotnetMajor = 10
	$minFreeMb = 3072

	$onWindows = ($PSVersionTable.PSVersion.Major -lt 6) -or $IsWindows

	function Write-Info([string]$Message) { Write-Host '==> ' -ForegroundColor Green -NoNewline; Write-Host $Message }
	function Write-Warn([string]$Message) { Write-Host "==> $Message" -ForegroundColor Yellow }
	function Stop-Install([string]$Message, [string[]]$Instructions = @()) {
		Write-Host ''
		Write-Host "ERROR: $Message" -ForegroundColor Red
		foreach ($line in $Instructions) { Write-Host "       $line" }
		Write-Host ''
		throw 'KleeneStarInstallAborted'
	}

	# Commands that install a missing piece on this platform. $What: git | sdk | runtime
	function Get-Hint([string]$What) {
		$hasWinget = [bool](Get-Command winget -ErrorAction SilentlyContinue)
		if (-not $onWindows) {
			switch ($What) {
				'git' { return @('Install git with the package manager of your system.') }
				default {
					return @(
						"Install the .NET $dotnetMajor SDK and the ASP.NET Core $dotnetMajor runtime: https://dot.net/download",
						'install.sh names the exact commands for this system.')
				}
			}
		}
		switch ($What) {
			'git' {
				if ($hasWinget) { return @('Install it with:  winget install --id Git.Git -e') }
				return @('Download it from https://git-scm.com/download/win')
			}
			'sdk' {
				if ($hasWinget) { return @("Install it with:  winget install --id Microsoft.DotNet.SDK.$dotnetMajor -e") }
				return @("Download the .NET $dotnetMajor SDK from https://dot.net/download")
			}
			'runtime' {
				if ($hasWinget) { return @("Install it with:  winget install --id Microsoft.DotNet.AspNetCore.$dotnetMajor -e") }
				return @("Download the ASP.NET Core Runtime $dotnetMajor from https://dot.net/download")
			}
		}
	}

	# A tool installed in this session is not on PATH until a new window is opened.
	function Find-Tool([string]$Name, [string[]]$Candidates) {
		if (Get-Command $Name -ErrorAction SilentlyContinue) { return $true }
		foreach ($candidate in $Candidates) {
			if ($candidate -and (Test-Path $candidate)) {
				$env:PATH = (Split-Path $candidate) + [IO.Path]::PathSeparator + $env:PATH
				Write-Warn "Using $candidate (it is not on PATH in this window)."
				return $true
			}
		}
		return $false
	}

	# --- options -----------------------------------------------------------------

	switch ($Configuration) {
		{ $_ -in 'Debug', 'Release' } { break }
		'DebugLocal' { $WithWebExpress = $true; break }
		default { Stop-Install "Unknown configuration '$Configuration'." @('Use Debug, Release or DebugLocal.') }
	}

	# --- prerequisites -----------------------------------------------------------

	Write-Info 'Checking prerequisites'

	if ($PSVersionTable.PSVersion -lt [version]'5.1') {
		Stop-Install "PowerShell $($PSVersionTable.PSVersion) is too old." @(
			'Use Windows PowerShell 5.1 or PowerShell 7 (winget install --id Microsoft.PowerShell -e).')
	}
	if ($PSVersionTable.PSVersion.Major -lt 6) {
		# Windows PowerShell 5.1 may still default to TLS 1.0, which GitHub and nuget.org refuse
		[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
	}

	# git
	if (-not (Find-Tool 'git' @("$env:ProgramFiles\Git\cmd\git.exe", "$env:LOCALAPPDATA\Programs\Git\cmd\git.exe"))) {
		Stop-Install 'git is not installed.' (@('KleeneStar is cloned from GitHub with git.') + (Get-Hint 'git') + @('Then open a new window and run this script again.'))
	}

	# dotnet
	$dotnetCandidates = @("$env:ProgramFiles\dotnet\dotnet.exe", "$env:LOCALAPPDATA\Microsoft\dotnet\dotnet.exe")
	if ($env:HOME) { $dotnetCandidates += (Join-Path $env:HOME '.dotnet/dotnet') }
	if (-not (Find-Tool 'dotnet' $dotnetCandidates)) {
		Stop-Install 'The .NET SDK is not installed.' (@(
			"KleeneStar needs the .NET $dotnetMajor SDK (or newer) and the ASP.NET Core $dotnetMajor runtime.") +
			(Get-Hint 'sdk') + @('Then open a new window and run this script again.'))
	}

	$sdks = @(& dotnet --list-sdks 2>&1 | ForEach-Object { "$_" })
	if ($LASTEXITCODE -ne 0) {
		Stop-Install 'dotnet is installed but does not start:' ($sdks + @('Repair or reinstall .NET from https://dot.net/download.'))
	}
	$sdkOk = $false
	foreach ($sdk in $sdks) {
		$major = 0
		if ([int]::TryParse(($sdk -split '\.')[0], [ref]$major) -and $major -ge $dotnetMajor) { $sdkOk = $true }
	}
	if (-not $sdkOk) {
		Stop-Install "No .NET SDK $dotnetMajor or newer found." (@(
			"Installed SDKs: $(($sdks | ForEach-Object { ($_ -split ' ')[0] }) -join ', ')") +
			(Get-Hint 'sdk') + @('Then open a new window and run this script again.'))
	}

	$runtimes = @(& dotnet --list-runtimes 2>$null | ForEach-Object { "$_" })
	if (-not ($runtimes | Where-Object { $_ -like "Microsoft.AspNetCore.App $dotnetMajor.*" })) {
		Stop-Install "The ASP.NET Core $dotnetMajor runtime is not installed." (@(
			"KleeneStar targets net$dotnetMajor.0; a newer runtime alone cannot run it.") +
			(Get-Hint 'runtime') + @('Then run this script again.'))
	}

	# network
	$env:GIT_TERMINAL_PROMPT = '0'
	& git ls-remote --heads "$orgUrl/KleeneStar.git" 2>$null | Out-Null
	if ($LASTEXITCODE -ne 0) {
		Stop-Install "GitHub cannot be reached ($orgUrl)." @(
			'Check the internet connection and, behind a proxy, set it for git (git config --global http.proxy <url>).',
			'Then run this script again.')
	}
	try {
		Invoke-WebRequest -Uri 'https://api.nuget.org/v3/index.json' -UseBasicParsing -TimeoutSec 20 | Out-Null
	} catch {
		Stop-Install 'nuget.org cannot be reached.' @(
			'The WebExpress framework and every other package are restored from https://api.nuget.org.',
			'Check the internet connection or the proxy settings, then run this script again.')
	}

	# workspace folder: the current folder when it already is one, else .\KleeneStar
	if (-not $Dir) {
		if (Test-Path (Join-Path (Get-Location).Path 'KleeneStar\src\KleeneStar.slnx')) { $Dir = '.' } else { $Dir = 'KleeneStar' }
	}
	try {
		$workspace = (New-Item -ItemType Directory -Force -Path $Dir -ErrorAction Stop).FullName
	} catch {
		Stop-Install "The folder '$Dir' cannot be created." @('Choose another one with -Dir <path>.')
	}
	# pointed at the host repository itself: its parent is the workspace
	if (Test-Path (Join-Path $workspace '.git')) {
		if (Test-Path (Join-Path $workspace 'src\KleeneStar.slnx')) {
			$workspace = Split-Path $workspace -Parent
		} else {
			Stop-Install "'$workspace' is a git repository, not a workspace folder." @(
				'KleeneStar consists of several repositories next to each other.',
				'Choose an empty or new folder with -Dir <path>.')
		}
	}
	try {
		$probe = Join-Path $workspace ".kleenestar-install-$PID"
		New-Item -ItemType File -Path $probe -Force -ErrorAction Stop | Out-Null
		Remove-Item $probe -Force -ErrorAction SilentlyContinue
	} catch {
		Stop-Install "The folder '$workspace' is not writable." @('Choose another one with -Dir <path>.')
	}

	$allRepos = $repos
	if ($WithWebExpress) { $allRepos += $webExpressRepos }
	foreach ($repo in $allRepos) {
		$path = Join-Path $workspace $repo
		if ((Test-Path $path) -and -not (Test-Path (Join-Path $path '.git')) -and (Get-ChildItem $path -Force -ErrorAction SilentlyContinue)) {
			Stop-Install "'$path' exists but is no git repository." @(
				'Move or delete it, or choose another folder with -Dir <path>.')
		}
	}

	# disk space
	try {
		$drive = New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($workspace))
		$freeMb = [math]::Floor($drive.AvailableFreeSpace / 1MB)
		if ($freeMb -lt $minFreeMb) {
			Stop-Install "Not enough free disk space on $($drive.Name): $freeMb MB." @(
				"Sources, packages and build output need about $minFreeMb MB.",
				'Free some space or choose another folder with -Dir <path>.')
		}
	} catch {
		if ("$_" -eq 'KleeneStarInstallAborted') { throw }
		Write-Warn 'Free disk space could not be determined.'
	}

	$gitVersion = ((& git --version) -split ' ')[2]
	$sdkVersion = (& dotnet --version)
	Write-Info "git $gitVersion, .NET SDK $sdkVersion"
	Write-Info "Workspace: $workspace (branch: $Branch, configuration: $Configuration)"

	# --- clone / update ----------------------------------------------------------
	# The repositories reference each other through relative project references
	# (..\..\..\KleeneStar.Core\...), so they must live side by side in one folder.

	function Sync-Repository([string]$Name, [string]$Url) {
		$path = Join-Path $workspace $Name
		if (Test-Path (Join-Path $path '.git')) {
			$changes = & git -C $path status --porcelain --untracked-files=no
			if ($changes) { Write-Warn "$Name has local changes, left as it is"; return }

			Write-Info "Updating $Name"
			& git -C $path fetch --quiet origin 2>$null
			if ($LASTEXITCODE -ne 0) { Write-Warn "Could not fetch $Name, building the local state"; return }

			& git -C $path show-ref --verify --quiet "refs/remotes/origin/$Branch"
			if ($LASTEXITCODE -ne 0) {
				Write-Warn "$Name has no branch '$Branch', staying on $(& git -C $path branch --show-current)"
				return
			}
			& git -C $path checkout --quiet $Branch 2>$null
			if ($LASTEXITCODE -ne 0) {
				& git -C $path checkout --quiet -b $Branch --track "origin/$Branch" 2>$null
				if ($LASTEXITCODE -ne 0) { Write-Warn "Could not check out $Branch in $Name"; return }
			}
			& git -C $path merge --ff-only --quiet "origin/$Branch" 2>$null
			if ($LASTEXITCODE -ne 0) { Write-Warn "$Name cannot be fast-forwarded to origin/$Branch, left as it is" }
		} else {
			Write-Info "Cloning $Name"
			$cloneArgs = @('-c', 'core.longpaths=true', 'clone', '--quiet')
			& git ls-remote --exit-code --heads $Url $Branch 2>$null | Out-Null
			if ($LASTEXITCODE -eq 0) {
				$cloneArgs += @('--branch', $Branch)
			} else {
				Write-Warn "$Name has no branch '$Branch', cloning its default branch"
			}
			& git @cloneArgs $Url $path
			if ($LASTEXITCODE -ne 0) {
				Stop-Install "Cloning $Url failed." @('Run the script again; it continues where it stopped.')
			}
			if ($onWindows) { & git -C $path config core.longpaths true }
		}
	}

	foreach ($repo in $repos) { Sync-Repository $repo "$orgUrl/$repo.git" }
	if ($WithWebExpress) {
		foreach ($repo in $webExpressRepos) { Sync-Repository $repo "$webExpressUrl/$repo.git" }
	}

	# --- restore & build ---------------------------------------------------------

	$solution = Join-Path $workspace 'KleeneStar\src\KleeneStar.slnx'
	if (-not (Test-Path $solution)) {
		Stop-Install "The solution '$solution' is missing." @(
			"The repository KleeneStar is incomplete; delete '$(Join-Path $workspace 'KleeneStar')' and run the script again.")
	}

	if (-not $env:DOTNET_CLI_TELEMETRY_OPTOUT) { $env:DOTNET_CLI_TELEMETRY_OPTOUT = '1' }
	$env:DOTNET_NOLOGO = '1'

	Write-Info 'Restoring packages (WebExpress framework included)'
	& dotnet restore $solution "-p:Configuration=$Configuration" | Out-Host
	if ($LASTEXITCODE -ne 0) {
		Stop-Install 'dotnet restore failed (see the output above).' @(
			'Check the connection to nuget.org and the package sources (dotnet nuget list source).')
	}

	Write-Info "Compiling all projects ($Configuration)"
	& dotnet build $solution --configuration $Configuration --no-restore | Out-Host
	if ($LASTEXITCODE -ne 0) {
		Stop-Install 'dotnet build failed (see the output above).' @(
			'Report it at https://github.com/kleenestar-project/KleeneStar/issues with the output.')
	}

	# --- signing key and start script --------------------------------------------
	# The shipped settings carry a signing key that is published with the source. Every
	# installation gets a key of its own instead, kept in kleenestar.env in the workspace folder
	# (no repository, so it never blocks an update or lands in a commit) and handed to the server
	# as WEBEXPRESS_WebExpress__Authentication__SigningKey, which wins over the settings files.

	$keyFile = Join-Path $workspace 'kleenestar.env'
	$hasKey = (Test-Path $keyFile) -and (Select-String -Path $keyFile -Pattern '^KLEENESTAR_SIGNING_KEY=.+' -Quiet)
	if ($hasKey) {
		Write-Info "Keeping the signing key in $keyFile"
	} else {
		Write-Info "Generating a signing key of this installation in $keyFile"
		$bytes = New-Object byte[] 32
		$rng = [Security.Cryptography.RandomNumberGenerator]::Create()
		try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
		$key = [Convert]::ToBase64String($bytes)
		$content = @(
			'# Generated by install.ps1. Signing key of the sign-in tokens of this installation, handed to',
			'# KleeneStar as WEBEXPRESS_WebExpress__Authentication__SigningKey by start.ps1. Keep it secret;',
			'# changing it signs every user out.',
			"KLEENESTAR_SIGNING_KEY=$key")
		[IO.File]::WriteAllLines($keyFile, [string[]]$content)
		if ($onWindows) {
			# readable by the current user only
			& icacls $keyFile /inheritance:r /grant:r "$($env:USERNAME):(F)" *> $null
			if ($LASTEXITCODE -ne 0) { Write-Warn "The access rights of $keyFile could not be restricted." }
		}
	}

	$startScript = Join-Path $workspace 'start.ps1'
	Write-Info "Writing $startScript"
	$startContent = @'
# Generated by install.ps1 - run the installer again instead of editing this file.
# Starts KleeneStar with the signing key of this installation (kleenestar.env). Arguments are
# passed on to 'dotnet run'.
$workspace = $PSScriptRoot
$keyFile = Join-Path $workspace 'kleenestar.env'
$key = $null
if (Test-Path $keyFile) {
	foreach ($line in Get-Content $keyFile) {
		if ($line -match '^KLEENESTAR_SIGNING_KEY=(.+)$') { $key = $Matches[1].Trim(); break }
	}
}
if (-not $key) {
	Write-Host "ERROR: $keyFile carries no KLEENESTAR_SIGNING_KEY; run install.ps1 again." -ForegroundColor Red
	exit 1
}
$previous = $env:WEBEXPRESS_WebExpress__Authentication__SigningKey
$env:WEBEXPRESS_WebExpress__Authentication__SigningKey = $key
Push-Location (Join-Path $workspace 'KleeneStar\src\KleeneStar')
try {
	& dotnet run -c __CONFIGURATION__ @args
} finally {
	Pop-Location
	$env:WEBEXPRESS_WebExpress__Authentication__SigningKey = $previous
}
'@
	[IO.File]::WriteAllText($startScript, $startContent.Replace('__CONFIGURATION__', $Configuration))
	if ($onWindows) {
		$startCmd = Join-Path $workspace 'start.cmd'
		[IO.File]::WriteAllText($startCmd, "@rem Generated by install.ps1: starts KleeneStar (double-click or run from cmd).`r`n@powershell -NoProfile -ExecutionPolicy Bypass -File `"%~dp0start.ps1`" %*`r`n")
	}

	# --- done --------------------------------------------------------------------

	Write-Host ''
	Write-Host 'KleeneStar is installed and compiled.' -ForegroundColor Green
	Write-Host ''
	Write-Host "  Workspace:    $workspace"
	if ($onWindows) {
		Write-Host "  Start:        $(Join-Path $workspace 'start.cmd')   (or start.ps1)"
	} else {
		Write-Host "  Start:        $startScript"
	}
	Write-Host '  Address:      http://localhost/'
	Write-Host '  Sign in:      admin / kleenestar (change the password after the first sign-in)'
	Write-Host "  Signing key:  $keyFile (kept on every run)"
	Write-Host '  IDE / manual: set WEBEXPRESS_WebExpress__Authentication__SigningKey to the key in that file;'
	Write-Host '                without it the published key of the shipped settings is used'
	Write-Host '  Update:       run this script again'
	Write-Host ''

	if ($Run) {
		Write-Info 'Starting KleeneStar (Ctrl+C stops it)'
		# a new process: the execution policy of this session may refuse a script file
		& (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File $startScript
	}
}

try {
	Invoke-KleeneStarInstall -Dir $Dir -Branch $Branch -Configuration $Configuration -WithWebExpress $WithWebExpress.IsPresent -Run $Run.IsPresent
	$global:LASTEXITCODE = 0
} catch {
	if ("$_" -ne 'KleeneStarInstallAborted') {
		Write-Host "ERROR: $_" -ForegroundColor Red
	}
	$global:LASTEXITCODE = 1
	if ($kleeneStarInstallFromFile) { exit 1 }
} finally {
	Remove-Item function:Invoke-KleeneStarInstall -ErrorAction SilentlyContinue
	Remove-Variable kleeneStarInstallFromFile -ErrorAction SilentlyContinue
}
