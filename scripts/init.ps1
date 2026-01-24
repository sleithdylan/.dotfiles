# ------------------------------------------------------------------------------
# Windows Initialization Script (PowerShell)
# ------------------------------------------------------------------------------
# Usage: Run as Administrator
#   Set-ExecutionPolicy Bypass -Scope Process -Force
#   .\init.ps1
# ------------------------------------------------------------------------------

#Requires -Version 5.1

param(
    [switch]$SkipChocolatey,
    [switch]$SkipModules,
    [switch]$SkipOhMyPosh,
    [switch]$SkipProfile,
    [switch]$SkipFonts
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
$OhMyPoshTheme = "powerlevel10k_rainbow"

# ------------------------------------------------------------------------------
# Installation Tracking
# ------------------------------------------------------------------------------

$script:Installed = [System.Collections.ArrayList]::new()
$script:Skipped = [System.Collections.ArrayList]::new()
$script:Failed = [System.Collections.ArrayList]::new()

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
        $current = 0
        
        Write-LogInfo "Found $totalPackages packages in config"
        
        foreach ($pkg in $packages) {
            $current++
            $packageId = $pkg.id
            $packageVersion = $pkg.version
            
            # Progress indicator
            Write-Host "[$current/$totalPackages] " -NoNewline -ForegroundColor Gray
            
            # Check if already installed
            $installed = choco list --local-only --exact $packageId 2>$null
            if ($installed -match $packageId) {
                Write-LogWarning "$packageId already installed, skipping"
                [void]$script:Skipped.Add($packageId)
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
        
        Write-LogSuccess "Chocolatey package installation complete"
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
        [void]$script:Skipped.Add($ModuleName)
        return $true
    }
    
    $attempt = 0
    while ($attempt -lt $MaxRetries) {
        $attempt++
        Write-LogInfo "Installing $ModuleName ($Description)..."
        
        try {
            # Use TLS 1.2 for PowerShell Gallery
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
    Write-LogInfo "Installing PowerShell Gallery modules..."
    
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
    
    foreach ($module in $PSGalleryModules) {
        Install-PSModule -ModuleName $module.Name -Description $module.Description
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
    Write-LogInfo "Installing MesloLGS NF fonts (Powerlevel10k recommendation)..."
    
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
    if ($skippedCount -eq $NerdFonts.Count) {
        [void]$script:Skipped.Add("MesloLGS-NF")
    }
    
    return $installedCount -gt 0 -or $skippedCount -gt 0
}

function Install-NerdFonts {
    # Install MesloLGS NF (Powerlevel10k recommended)
    Install-MesloLGSNF
    
    Write-LogInfo "Font installation complete"
    Write-LogInfo "Configure Windows Terminal: Settings > Profiles > Appearance > Font face"
    Write-LogInfo "Recommended font: 'MesloLGS NF'"
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
        Write-LogInfo "Installing Oh My Posh via winget..."
        
        try {
            winget install JanDeDobbeleer.OhMyPosh -s winget --accept-package-agreements --accept-source-agreements
            
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
        [void]$script:Skipped.Add("oh-my-posh")
    }
    
    # Verify theme exists
    $themePath = "$env:POSH_THEMES_PATH\$OhMyPoshTheme.omp.json"
    if ($env:POSH_THEMES_PATH -and (Test-Path $themePath)) {
        Write-LogSuccess "Theme '$OhMyPoshTheme' is available"
    }
    else {
        Write-LogInfo "Theme path: Use 'Get-PoshThemes' to see available themes"
    }
    
    return $true
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
    
    # Backup existing profile
    if (Test-Path $PROFILE) {
        $backupPath = "$PROFILE.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item -Path $PROFILE -Destination $backupPath
        Write-LogInfo "Backed up existing profile to: $backupPath"
    }
    
    # Generate profile content
    $profileContent = @'
# ==============================================================================
# PowerShell Profile - Generated by init.ps1
# ==============================================================================

# ------------------------------------------------------------------------------
# Oh My Posh
# ------------------------------------------------------------------------------
$env:POSH_DISABLE_COMPLETION = "1"
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    $themePath = "$env:POSH_THEMES_PATH\powerlevel10k_rainbow.omp.json"
    if (Test-Path $themePath) {
        oh-my-posh init pwsh --config $themePath | Invoke-Expression
    }
    else {
        # Fallback to default theme
        oh-my-posh init pwsh | Invoke-Expression
    }
}

# ------------------------------------------------------------------------------
# Modules
# ------------------------------------------------------------------------------

# posh-git - Git status in prompt
if (Get-Module -ListAvailable -Name posh-git) {
    Import-Module posh-git
}

# Terminal-Icons - File/folder icons
if (Get-Module -ListAvailable -Name Terminal-Icons) {
    Import-Module Terminal-Icons
}

# z - Directory jumping
if (Get-Module -ListAvailable -Name z) {
    Import-Module z
}

# PSFzf - Fuzzy finder (requires fzf to be installed)
if ((Get-Command fzf -ErrorAction SilentlyContinue) -and (Get-Module -ListAvailable -Name PSFzf)) {
    Import-Module PSFzf
    Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+f' -PSReadlineChordReverseHistory 'Ctrl+r'
}

# ------------------------------------------------------------------------------
# PSReadLine Configuration
# ------------------------------------------------------------------------------
if (Get-Module -ListAvailable -Name PSReadLine) {
    # Prediction settings (PSReadLine 2.1.0+)
    try {
        Set-PSReadLineOption -PredictionSource History
        Set-PSReadLineOption -PredictionViewStyle ListView
    }
    catch { }
    
    # Key bindings
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
    Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
    
    # Colors (optional - uses theme colors)
    Set-PSReadLineOption -Colors @{
        Command = 'Cyan'
        Parameter = 'DarkCyan'
        String = 'DarkYellow'
    }
}

# ------------------------------------------------------------------------------
# Aliases
# ------------------------------------------------------------------------------
Set-Alias -Name vim -Value nvim -ErrorAction SilentlyContinue
Set-Alias -Name g -Value git -ErrorAction SilentlyContinue
Set-Alias -Name open -Value explorer -ErrorAction SilentlyContinue

# ------------------------------------------------------------------------------
# Functions
# ------------------------------------------------------------------------------

# Quick navigation
function .. { Set-Location .. }
function ... { Set-Location ..\.. }
function .... { Set-Location ..\..\.. }

# Create and enter directory
function mkcd { param($dir) New-Item -ItemType Directory -Path $dir -Force; Set-Location $dir }

# Get public IP
function Get-PublicIP { (Invoke-WebRequest -Uri "https://api.ipify.org").Content }

# Quick edit profile
function Edit-Profile { code $PROFILE }

# Reload profile
function Reload-Profile { . $PROFILE }

# ==============================================================================
# End of Profile
# ==============================================================================
'@

    try {
        # Check if profile already contains our marker
        if (Test-Path $PROFILE) {
            $existingContent = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
            if ($existingContent -match "Generated by init.ps1") {
                Write-LogWarning "Profile already configured by init.ps1, skipping"
                [void]$script:Skipped.Add("ps-profile")
                return $true
            }
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
# Installation Summary
# ------------------------------------------------------------------------------

function Show-Summary {
    Write-Host ""
    
    # Installed
    Write-Host "Installed ($($script:Installed.Count)):" -ForegroundColor Green
    if ($script:Installed.Count -gt 0) {
        $installedList = $script:Installed -join ", "
        Write-Host "  $installedList" -ForegroundColor Gray
    }
    else {
        Write-Host "  (none)" -ForegroundColor Gray
    }
    Write-Host ""
    
    # Skipped
    Write-Host "Skipped ($($script:Skipped.Count)):" -ForegroundColor Yellow
    if ($script:Skipped.Count -gt 0) {
        $skippedList = $script:Skipped -join ", "
        Write-Host "  $skippedList" -ForegroundColor Gray
    }
    else {
        Write-Host "  (none)" -ForegroundColor Gray
    }
    Write-Host ""
    
    # Failed
    Write-Host "Failed ($($script:Failed.Count)):" -ForegroundColor Red
    if ($script:Failed.Count -gt 0) {
        $failedList = $script:Failed -join ", "
        Write-Host "  $failedList" -ForegroundColor Gray
        Write-Host ""
        Write-Host "To retry failed packages manually:" -ForegroundColor Yellow
        foreach ($pkg in $script:Failed) {
            Write-Host "  choco install $pkg -y" -ForegroundColor Gray
        }
    }
    else {
        Write-Host "  (none)" -ForegroundColor Gray
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
            [void]$script:Skipped.Add("chocolatey")
        }
        else {
            if (-not (Install-Chocolatey)) {
                Write-LogError "Cannot proceed without Chocolatey"
                Show-Summary
                exit 1
            }
        }
        
        # Install Chocolatey packages from config
        Install-ChocolateyPackages -ConfigPath $chocoConfigPath
        
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
        Write-LogWarning "Skipping Chocolatey packages (--SkipChocolatey)"
    }
    
    # Install Nerd Font MesloLGS NF
    if (-not $SkipFonts) {
        Install-NerdFonts
    }
    else {
        Write-LogWarning "Skipping font installation (--SkipFonts)"
    }
    
    # Install PowerShell modules
    if (-not $SkipModules) {
        Install-AllPSModules
    }
    else {
        Write-LogWarning "Skipping PowerShell modules (--SkipModules)"
    }
    
    # Install Oh My Posh
    if (-not $SkipOhMyPosh) {
        Write-LogInfo "Installing Oh My Posh..."
        Install-OhMyPosh
    }
    else {
        Write-LogWarning "Skipping Oh My Posh (--SkipOhMyPosh)"
    }
    
    # Configure PowerShell profile
    if (-not $SkipProfile) {
        Update-PowerShellProfile
    }
    else {
        Write-LogWarning "Skipping profile configuration (--SkipProfile)"
    }
    
    # Show installation summary
    Show-Summary
    
    Write-LogSuccess "Setup complete!"
    Write-Host ""
    Write-LogInfo "Next steps:"
    Write-Host "  1. Restart your terminal to apply all changes" -ForegroundColor Gray
    Write-Host "  2. Configure Windows Terminal font:" -ForegroundColor Gray
    Write-Host "     Settings (Ctrl+,) > Profiles > Defaults > Appearance > Font face" -ForegroundColor DarkGray
    Write-Host "     Set to: 'MesloLGS NF'" -ForegroundColor DarkGray
    Write-Host ""
}

# Run main function
Main
