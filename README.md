# .dotfiles

Personal development environment for Windows and Unix-based systems (WSL/Linux/MacOS).

## WSL2

### Installing WSL2

```powershell
wsl.exe --install
```

> To list available distros: `wsl.exe --list --online`

### Unregister a distro

List installed distros:

```powershell
wsl.exe --list --verbose
```

Unregister (destroy) a distro:

```powershell
wsl --unregister <DistroName>
```

## Scripts

### Windows (PowerShell)

Run as **Administrator**:

```powershell
# Run the init script
Set-ExecutionPolicy Bypass -Scope Process -Force; .\scripts\init.ps1
```

**Optional flags:**

| Flag                  | Description                                                                  |
| --------------------- | ---------------------------------------------------------------------------- |
| `-SkipChocolatey`     | Skip Chocolatey and all package installs                                     |
| `-SkipFonts`          | Skip Nerd Font installation (used for icons in shell prompts)                |
| `-SkipModules`        | Skip PowerShell Gallery modules (used for shell enhancements)                |
| `-SkipOhMyPosh`       | Skip Oh My Posh installation (prompt theme engine)                           |
| `-SkipProfile`        | Skip PowerShell profile setup                                                |
| `-SkipTerminalConfig` | Skip Windows Terminal configuration (suppresses PowerShell copyright banner) |
| `-UpdatePackages`     | Upgrade installed packages to the versions pinned in `chocolatey.config`     |
| `-RemoveOrphaned`     | Remove installed packages not listed in `chocolatey.config`                  |

```powershell
# Run the init script with all optional flags
Set-ExecutionPolicy Bypass -Scope Process -Force; .\scripts\init.ps1 -UpdatePackages -RemoveOrphaned -SkipFonts -SkipModules -SkipOhMyPosh -SkipProfile -SkipTerminalConfig
```

### WSL / Linux / macOS

```sh
# Make the script executable
chmod +x scripts/init.sh

# Run the init script
./scripts/init.sh
```

**Optional flags:**

| Flag                | Description                                                          |
| ------------------- | -------------------------------------------------------------------- |
| `--update-packages` | Upgrade already-installed packages to their latest available version |

```sh
# Run the init script with all optional flags
./scripts/init.sh --update-packages
```

> Automatically detects your OS (WSL, Linux, macOS) and uses `apt` or `Homebrew` accordingly.
