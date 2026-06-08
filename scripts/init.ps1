# ------------------------------------------------------------------------------
# Windows Initialization Script (PowerShell)
# ------------------------------------------------------------------------------
# Usage: Run as Administrator
#   Set-ExecutionPolicy Bypass -Scope Process -Force
#   .\init.ps1
#
#   Switches: -SkipChocolatey -SkipPowerShellModules  -SkipOhMyPosh -SkipProfile -SkipFonts
#             -SkipTerminalConfig -SkipAgents -UpdatePackages -RemoveOrphaned
# ------------------------------------------------------------------------------

#Requires -Version 5.1

param(
    [switch]$SkipChocolatey,
    [switch]$SkipPowerShellModules ,
    [switch]$SkipOhMyPosh,
    [switch]$SkipProfile,
    [switch]$SkipFonts,
    [switch]$SkipTerminalConfig,
    [switch]$SkipAgents,
    [switch]$UpdatePackages,
    [switch]$RemoveOrphaned
)

# Strict mode for better error handling
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------

# PowerShell Gallery Modules to install
$PSGalleryModules = @(
    @{ Name = "PSReadLine"; Description = "Enhanced command-line editing" }
    @{ Name = "posh-git"; Description = "Git status in prompt" }
    @{ Name = "Terminal-Icons"; Description = "File/folder icons in terminal" }
    @{ Name = "z"; Description = "Directory jumping" }
    @{ Name = "PSFzf"; Description = "Fuzzy finder integration" }
)

# Oh My Posh theme
$OhMyPoshTheme = "tokyonight_storm"

# Max number of timestamped backups to keep per file
$MaxBackupsToKeep = 3

# ------------------------------------------------------------------------------
# Installation Tracking
# ------------------------------------------------------------------------------

$script:Installed = [System.Collections.ArrayList]::new()
$script:Skipped = [System.Collections.ArrayList]::new()
$script:Failed = [System.Collections.ArrayList]::new()
$script:Removed = [System.Collections.ArrayList]::new()
$script:Updated = [System.Collections.ArrayList]::new()

# ------------------------------------------------------------------------------
# Logging Functions
# ------------------------------------------------------------------------------

function Get-Timestamp {
    return Get-Date -Format "HH:mm:ss"
}

function Write-LogInfo {
    param([string]$Message)
    Write-Host "[$(Get-Timestamp)] [INFO] $Message" -ForegroundColor Cyan
}

function Write-LogSuccess {
    param([string]$Message)
    Write-Host "[$(Get-Timestamp)] [SUCCESS] $Message" -ForegroundColor Green
}

function Write-LogWarning {
    param([string]$Message)
    Write-Host "[$(Get-Timestamp)] [WARN] $Message" -ForegroundColor Yellow
}

function Write-LogError {
    param([string]$Message)
    Write-Host "[$(Get-Timestamp)] [ERROR] $Message" -ForegroundColor Red
}

function Write-HorizontalRule {
    param([ConsoleColor]$Color = 'Gray')

    $width = try {
        if ($Host.UI.RawUI.WindowSize.Width -gt 0) {
            $Host.UI.RawUI.WindowSize.Width
        }
        elseif ([Console]::WindowWidth -gt 0) {
            [Console]::WindowWidth
        }
        else {
            80
        }
    }
    catch {
        80
    }

    Write-Host ('─' * $width) -ForegroundColor $Color
}

# ------------------------------------------------------------------------------
# Backup Helpers
# ------------------------------------------------------------------------------

function Remove-OldBackups {
    param(
        [string]$Path,        # original file; backups are "$Path.backup.*"
        [int]$KeepLast = 3
    )

    $dir = Split-Path -Parent $Path
    $leaf = Split-Path -Leaf $Path

    $backups = Get-ChildItem -Path $dir -Filter "$leaf.backup.*" -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending

    if ($backups.Count -gt $KeepLast) {
        foreach ($old in ($backups | Select-Object -Skip $KeepLast)) {
            Remove-Item $old.FullName -Force -ErrorAction SilentlyContinue
            Write-LogInfo "Pruned old backup: $($old.Name)"
        }
    }
}

# ------------------------------------------------------------------------------
# ASCII Banner
# ------------------------------------------------------------------------------

function Show-Banner {
    $banner = @"

                  __                __
   __          __/\ \__            /\ \
  /\_\    ___ /\_\ \ ,_\       ____\ \ \___
  \/\ \ /' _ `\/\ \ \ \/      /',__\\ \  _ `\
   \ \ \/\ \/\ \ \ \ \ \_  __/\__, `\\ \ \ \ \
    \ \_\ \_\ \_\ \_\ \__\/\_\/\____/ \ \_\ \_\
     \/_/\/_/\/_/\/_/\/__/\/_/\/___/   \/_/\/_/

"@
    Write-Host $banner -ForegroundColor Red
    Write-Host ""
}

# ------------------------------------------------------------------------------
# Admin Check
# ------------------------------------------------------------------------------

function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Request-AdminElevation {
    if (-not (Test-Administrator)) {
        Write-LogError "This script requires Administrator privileges."
        Write-LogWarning "Please run PowerShell as Administrator and try again."
        Write-Host ""
        exit 1
    }
}

# ------------------------------------------------------------------------------
# Chocolatey Functions
# ------------------------------------------------------------------------------

function Test-Chocolatey {
    try {
        $null = Get-Command choco -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

function Install-Chocolatey {
    Write-LogInfo "Installing Chocolatey..."
    
    try {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        
        # Refresh environment
        $env:ChocolateyInstall = Convert-Path "$((Get-Command choco).Path)\..\.."
        Import-Module "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
        refreshenv | Out-Null
        
        Write-LogSuccess "Chocolatey installed successfully"
        [void]$script:Installed.Add("chocolatey")
        return $true
    }
    catch {
        Write-LogError "Failed to install Chocolatey: $_"
        [void]$script:Failed.Add("chocolatey")
        return $false
    }
}

function Get-InstalledChocolateyPackages {
    try {
        $output = choco list --limit-output 2>$null
        if ($LASTEXITCODE -ne 0) {
            return @()
        }

        $packages = @()
        foreach ($line in $output) {
            if ($line -match '^([^\s|]+)\|') {
                $packageId = $matches[1]
                # Exclude Chocolatey itself
                if ($packageId -ne 'chocolatey') {
                    $packages += $packageId
                }
            }
        }
        
        return $packages
    }
    catch {
        Write-LogWarning "Failed to get installed packages list: $_"
        return @()
    }
}

function Get-InstalledChocolateyPackageMap {
    $map = New-Object 'System.Collections.Hashtable' ([System.StringComparer]::OrdinalIgnoreCase)

    try {
        $output = choco list --limit-output 2>$null
        if ($LASTEXITCODE -ne 0) {
            return $map
        }

        foreach ($line in $output) {
            if ($line -match '^([^\s|]+)\|([^\s|]+)') {
                $map[$matches[1]] = $matches[2]
            }
        }
    }
    catch {
        Write-LogWarning "Failed to get installed packages map: $_"
    }

    return $map
}

function Remove-OrphanedPackages {
    param(
        [string]$ConfigPath
    )
    
    if (-not $RemoveOrphaned) {
        return
    }
    
    Write-LogInfo "Checking for orphaned packages (not in config)..."
    
    if (-not (Test-Path $ConfigPath)) {
        Write-LogError "Chocolatey config not found: $ConfigPath"
        return
    }
    
    try {
        # Get packages from config
        [xml]$config = Get-Content $ConfigPath
        $configPackages = @{}
        foreach ($pkg in $config.packages.package) {
            $configPackages[$pkg.id] = $true
        }
        
        # Get installed packages
        $installedPackages = Get-InstalledChocolateyPackages
        
        # Find orphaned packages (installed but not in config)
        $orphaned = @()
        foreach ($installed in $installedPackages) {
            if (-not $configPackages.ContainsKey($installed)) {
                $orphaned += $installed
            }
        }
        
        if ($orphaned.Count -eq 0) {
            Write-LogInfo "No orphaned packages found"
            return
        }
        
        Write-LogInfo "Found $($orphaned.Count) orphaned package(s) to remove"
        
        foreach ($packageId in $orphaned) {
            Write-LogInfo "Removing orphaned package: $packageId"
            
            try {
                $result = choco uninstall $packageId -y --no-progress 2>&1
                
                if ($LASTEXITCODE -eq 0) {
                    Write-LogSuccess "$packageId removed"
                    [void]$script:Removed.Add($packageId)
                }
                else {
                    Write-LogWarning "$packageId could not be removed (may have dependencies)"
                }
            }
            catch {
                Write-LogWarning "Failed to remove $packageId : $_"
            }
        }
        
        Write-LogSuccess "Orphaned package cleanup complete"
    }
    catch {
        Write-LogError "Failed to remove orphaned packages: $_"
    }
}

function Install-ChocolateyPackages {
    param(
        [string]$ConfigPath
    )
    
    Write-LogInfo "Installing Chocolatey packages from config..."
    
    if (-not (Test-Path $ConfigPath)) {
        Write-LogError "Chocolatey config not found: $ConfigPath"
        [void]$script:Failed.Add("chocolatey-packages")
        return $false
    }
    
    try {
        # Parse the config to get package names
        [xml]$config = Get-Content $ConfigPath
        $packages = $config.packages.package
        $totalPackages = $packages.Count
        
        Write-LogInfo "Found $totalPackages packages in config"
        
        # Single discovery call: ask Chocolatey once for everything installed.
        $installedMap = Get-InstalledChocolateyPackageMap
        
        $toProcess = @()
        $installedCount = 0
        $updateCount = 0
        foreach ($pkg in $packages) {
            $installedVersion = $installedMap[$pkg.id]
            if ($null -ne $installedVersion) {
                $installedCount++
                if ($UpdatePackages -and $installedVersion -ne $pkg.version) {
                    $updateCount++
                    $toProcess += $pkg
                }
                else {
                    [void]$script:Skipped.Add($pkg.id)
                }
            }
            else {
                $toProcess += $pkg
            }
        }
        
        $missingCount = $totalPackages - $installedCount
        if ($missingCount -eq 0 -and $updateCount -eq 0) {
            Write-LogSuccess "All $totalPackages packages already installed"
        }
        else {
            $summary = "$installedCount/$totalPackages already installed, installing $missingCount missing"
            if ($UpdatePackages) {
                $summary += ", $updateCount to update"
            }
            Write-LogInfo $summary
        }
        
        $totalWork = $toProcess.Count
        $current = 0
        
        foreach ($pkg in $toProcess) {
            $current++
            $packageId = $pkg.id
            $packageVersion = $pkg.version
            $installedVersion = $installedMap[$packageId]
            
            Write-Host "[$current/$totalWork] " -NoNewline -ForegroundColor Gray
            
            if ($null -ne $installedVersion) {
                # Package is installed but version-mismatched under -UpdatePackages
                Write-LogInfo "Updating $packageId from $installedVersion to $packageVersion..."
                
                # Upgrade to config version
                $result = choco upgrade $packageId --version $packageVersion -y --no-progress 2>&1
                
                if ($LASTEXITCODE -eq 0) {
                    Write-LogSuccess "$packageId updated to $packageVersion"
                    [void]$script:Updated.Add("$packageId ($installedVersion -> $packageVersion)")
                }
                else {
                    Write-LogError "$packageId update failed"
                    [void]$script:Failed.Add("$packageId (update)")
                }
                continue
            }
            
            Write-LogInfo "Installing $packageId ($packageVersion)..."
            
            # Install with visible output
            $result = choco install $packageId --version $packageVersion -y --no-progress 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                Write-LogSuccess "$packageId installed"
                [void]$script:Installed.Add($packageId)
            }
            else {
                Write-LogError "$packageId failed"
                [void]$script:Failed.Add($packageId)
            }
        }
        
        return $true
    }
    catch {
        Write-LogError "Failed to install Chocolatey packages: $_"
        [void]$script:Failed.Add("chocolatey-packages")
        return $false
    }
}

# ------------------------------------------------------------------------------
# PowerShell Module Functions
# ------------------------------------------------------------------------------

function Test-ModuleInstalled {
    param([string]$ModuleName)
    
    $module = Get-Module -ListAvailable -Name $ModuleName -ErrorAction SilentlyContinue
    return $null -ne $module
}

function Install-PSModule {
    param(
        [string]$ModuleName,
        [string]$Description,
        [int]$MaxRetries = 3
    )
    
    # Check if already installed
    if (Test-ModuleInstalled -ModuleName $ModuleName) {
        Write-LogWarning "$ModuleName already installed, skipping"
        return $true
    }
    
    $attempt = 0
    while ($attempt -lt $MaxRetries) {
        $attempt++
        Write-LogInfo "Installing $ModuleName ($Description)..."
        
        try {
            # Use TLS 1.2 for PowerShell Gallery Modules
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            
            Install-Module -Name $ModuleName -Force -AllowClobber -Scope CurrentUser -ErrorAction Stop
            Write-LogSuccess "$ModuleName installed"
            [void]$script:Installed.Add($ModuleName)
            return $true
        }
        catch {
            if ($attempt -lt $MaxRetries) {
                Write-LogWarning "Failed to install $ModuleName, retrying ($attempt/$MaxRetries)..."
                Start-Sleep -Seconds 2
            }
        }
    }
    
    Write-LogError "$ModuleName failed after $MaxRetries attempts"
    [void]$script:Failed.Add($ModuleName)
    return $false
}

function Install-AllPSModules {
    Write-LogInfo "Installing PowerShell Gallery Modules..."
    
    # Ensure NuGet provider is available
    try {
        $nuget = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue
        if (-not $nuget -or $nuget.Version -lt [Version]"2.8.5.201") {
            Write-LogInfo "Installing NuGet package provider..."
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
            Write-LogSuccess "NuGet provider installed"
        }
    }
    catch {
        Write-LogWarning "Could not install NuGet provider: $_"
    }
    
    # Set PSGallery as trusted
    try {
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
    }
    catch {
        Write-LogWarning "Could not set PSGallery as trusted"
    }
    
    $allModulesInstalled = @($PSGalleryModules | Where-Object { -not (Test-ModuleInstalled -ModuleName $_.Name) }).Count -eq 0
    if ($allModulesInstalled) {
        Write-LogWarning "All PowerShell modules already installed, skipping"
        return
    }

    foreach ($module in $PSGalleryModules) {
        [void](Install-PSModule -ModuleName $module.Name -Description $module.Description)
    }
}

# ------------------------------------------------------------------------------
# Nerd Fonts Installation
# ------------------------------------------------------------------------------

# Font URLs
$NerdFonts = @{
    # MesloLGS NF - Recommended for Powerlevel10k
    "MesloLGS NF Regular.ttf"      = "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Regular.ttf"
    "MesloLGS NF Bold.ttf"         = "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold.ttf"
    "MesloLGS NF Italic.ttf"       = "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Italic.ttf"
    "MesloLGS NF Bold Italic.ttf"  = "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold%20Italic.ttf"
}

function Test-FontInstalled {
    param([string]$FontName)
    
    $fontsFolder = "$env:windir\Fonts"
    $userFontsFolder = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
    
    # Check system fonts
    if (Test-Path "$fontsFolder\$FontName") {
        return $true
    }
    
    # Check user fonts
    if (Test-Path "$userFontsFolder\$FontName") {
        return $true
    }
    
    return $false
}

function Install-Font {
    param(
        [string]$FontPath,
        [string]$FontName
    )
    
    try {
        $fontsFolder = "$env:windir\Fonts"
        $destination = Join-Path $fontsFolder $FontName
        
        # Copy font to Windows Fonts folder
        Copy-Item -Path $FontPath -Destination $destination -Force
        
        # Register font in registry
        $regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
        $fontRegistryName = $FontName -replace '\.ttf$', ' (TrueType)'
        Set-ItemProperty -Path $regPath -Name $fontRegistryName -Value $FontName -Force
        
        return $true
    }
    catch {
        Write-LogError "Failed to install font $FontName : $_"
        return $false
    }
}

function Install-MesloLGSNF {
    Write-LogInfo "Installing Nerd Fonts (MesloLGS NF)..."

    $allFontsInstalled = @($NerdFonts.Keys | Where-Object { -not (Test-FontInstalled -FontName $_) }).Count -eq 0
    if ($allFontsInstalled) {
        Write-LogWarning "All Nerd Fonts already installed, skipping"
        return $true
    }

    $tempDir = Join-Path $env:TEMP "MesloLGS-NF"
    
    # Create temp directory
    if (-not (Test-Path $tempDir)) {
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    }
    
    $installedCount = 0
    $skippedCount = 0
    
    foreach ($font in $NerdFonts.GetEnumerator()) {
        $fontName = $font.Key
        $fontUrl = $font.Value
        
        # Check if already installed
        if (Test-FontInstalled -FontName $fontName) {
            Write-LogWarning "  $fontName already installed, skipping"
            $skippedCount++
            continue
        }
        
        Write-LogInfo "Downloading $fontName..."
        
        try {
            $fontPath = Join-Path $tempDir $fontName
            
            # Download font
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $fontUrl -OutFile $fontPath -UseBasicParsing
            
            # Install font
            if (Install-Font -FontPath $fontPath -FontName $fontName) {
                Write-LogSuccess "$fontName installed"
                $installedCount++
            }
        }
        catch {
            Write-LogError "  Failed to download/install $fontName : $_"
            [void]$script:Failed.Add("font-$fontName")
        }
    }
    
    # Cleanup temp directory
    if (Test-Path $tempDir) {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    if ($installedCount -gt 0) {
        [void]$script:Installed.Add("MesloLGS-NF ($installedCount fonts)")
    }
    
    return $installedCount -gt 0 -or $skippedCount -gt 0
}

function Install-NerdFonts {
    # Install Nerd Fonts (MesloLGS NF)
    [void](Install-MesloLGSNF)
}

# ------------------------------------------------------------------------------
# Oh My Posh Functions
# ------------------------------------------------------------------------------

function Test-OhMyPosh {
    try {
        $null = Get-Command oh-my-posh -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

function Install-OhMyPosh {
    if (-not (Test-OhMyPosh)) {
        Write-LogInfo "Installing Oh My Posh via Chocolatey..."

        try {
            choco install oh-my-posh -y --no-progress

            # Refresh PATH
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

            if (Test-OhMyPosh) {
                Write-LogSuccess "Oh My Posh installed"
                [void]$script:Installed.Add("oh-my-posh")
            }
            else {
                Write-LogWarning "Oh My Posh installed but may require terminal restart"
                [void]$script:Installed.Add("oh-my-posh")
            }
        }
        catch {
            Write-LogError "Failed to install Oh My Posh: $_"
            [void]$script:Failed.Add("oh-my-posh")
            return $false
        }
    }
    else {
        Write-LogWarning "Oh My Posh already installed, skipping"
    }
    
    # Ensure themes are present (recent oh-my-posh releases ship the binary only)
    Install-OhMyPoshThemes
    
    return $true
}

function Get-OhMyPoshThemesDir {
    # Prefer the path oh-my-posh itself reports
    if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
        try {
            $initOutput = & oh-my-posh init pwsh 2>$null
            $match = $initOutput | Select-String -Pattern 'POSH_THEMES_PATH\s*=\s*"([^"]+)"' | Select-Object -First 1
            if ($match) {
                $reported = $match.Matches[0].Groups[1].Value
                if ($reported) { return $reported }
            }
        }
        catch { }
    }

    if ($env:POSH_THEMES_PATH) { return $env:POSH_THEMES_PATH }

    return (Join-Path $env:LOCALAPPDATA "Programs\oh-my-posh\themes")
}

function Install-OhMyPoshThemes {
    $themesDir = Get-OhMyPoshThemesDir
    $themeFile = Join-Path $themesDir "$OhMyPoshTheme.omp.json"

    if (Test-Path $themeFile) {
        Write-LogSuccess "Theme '$OhMyPoshTheme' is available at: $themesDir"
        $env:POSH_THEMES_PATH = $themesDir
        return $true
    }

    Write-LogInfo "Downloading Oh My Posh themes to: $themesDir"

    try {
        if (-not (Test-Path $themesDir)) {
            New-Item -ItemType Directory -Path $themesDir -Force | Out-Null
        }

        $zipUrl  = "https://github.com/JanDeDobbeleer/oh-my-posh/releases/latest/download/themes.zip"
        $zipPath = Join-Path $env:TEMP "oh-my-posh-themes-$(Get-Random).zip"

        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing -ErrorAction Stop

        $zipSizeKb = [Math]::Round((Get-Item $zipPath).Length / 1KB)
        Write-LogInfo "Downloaded themes.zip ($zipSizeKb KB), extracting..."

        Expand-Archive -Path $zipPath -DestinationPath $themesDir -Force -ErrorAction Stop
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue

        $themeCount = (Get-ChildItem $themesDir -Filter "*.omp.json" -ErrorAction SilentlyContinue).Count

        if (Test-Path $themeFile) {
            Write-LogSuccess "Installed $themeCount Oh My Posh themes (including '$OhMyPoshTheme')"
            $env:POSH_THEMES_PATH = $themesDir
            [void]$script:Installed.Add("oh-my-posh-themes ($themeCount themes)")
            return $true
        }

        Write-LogWarning "Themes extracted ($themeCount files) but configured theme '$OhMyPoshTheme' is not among them"
        $env:POSH_THEMES_PATH = $themesDir
        [void]$script:Installed.Add("oh-my-posh-themes ($themeCount themes, '$OhMyPoshTheme' missing)")
        return $true
    }
    catch {
        Write-LogError "Failed to install Oh My Posh themes: $_"
        [void]$script:Failed.Add("oh-my-posh-themes")
        return $false
    }
}

# ------------------------------------------------------------------------------
# Agents (Pi + omp)
# ------------------------------------------------------------------------------

function Install-Agents {
    Write-LogInfo "Installing Agents (Pi, omp)..."

    # Match the remote-install setup used for the Chocolatey installer so the
    # upstream 'irm | iex' installers behave reliably.
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072

    $agents = @(
        @{ Name = "pi";  Command = "pi";  InstallerUrl = "https://pi.dev/install.ps1" }
        @{ Name = "omp"; Command = "omp"; InstallerUrl = "https://omp.sh/install.ps1" }
    )

    foreach ($agent in $agents) {
        $name = $agent.Name

        try {
            Write-LogInfo "Running $name installer ($($agent.InstallerUrl))..."

            $wasPresent = [bool](Get-Command $agent.Command -ErrorAction SilentlyContinue)

            # Always re-run the official installer; it self-updates if present.
            pwsh -NoProfile -ExecutionPolicy Bypass -Command "irm $($agent.InstallerUrl) | iex"
            if ($LASTEXITCODE -ne 0) { throw "$name installer exited with code $LASTEXITCODE" }

            # Refresh PATH so the freshly installed command resolves in this run.
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

            Write-Host ""
            if (-not (Get-Command $agent.Command -ErrorAction SilentlyContinue)) {
                Write-LogWarning "$name installed but may require terminal restart"
                [void]$script:Installed.Add($name)
            }
            elseif ($wasPresent) {
                Write-LogSuccess "$name already present (re-ran installer for self-update)"
                [void]$script:Updated.Add($name)
            }
            else {
                Write-LogSuccess "$name installed"
                [void]$script:Installed.Add($name)
            }
        }
        catch {
            Write-Host ""
            Write-LogError "Failed to install ${name}: $_"
            [void]$script:Failed.Add($name)
        }
    }
}

# ------------------------------------------------------------------------------
# PowerShell Profile Configuration
# ------------------------------------------------------------------------------

function Update-PowerShellProfile {
    Write-LogInfo "Configuring PowerShell profile..."
    
    $profileDir = Split-Path -Parent $PROFILE
    
    # Create profile directory if it doesn't exist
    if (-not (Test-Path $profileDir)) {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
        Write-LogInfo "Created profile directory: $profileDir"
    }
    
    # Load and hydrate profile template
    $templatePath = Join-Path $PSScriptRoot "templates\profile.ps1"
    if (-not (Test-Path $templatePath)) {
        Write-LogError "Profile template not found: $templatePath"
        [void]$script:Failed.Add("ps-profile")
        return $false
    }
    $profileContent = (Get-Content $templatePath -Raw).Replace("{{OhMyPoshTheme}}", $OhMyPoshTheme)

    try {
        # Check if profile already contains our marker
        if (Test-Path $PROFILE) {
            $existingContent = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
            if ($existingContent -match "Generated by init.ps1") {
                if ($existingContent -match [regex]::Escape($OhMyPoshTheme)) {
                    Write-LogWarning "Profile already configured with theme '$OhMyPoshTheme', skipping"
                    return $true
                }
                Write-LogInfo "Theme changed, regenerating profile..."
            }
        }
        
        # We're about to overwrite — back up first (skip the empty placeholder)
        if ((Test-Path $PROFILE) -and -not [string]::IsNullOrWhiteSpace((Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue))) {
            $backupPath = "$PROFILE.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            Copy-Item -Path $PROFILE -Destination $backupPath
            Write-LogInfo "Backed up existing profile to: $backupPath"
            Remove-OldBackups -Path $PROFILE -KeepLast $MaxBackupsToKeep
        }
        
        # Write new profile
        Set-Content -Path $PROFILE -Value $profileContent -Force
        Write-LogSuccess "PowerShell profile configured"
        [void]$script:Installed.Add("ps-profile")
        
        Write-LogInfo "Profile location: $PROFILE"
        Write-LogInfo "Run 'Reload-Profile' or restart PowerShell to apply changes"
        
        return $true
    }
    catch {
        Write-LogError "Failed to configure profile: $_"
        [void]$script:Failed.Add("ps-profile")
        return $false
    }
}

# ------------------------------------------------------------------------------
# Windows Terminal Configuration
# ------------------------------------------------------------------------------

function Set-WindowsTerminalNoLogo {
    Write-LogInfo "Configuring Windows Terminal to suppress PowerShell copyright..."

    $settingsPaths = @(
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json"
        "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json"
    )

    $settingsPath = $settingsPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

    if (-not $settingsPath) {
        Write-LogWarning "Windows Terminal settings.json not found, skipping"
        return
    }

    try {
        $raw = Get-Content $settingsPath -Raw -Encoding UTF8

        # Backup before modifying
        $backupPath = "$settingsPath.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Set-Content -Path $backupPath -Value $raw -Encoding UTF8

        # Strip single-line JSONC comments so ConvertFrom-Json can parse it
        $stripped = $raw -replace '(?m)(?<!:)//[^\r\n]*', ''
        $settings = $stripped | ConvertFrom-Json

        $updatedProfiles = [System.Collections.Generic.List[string]]::new()
        $alreadyConfigured = [System.Collections.Generic.List[string]]::new()
        $powershellProfileCount = 0

        foreach ($wtProfile in $settings.profiles.list) {
            $profileName = if ($wtProfile.PSObject.Properties['name']) { $wtProfile.name } else { '<unnamed>' }

            $isPowerShell = (
                ($wtProfile.PSObject.Properties['commandline'] -and $wtProfile.commandline -match 'pwsh|powershell') -or
                ($wtProfile.PSObject.Properties['source']      -and $wtProfile.source      -match 'PowerShell') -or
                ($wtProfile.PSObject.Properties['name']        -and $wtProfile.name        -match 'PowerShell')
            )

            if (-not $isPowerShell) { continue }

            $powershellProfileCount++

            if ($wtProfile.PSObject.Properties['commandline']) {
                if ($wtProfile.commandline -match '-NoLogo') {
                    Write-LogInfo "$profileName already has -NoLogo"
                    $alreadyConfigured.Add($profileName)
                    continue
                }
                $wtProfile.commandline = "$($wtProfile.commandline.TrimEnd()) -NoLogo"
            }
            else {
                $exe = if ($wtProfile.PSObject.Properties['source'] -and $wtProfile.source -match 'PowershellCore') {
                    "pwsh.exe"
                } elseif (Get-Command pwsh -ErrorAction SilentlyContinue) {
                    "pwsh.exe"
                } else {
                    "powershell.exe"
                }
                $wtProfile | Add-Member -NotePropertyName commandline -NotePropertyValue "$exe -NoLogo" -Force
            }

            $updatedProfiles.Add($profileName)
        }

        if ($powershellProfileCount -eq 0) {
            Write-LogWarning "No PowerShell profiles found in Windows Terminal settings"
            Remove-Item $backupPath -Force -ErrorAction SilentlyContinue
            return
        }

        if ($updatedProfiles.Count -eq 0) {
            Write-LogInfo "All PowerShell profiles already have -NoLogo ($powershellProfileCount profile(s))"
            Remove-Item $backupPath -Force -ErrorAction SilentlyContinue
            return
        }

        $settings | ConvertTo-Json -Depth 20 | Set-Content $settingsPath -Encoding UTF8
        Write-LogSuccess "Windows Terminal -NoLogo applied to: $($updatedProfiles -join ', ')"
        Write-LogInfo "Backup saved to: $backupPath"
        Remove-OldBackups -Path $settingsPath -KeepLast $MaxBackupsToKeep
        [void]$script:Installed.Add("terminal-nologo ($($updatedProfiles.Count) profile(s))")
    }
    catch {
        Write-LogError "Failed to configure Windows Terminal: $_"
        [void]$script:Failed.Add("terminal-nologo")
    }
}

# ------------------------------------------------------------------------------
# Installation Summary
# ------------------------------------------------------------------------------

function Show-Summary {
    Write-Host ""
    
    # Installed
    Write-Host "Installed ($($script:Installed.Count)):" -ForegroundColor Green
    if ($script:Installed.Count -gt 0) {
        $installedList = $script:Installed -join ", "
        Write-Host ""
        Write-Host "$installedList" -ForegroundColor Gray
        Write-Host ""
        Write-HorizontalRule
    }
    else {
        Write-Host ""
        Write-Host "(none)" -ForegroundColor Gray
        Write-Host ""
        Write-HorizontalRule
    }
    Write-Host ""
    
    # Updated
    if ($script:Updated.Count -gt 0) {
        Write-Host "Updated ($($script:Updated.Count)):" -ForegroundColor Cyan
        $updatedList = $script:Updated -join ", "
        Write-Host ""
        Write-Host "$updatedList" -ForegroundColor Gray
        Write-Host ""
        Write-HorizontalRule
        Write-Host ""
    }
    
    # Skipped
    Write-Host "Skipped ($($script:Skipped.Count)):" -ForegroundColor Yellow
    if ($script:Skipped.Count -gt 0) {
        $skippedList = $script:Skipped -join ", "
        Write-Host ""
        Write-Host "$skippedList" -ForegroundColor Gray
        Write-Host ""
        Write-HorizontalRule
    }
    else {
        Write-Host ""
        Write-Host "(none)" -ForegroundColor Gray
        Write-Host ""
        Write-HorizontalRule
    }
    Write-Host ""
    
    # Removed
    if ($script:Removed.Count -gt 0) {
        Write-Host "Removed ($($script:Removed.Count)):" -ForegroundColor Magenta
        $removedList = $script:Removed -join ", "
        Write-Host ""
        Write-Host "$removedList" -ForegroundColor Gray
        Write-Host ""
        Write-HorizontalRule
    }
    
    # Failed
    Write-Host "Failed ($($script:Failed.Count)):" -ForegroundColor Red
    if ($script:Failed.Count -gt 0) {
        $failedList = $script:Failed -join ", "
        Write-Host ""
        Write-Host "$failedList" -ForegroundColor Gray
        Write-Host ""
        Write-Host "To retry failed packages manually:" -ForegroundColor Yellow
        Write-Host ""
        foreach ($pkg in $script:Failed) {
            Write-Host "  choco install $pkg -y" -ForegroundColor Gray
        }
        Write-Host ""
        Write-HorizontalRule
    }
    else {
        Write-Host ""
        Write-Host "(none)" -ForegroundColor Gray
        Write-Host ""
        Write-HorizontalRule
    }
    
    Write-Host ""
}

# ------------------------------------------------------------------------------
# Main Entry Point
# ------------------------------------------------------------------------------

function Main {
    # Show banner
    Show-Banner
    
    # Check admin privileges
    Write-LogInfo "Checking administrator privileges..."
    Request-AdminElevation
    Write-LogSuccess "Running as Administrator"
    
    # Determine script location and config path
    $scriptDir = Split-Path -Parent $MyInvocation.PSCommandPath
    $repoRoot = Split-Path -Parent $scriptDir
    $chocoConfigPath = Join-Path $repoRoot "chocolatey.config"
    
    Write-LogInfo "Setting up Windows environment..."
    
    # Ensure PowerShell profile exists (prevents warnings from Oh My Posh)
    $profileDir = Split-Path -Parent $PROFILE
    if (-not (Test-Path $profileDir)) {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
        Write-LogInfo "Created profile directory: $profileDir"
    }
    if (-not (Test-Path $PROFILE)) {
        New-Item -ItemType File -Path $PROFILE -Force | Out-Null
        Write-LogInfo "Created empty profile: $PROFILE"
    }
    
    # Install Chocolatey
    if (-not $SkipChocolatey) {        
        if (Test-Chocolatey) {
            Write-LogSuccess "Chocolatey is already installed"
        }
        else {
            if (-not (Install-Chocolatey)) {
                Write-LogError "Cannot proceed without Chocolatey"
                Show-Summary
                exit 1
            }
        }
        
        # Remove orphaned packages (not in config) if requested
        Remove-OrphanedPackages -ConfigPath $chocoConfigPath
        
        # Install Chocolatey packages from config
        [void](Install-ChocolateyPackages -ConfigPath $chocoConfigPath)
        
        # Refresh environment variables after Chocolatey installs
        Write-LogInfo "Refreshing environment variables..."
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        
        # Add git to User PATH permanently if installed (persists across sessions)
        $gitPath = "C:\Program Files\Git\cmd"
        if (Test-Path $gitPath) {
            $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
            if ($userPath -notlike "*$gitPath*") {
                [Environment]::SetEnvironmentVariable("Path", "$userPath;$gitPath", "User")
                Write-LogInfo "Added git to User PATH"
            }
            if ($env:Path -notlike "*$gitPath*") {
                $env:Path += ";$gitPath"
            }
        }
    }
    else {
        Write-LogWarning "Skipping Chocolatey packages (--SkipChocolatey flag is set)"
    }
    
    # Install Nerd Font MesloLGS NF
    if (-not $SkipFonts) {
        Install-NerdFonts
    }
    else {
        Write-LogWarning "Skipping Nerd Font Installation (--SkipFonts flag is set)"
    }
    
    # Install PowerShell modules
    if (-not $SkipPowerShellModules) {
        Install-AllPSModules
    }
    else {
        Write-LogWarning "Skipping PowerShell Gallery Modules (--SkipPowerShellModules flag is set)"
    }
    
    # Install Oh My Posh
    if (-not $SkipOhMyPosh) {
        Write-LogInfo "Installing Oh My Posh..."
        [void](Install-OhMyPosh)
    }
    else {
        Write-LogWarning "Skipping Oh My Posh (--SkipOhMyPosh flag is set)"
    }
    
    # Install Pi and Oh My Pi (omp)
    if (-not $SkipAgents) {
        Install-Agents
    }
    else {
        Write-LogWarning "Skipping Pi and Oh My Pi (--SkipAgents flag is set)"
    }
    
    # Configure PowerShell profile
    if (-not $SkipProfile) {
        [void](Update-PowerShellProfile)
    }
    else {
        Write-LogWarning "Skipping PowerShell Profile Configuration (--SkipProfile flag is set)"
    }
    
    # Configure Windows Terminal -NoLogo
    if (-not $SkipTerminalConfig) {
        Set-WindowsTerminalNoLogo
    }
    else {
        Write-LogWarning "Skipping Windows Terminal Configuration (--SkipTerminalConfig flag is set)"
    }

    # Show installation summary
    Show-Summary
    
    Write-LogSuccess "Setup complete!"
    Write-Host ""
    Write-LogInfo "Next steps:"
    Write-Host "  1. Reload your profile: . `$PROFILE" -ForegroundColor Gray
    Write-Host "  2. Configure Windows Terminal font:" -ForegroundColor Gray
    Write-Host "     Settings (Ctrl+,) > Profiles > Defaults > Appearance > Font face" -ForegroundColor DarkGray
    Write-Host "     Set to: 'MesloLGS NF'" -ForegroundColor DarkGray
    Write-Host ""
}

# Run main function
Main
