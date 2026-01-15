#!/bin/bash

# ------------------------------------------------------------------------------
# WSL/Linux/MacOS Initialization Script
# ------------------------------------------------------------------------------
# Usage: sudo chmod +x init.sh && ./init.sh
# ------------------------------------------------------------------------------

set -o pipefail

# Packages ---------------------------------------------------------------------
# Dev tools for apt (Ubuntu/Debian)
APT_PACKAGES=(
	"git"
	"curl"
	"wget"
	"tmux"
	"unzip"
	"build-essential"
	"zsh"
	"php"
	"composer"
	"ruby"
	"postgresql-client"
	"dnsutils"
	"neofetch"
  "htop"
  "speedtest-cli"
  "cmatrix"
  "figlet"
)

# Dev tools for Homebrew (MacOS)
HOMEBREW_PACKAGES=(
	"git"
	"curl"
	"wget"
	"unzip"
	"zsh"
	"tmux"
	"php"
	"composer"
	"ruby"
	"postgresql"
	"bind"
	"ngrok"
	"act"
	"htop"
  "speedtest-cli"
  "cmatrix"
  "figlet"
)

# GUI Apps (MacOS)
HOMEBREW_CASK_PACKAGES=(
	"firefox"
	"slack"
	"zoom"
	"visual-studio-code"
	"docker"
	"postman"
	"pgadmin4"
	"tableplus"
	"android-studio"
	"mongodb-compass"
	"vlc"
	"hyper"
)

# Cargo packages (Rust)
CARGO_PACKAGES=(
	"bob-nvim"
)

# Oh My Zsh Plugins
ZSH_PLUGINS=(
	"git"
	"zsh-autosuggestions"
	"zsh-syntax-highlighting"
)

# Logging ----------------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NO_COLOR='\033[0m'

log_info() {
	echo -e "${CYAN}[$(date +%H:%M:%S)] [INFO] $1${NO_COLOR}"
}

log_success() {
	echo -e "${GREEN}[$(date +%H:%M:%S)] [SUCCESS] $1${NO_COLOR}"
}

log_warning() {
	echo -e "${YELLOW}[$(date +%H:%M:%S)] [WARN] $1${NO_COLOR}"
}

log_error() {
	echo -e "${RED}[$(date +%H:%M:%S)] [ERROR] $1${NO_COLOR}"
}

# Detect OS --------------------------------------------------------------------

detect_os() {
	local os_type
	os_type=$(uname -s)

	case "$os_type" in
		Linux)
			# Check if running in WSL
			if grep -qi microsoft /proc/version 2>/dev/null; then
				echo "wsl"
			else
				echo "linux"
			fi
			;;
		Darwin)
			echo "macos"
			;;
		*)
			echo "unknown"
			;;
	esac
}


# Functions --------------------------------------------------------------------

INSTALLED=()
SKIPPED=()
FAILED=()

# Prompt for yes/no confirmation
confirm_install() {
	local prompt=$1
	local response

	while true; do
		read -rp "$prompt [y/n]: " response
		case "$response" in
			[yY]|[yY][eE][sS])
				return 0
				;;
			[nN]|[nN][oO])
				return 1
				;;
			*)
				echo "Please answer y/yes or n/no."
				;;
		esac
	done
}

check_homebrew() {
	if command -v brew &>/dev/null; then
		return 0
	else
		return 1
	fi
}

install_homebrew() {
	log_info "Installing Homebrew..."

	if /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
		# Add Homebrew to PATH for this session
		if [[ -f /opt/homebrew/bin/brew ]]; then
			eval "$(/opt/homebrew/bin/brew shellenv)"
		elif [[ -f /usr/local/bin/brew ]]; then
			eval "$(/usr/local/bin/brew shellenv)"
		fi
		log_success "Homebrew installed successfully"
		return 0
	else
		log_error "Failed to install Homebrew"
		return 1
	fi
}

check_command() {
	command -v "$1" &>/dev/null
}

install_apt_package() {
	local package=$1
	local max_retries=3
	local attempt=0

	# Check if already installed
	if dpkg -l "$package" 2>/dev/null | grep -q "^ii"; then
		log_warning "$package already installed, skipping"
		SKIPPED+=("$package")
		return 0
	fi

	while [[ $attempt -lt $max_retries ]]; do
		((attempt++))
		log_info "Installing $package..."

		if sudo apt-get install -y "$package" &>/dev/null; then
			log_success "$package installed"
			INSTALLED+=("$package")
			return 0
		else
			if [[ $attempt -lt $max_retries ]]; then
				log_warning "Failed to install $package, retrying..."
				sleep 2
			fi
		fi
	done

	log_error "$package failed"
	FAILED+=("$package")
	return 1
}

install_brew_package() {
	local package=$1
	local max_retries=2
	local attempt=0

	# Check if already installed
	if brew list "$package" &>/dev/null; then
		log_warning "$package already installed, skipping"
		SKIPPED+=("$package")
		return 0
	fi

	while [[ $attempt -lt $max_retries ]]; do
		((attempt++))
		log_info "Installing $package..."

		if brew install "$package" &>/dev/null; then
			log_success "$package installed"
			INSTALLED+=("$package")
			return 0
		else
			if [[ $attempt -lt $max_retries ]]; then
				log_warning "Failed to install $package, retrying..."
				sleep 2
			fi
		fi
	done

	log_error "$package failed"
	FAILED+=("$package")
	return 1
}

install_brew_cask() {
	local package=$1
	local max_retries=2
	local attempt=0

	# Check if already installed
	if brew list --cask "$package" &>/dev/null; then
		log_warning "$package already installed, skipping"
		SKIPPED+=("$package")
		return 0
	fi

	while [[ $attempt -lt $max_retries ]]; do
		((attempt++))
		log_info "Installing $package..."

		if brew install --cask "$package" &>/dev/null; then
			log_success "$package installed"
			INSTALLED+=("$package")
			return 0
		else
			if [[ $attempt -lt $max_retries ]]; then
				log_warning "Failed to install $package, retrying..."
				sleep 2
			fi
		fi
	done

	log_error "$package failed"
	FAILED+=("$package")
	return 1
}

check_rust() {
	command -v rustc &>/dev/null && command -v cargo &>/dev/null
}

install_rust() {
	log_info "Installing Rust and Cargo..."

	if check_rust; then
		log_warning "Rust and Cargo already installed, skipping"
		SKIPPED+=("rust")
		return 0
	fi

	# Install rustup (which installs Rust and Cargo)
	if curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y &>/dev/null; then
		# Source cargo env for current session
		source "$HOME/.cargo/env"
		log_success "Rust and Cargo installed"
		INSTALLED+=("rust" "cargo")
		return 0
	else
		log_error "Rust installation failed"
		FAILED+=("rust")
		return 1
	fi
}

install_cargo_package() {
	local package=$1
	local max_retries=3
	local attempt=0

	# Ensure cargo is available
	[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"

	if ! command -v cargo &>/dev/null; then
		log_error "Cargo not found, cannot install $package"
		FAILED+=("$package")
		return 1
	fi

	# Check if already installed
	if cargo install --list 2>/dev/null | grep -q "^$package "; then
		log_warning "$package already installed, skipping"
		SKIPPED+=("$package")
		return 0
	fi

	while [[ $attempt -lt $max_retries ]]; do
		((attempt++))
		log_info "Installing $package via cargo..."

		if cargo install "$package" &>/dev/null; then
			log_success "$package installed"
			INSTALLED+=("$package")
			return 0
		else
			if [[ $attempt -lt $max_retries ]]; then
				log_warning "Failed to install $package via cargo, retrying..."
				sleep 2
			fi
		fi
	done

	log_error "$package failed"
	FAILED+=("$package")
	return 1
}

setup_cargo_packages() {
	log_info "Installing Cargo packages..."

	# Ensure cargo is available
	[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"

	for package in "${CARGO_PACKAGES[@]}"; do
		install_cargo_package "$package"
	done
}

setup_neovim_via_bob() {
	log_info "Setting up Neovim via bob..."

	# Ensure cargo env is loaded (bob is installed via cargo)
	[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"

	if ! command -v bob &>/dev/null; then
		log_error "bob not found, cannot install Neovim"
		FAILED+=("neovim")
		return 1
	fi

	# Check if neovim is already installed via bob
	if bob list 2>/dev/null | grep -q "Used"; then
		log_warning "Neovim already installed via bob, skipping"
		SKIPPED+=("neovim")
		# Still add to PATH for this session so LazyVim can find it
		export PATH="$HOME/.local/share/bob/nvim-bin:$PATH"
		return 0
	fi

	log_info "Installing Neovim stable via bob..."
	if bob install stable &>/dev/null && bob use stable &>/dev/null; then
		log_success "Neovim stable installed via bob"
		INSTALLED+=("neovim-stable")

		# Add bob's nvim-bin to PATH for current session (so LazyVim can find nvim)
		local bob_nvim_bin="$HOME/.local/share/bob/nvim-bin"
		export PATH="$bob_nvim_bin:$PATH"
		log_info "Added $bob_nvim_bin to PATH for this session"
	else
		log_error "Neovim installation via bob failed"
		FAILED+=("neovim")
		return 1
	fi
}

setup_apt_packages() {
	log_info "Updating apt packages..."

	sudo apt-get update -y &>/dev/null

	log_info "Installing dev tools via apt..."

	for package in "${APT_PACKAGES[@]}"; do
		install_apt_package "$package"
	done
}

setup_brew_packages() {
	log_info "Updating Homebrew..."
	brew update &>/dev/null

	log_info "Installing dev tools via Homebrew..."
	echo ""

	for package in "${HOMEBREW_PACKAGES[@]}"; do
		install_brew_package "$package"
	done
}

setup_brew_cask_packages() {
	log_info "Installing GUI apps via Homebrew Cask..."
	echo ""

	for package in "${HOMEBREW_CASK_PACKAGES[@]}"; do
		install_brew_cask "$package"
	done
}

setup_ohmyzsh() {
	log_info "Setting up Oh My Zsh..."
  echo ""

	# Check if already installed
	if [[ -d "$HOME/.oh-my-zsh" ]]; then
		log_warning "Oh My Zsh already installed, skipping"
		SKIPPED+=("oh-my-zsh")
	else
		# Install Oh My Zsh (unattended)
		if sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended; then
      echo ""
			log_success "Oh My Zsh installed"
			INSTALLED+=("oh-my-zsh")
		else
			log_error "Oh My Zsh installation failed"
			FAILED+=("oh-my-zsh")
			return 1
		fi
	fi

	# Install zsh-autosuggestions plugin
	local zsh_autosuggestions_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"
	if [[ ! -d "$zsh_autosuggestions_dir" ]]; then
		log_info "Installing zsh-autosuggestions plugin..."
		if git clone https://github.com/zsh-users/zsh-autosuggestions "$zsh_autosuggestions_dir" &>/dev/null; then
			log_success "zsh-autosuggestions installed"
			INSTALLED+=("zsh-autosuggestions")
		else
			log_error "zsh-autosuggestions failed"
			FAILED+=("zsh-autosuggestions")
		fi
	else
		log_warning "zsh-autosuggestions already installed, skipping"
		SKIPPED+=("zsh-autosuggestions")
	fi

	# Install zsh-syntax-highlighting plugin
	local zsh_syntax_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting"
	if [[ ! -d "$zsh_syntax_dir" ]]; then
		log_info "Installing zsh-syntax-highlighting plugin..."
		if git clone https://github.com/zsh-users/zsh-syntax-highlighting "$zsh_syntax_dir" &>/dev/null; then
			log_success "zsh-syntax-highlighting installed"
			INSTALLED+=("zsh-syntax-highlighting")
		else
			log_error "zsh-syntax-highlighting failed"
			FAILED+=("zsh-syntax-highlighting")
		fi
	else
		log_warning "zsh-syntax-highlighting already installed, skipping"
		SKIPPED+=("zsh-syntax-highlighting")
	fi

	# Update .zshrc to enable plugins
	if [[ -f "$HOME/.zshrc" ]]; then
		log_info "Configuring Oh My Zsh plugins..."
		# Backup original
		cp "$HOME/.zshrc" "$HOME/.zshrc.backup"
		# Update plugins line
		sed -i.bak 's/^plugins=.*/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' "$HOME/.zshrc"
		log_success "Oh My Zsh plugins configured"
	fi
}

setup_nvm() {
	log_info "Setting up NVM (Node Version Manager)..."
  echo -e "\n"

	if [[ -d "$HOME/.nvm" ]]; then
		log_warning "NVM already installed, skipping"
		SKIPPED+=("nvm")
	else
		# Install NVM
		if curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash &>/dev/null; then
			log_success "NVM installed"
			INSTALLED+=("nvm")

			# Load NVM for current session
			export NVM_DIR="$HOME/.nvm"
			[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
		else
			log_error "NVM installation failed"
			FAILED+=("nvm")
			return 1
		fi
	fi

	# Load NVM if available
	export NVM_DIR="$HOME/.nvm"
	[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

	# Install Node.js LTS
	if command -v nvm &>/dev/null; then
		log_info "Installing Node.js LTS via NVM..."
		if nvm install --lts &>/dev/null; then
			nvm use --lts &>/dev/null
			nvm alias default 'lts/*' &>/dev/null
			log_success "Node.js LTS installed"
			INSTALLED+=("nodejs-lts")
		else
			log_error "Node.js LTS installation failed"
			FAILED+=("nodejs-lts")
		fi

		# Install global npm packages
		log_info "Installing pnpm and yarn..."
		if npm install -g pnpm &>/dev/null; then
			log_success "pnpm installed"
			INSTALLED+=("pnpm")
		else
			log_error "pnpm failed"
			FAILED+=("pnpm")
		fi

		if npm install -g yarn &>/dev/null; then
			log_success "yarn installed"
			INSTALLED+=("yarn")
		else
			log_error "yarn failed"
			FAILED+=("yarn")
		fi
	fi
}

setup_pyenv() {
	log_info "Setting up pyenv (Python Version Manager)..."
  echo -e "\n"

	if [[ -d "$HOME/.pyenv" ]]; then
		log_warning "pyenv already installed, skipping"
		SKIPPED+=("pyenv")
	else
		# Install pyenv
		if curl https://pyenv.run | bash &>/dev/null; then
			log_success "pyenv installed"
			INSTALLED+=("pyenv")

			# Add pyenv to PATH for current session
			export PYENV_ROOT="$HOME/.pyenv"
			export PATH="$PYENV_ROOT/bin:$PATH"
			eval "$(pyenv init -)"
		else
			log_error "pyenv installation failed"
			FAILED+=("pyenv")
			return 1
		fi
	fi

	# Load pyenv if available
	export PYENV_ROOT="$HOME/.pyenv"
	[[ -d "$PYENV_ROOT/bin" ]] && export PATH="$PYENV_ROOT/bin:$PATH"
	command -v pyenv &>/dev/null && eval "$(pyenv init -)"

	# Install latest Python 3
	if command -v pyenv &>/dev/null; then
		log_info "Installing Python 3 via pyenv..."
		local latest_python
		latest_python=$(pyenv install --list 2>/dev/null | grep -E "^\s*3\.[0-9]+\.[0-9]+$" | tail -1 | tr -d ' ')

		if [[ -n "$latest_python" ]]; then
			if pyenv install "$latest_python" &>/dev/null; then
				pyenv global "$latest_python" &>/dev/null
				log_success "Python $latest_python installed"
				INSTALLED+=("python-$latest_python")
			else
				log_warning "Python $latest_python may already be installed or failed"
			fi
		fi
	fi
}

setup_lazyvim() {
	log_info "Setting up LazyVim..."

	local nvim_config="$HOME/.config/nvim"

	# Check if neovim is installed
	if ! command -v nvim &>/dev/null; then
		log_error "Neovim is not installed. Please install neovim first."
		FAILED+=("lazyvim")
		return 1
	fi

	# Check if LazyVim is already installed (look for lazy.nvim)
	if [[ -d "$nvim_config/lua" ]] && [[ -f "$nvim_config/lazy-lock.json" ]]; then
		log_warning "LazyVim appears to be already installed, skipping"
		SKIPPED+=("lazyvim")
		return 0
	fi

	# Backup existing config if it exists
	if [[ -d "$nvim_config" ]]; then
		log_info "Backing up existing Neovim config..."
		mv "$nvim_config" "${nvim_config}.bak"
	fi

	# Optional: Backup data directories
	[[ -d "$HOME/.local/share/nvim" ]] && mv "$HOME/.local/share/nvim" "$HOME/.local/share/nvim.bak"
	[[ -d "$HOME/.local/state/nvim" ]] && mv "$HOME/.local/state/nvim" "$HOME/.local/state/nvim.bak"
	[[ -d "$HOME/.cache/nvim" ]] && mv "$HOME/.cache/nvim" "$HOME/.cache/nvim.bak"

	# Clone LazyVim starter
	log_info "Cloning LazyVim starter..."
	if git clone https://github.com/LazyVim/starter "$nvim_config" &>/dev/null; then
		# Remove .git and set up fresh repo with upstream remote
		rm -rf "$nvim_config/.git"

		# Initialize new repo with upstream for future updates
		git -C "$nvim_config" init &>/dev/null
		git -C "$nvim_config" remote add upstream https://github.com/LazyVim/starter.git &>/dev/null
		git -C "$nvim_config" add . &>/dev/null
		git -C "$nvim_config" commit -m "Initial LazyVim setup" &>/dev/null

		log_success "LazyVim installed"
		INSTALLED+=("lazyvim")

		log_info "Run 'nvim' to complete LazyVim setup and install plugins"
		log_info "After first launch, run ':LazyHealth' to verify installation"
		log_info "To pull LazyVim updates: cd ~/.config/nvim && git fetch upstream && git merge upstream/main"
	else
		log_error "LazyVim installation failed"
		FAILED+=("lazyvim")
		return 1
	fi
}

# Installation Summary ---------------------------------------------------------

show_summary() {
	local os_type=$1

	echo ""

	# Installed
	echo -e "${GREEN}Installed (${#INSTALLED[@]}):${NO_COLOR}"
	if [[ ${#INSTALLED[@]} -gt 0 ]]; then
		echo -e "${GRAY}  ${INSTALLED[*]}${NO_COLOR}"
	else
		echo -e "${GRAY}  (none)${NO_COLOR}"
	fi
	echo ""

	# Skipped
	echo -e "${YELLOW}Skipped (${#SKIPPED[@]}):${NO_COLOR}"
	if [[ ${#SKIPPED[@]} -gt 0 ]]; then
		echo -e "${GRAY}  ${SKIPPED[*]}${NO_COLOR}"
	else
		echo -e "${GRAY}  (none)${NO_COLOR}"
	fi
	echo ""

	# Failed
	echo -e "${RED}Failed (${#FAILED[@]}) - after retry:${NO_COLOR}"
	if [[ ${#FAILED[@]} -gt 0 ]]; then
		echo -e "${GRAY}  ${FAILED[*]}${NO_COLOR}"
		echo ""
		echo -e "${YELLOW}To retry manually:${NO_COLOR}"
		for pkg in "${FAILED[@]}"; do
			case "$os_type" in
				wsl|linux)
					echo -e "${GRAY}  sudo apt-get install -y $pkg${NO_COLOR}"
					;;
				macos)
					echo -e "${GRAY}  brew install $pkg${NO_COLOR}"
					;;
			esac
		done
	else
		echo -e "${GRAY}  (none)${NO_COLOR}"
	fi

	echo ""
}

# Main Entry Point --------------------------------------------------------------

main() {
	echo ""

  echo -e "${RED}"
  cat << 'EOF'
                  __                __
   __          __/\ \__            /\ \
  /\_\    ___ /\_\ \ ,_\       ____\ \ \___
  \/\ \ /' _ `\/\ \ \ \/      /',__\\ \  _ `\
   \ \ \/\ \/\ \ \ \ \ \_  __/\__, `\\ \ \ \ \
    \ \_\ \_\ \_\ \_\ \__\/\_\/\____/ \ \_\ \_\
     \/_/\/_/\/_/\/_/\/__/\/_/\/___/   \/_/\/_/
EOF
  echo -e "${NO_COLOR}"

	echo ""

	# Detect OS
	local os_type
	os_type=$(detect_os)
	log_info "Detected OS: $os_type"

	case "$os_type" in
		wsl|linux)
			log_info "Setting up WSL/Linux environment..."

			# Install apt packages
			setup_apt_packages
			echo ""

			# Setup Rust and Cargo
			if confirm_install "Do you want to install Rust, Cargo, and Neovim (via bob)?"; then
        echo ""
				install_rust
				setup_cargo_packages
				setup_neovim_via_bob
				echo ""
			else
				log_warning "Skipping Rust/Cargo/Neovim setup"
				SKIPPED+=("rust" "cargo" "bob-nvim" "neovim")
				echo ""
			fi

			# Setup Oh My Zsh
			setup_ohmyzsh
			echo ""

			# Setup version managers (optional)
			if confirm_install "Do you want to install NVM, Node.js, pnpm, and Yarn?"; then
				setup_nvm
				echo ""
			else
				log_warning "Skipping NVM setup"
				SKIPPED+=("nvm" "nodejs-lts" "pnpm" "yarn")
				echo ""
			fi

			if confirm_install "Do you want to install pyenv and Python?"; then
				setup_pyenv
				echo ""
			else
				log_warning "Skipping pyenv setup"
				SKIPPED+=("pyenv")
				echo ""
			fi

			if confirm_install "Do you want to install LazyVim for Neovim?"; then
				setup_lazyvim
			else
				log_warning "Skipping LazyVim setup"
				SKIPPED+=("lazyvim")
			fi
			;;

		macos)
			log_info "Setting up MacOS environment..."
			echo ""

			# Check/Install Homebrew
			if check_homebrew; then
				log_success "Homebrew is already installed"
			else
				log_warning "Homebrew not found"
				if ! install_homebrew; then
					log_error "Cannot proceed without Homebrew"
					exit 1
				fi
			fi
			echo ""

			# Install Homebrew packages
			setup_brew_packages
			echo ""

			# Install GUI apps
			setup_brew_cask_packages
			echo ""

			# Setup Rust and Cargo
			if confirm_install "Do you want to install Rust, Cargo, and Neovim (via bob)?"; then
				install_rust
				echo ""
				setup_cargo_packages
				setup_neovim_via_bob
			else
				log_warning "Skipping Rust/Cargo/Neovim setup"
				SKIPPED+=("rust" "cargo" "bob-nvim" "neovim")
				echo ""
			fi

			# Setup Oh My Zsh
			setup_ohmyzsh
			echo ""

			# Setup version managers (optional)
			if confirm_install "Do you want to install NVM, Node.js, pnpm, and Yarn?"; then
				setup_nvm
				echo ""
			else
				log_warning "Skipping NVM setup"
				SKIPPED+=("nvm" "nodejs-lts" "pnpm" "yarn")
				echo ""
			fi

			if confirm_install "Do you want to install pyenv and Python?"; then
				setup_pyenv
				echo ""
			else
				log_warning "Skipping pyenv setup"
				SKIPPED+=("pyenv")
				echo ""
			fi

			if confirm_install "Do you want to install LazyVim for Neovim?"; then
				setup_lazyvim
			else
				log_warning "Skipping LazyVim setup"
				SKIPPED+=("lazyvim")
			fi
			;;

		*)
			log_error "Unsupported OS: $os_type"
			exit 1
			;;
	esac

	# Show summary
	show_summary "$os_type"

	log_success "Setup complete!"

	# Set zsh as default shell if not already
	if command -v zsh &>/dev/null; then
		local current_shell
		current_shell=$(getent passwd "$USER" | cut -d: -f7)
		local zsh_path
		zsh_path=$(which zsh)

		if [[ "$current_shell" != "$zsh_path" ]]; then
			log_info "Setting zsh as default shell (may require password)..."
      echo -e ""

			if chsh -s "$zsh_path"; then
        echo ""
				log_success "Default shell changed to zsh"
				echo -e "${YELLOW}Note: Restart your terminal for the shell change to take effect${NO_COLOR}"
				echo ""
			else
				log_warning "Failed to change shell. You can manually run: chsh -s $zsh_path"
				echo ""
			fi
		else
			log_info "zsh is already your default shell"
			echo ""
		fi
	fi
}

# Run main function
main "$@"
