# Dotfiles

Personal development environment for Windows and Unix-based systems (WSL/Linux/MacOS).

## WSL2

### Installing WSL2

1. Open PowerShell

2. Install WSL2:

   ```sh
   wsl.exe --install
   ```

   > **List the available Linux distros:** wsl.exe --list --online

### Unregister Linux distro

1. Open PowerShell

2. List all distros:

   ```sh
   wsl.exe --list --verbose
   ```

3. Unregister (destroy) distro:

   ```sh
   wsl --unregister <Distro, e.g: Ubuntu>
   ```

## Scripts

### Installation for Windows

Automates the installation of essential dev tools and GUI applications using PowerShell.

**Usage:**

```sh
Set-ExecutionPolicy Bypass -Scope Process -Force; .\scripts\init.ps1
```

> Make sure you are running PowerShell as Administrator before running the script!

### Installation for WSL/Linux/MacOS

Automates the installation of essential dev tools and GUI applications using apt or Homebrew, depending on your OS.

**Usage:**

```sh
sudo chmod +x scripts/init.sh && ./scripts/init.sh
```
