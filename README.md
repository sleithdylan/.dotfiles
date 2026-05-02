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
Set-ExecutionPolicy Bypass -Scope Process -Force; .\scripts\init.ps1
```

**Optional flags:**

| Flag              | Description                                |
| ----------------- | ------------------------------------------ |
| `-SkipChocolatey` | Skip Chocolatey and all package installs   |
| `-SkipFonts`      | Skip MesloLGS NF font installation         |
| `-SkipModules`    | Skip PowerShell Gallery modules            |
| `-SkipOhMyPosh`   | Skip Oh My Posh installation               |
| `-SkipProfile`    | Skip PowerShell profile setup              |
| `-UpdatePackages` | Upgrade outdated Chocolatey packages       |
| `-RemoveOrphaned` | Remove packages not in `chocolatey.config` |

### WSL / Linux / macOS

```sh
chmod +x scripts/init.sh && ./scripts/init.sh
```

**Optional flags:**

| Flag                | Description                        |
| ------------------- | ---------------------------------- |
| `--update-packages` | Upgrade already-installed packages |

> Automatically detects your OS (WSL, Linux, macOS) and uses `apt` or `Homebrew` accordingly.
