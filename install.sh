#!/usr/bin/env bash
#
# Albedo Installer
# One-command setup for Albedo CLI
#
# Usage:
#   ./install.sh           # Standard installation
#   source install.sh      # Installation + auto-apply changes
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color


print_header() {
  echo ""
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${CYAN}  Albedo Installer${NC}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
}

print_success() {
  echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
  echo -e "${RED}✗ $1${NC}"
}

print_info() {
  echo -e "${YELLOW}→ $1${NC}"
}

detect_os() {
  case "$(uname -s)" in
    Darwin*) echo "macos" ;;
    Linux*)  echo "linux" ;;
    MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
    *)       echo "unknown" ;;
  esac
}

detect_shell_profile() {
  if [[ -n "$ZSH_VERSION" ]] || [[ "$SHELL" == *"zsh"* ]]; then
    echo "$HOME/.zshrc"
  elif [[ -n "$BASH_VERSION" ]] || [[ "$SHELL" == *"bash"* ]]; then
    if [[ -f "$HOME/.bashrc" ]]; then
      echo "$HOME/.bashrc"
    else
      echo "$HOME/.bash_profile"
    fi
  else
    echo "$HOME/.profile"
  fi
}

check_command() {
  command -v "$1" &> /dev/null
}

detect_package_manager() {
  local os="$1"

  # Prefer asdf for Elixir developers (better version management)
  if check_command asdf; then
    echo "asdf"
    return
  fi

  case $os in
    macos)
      if check_command brew; then
        echo "brew"
      else
        echo "none"
      fi
      ;;
    linux)
      if check_command apt-get; then
        echo "apt"
      elif check_command dnf; then
        echo "dnf"
      elif check_command pacman; then
        echo "pacman"
      elif check_command zypper; then
        echo "zypper"
      else
        echo "none"
      fi
      ;;
    *)
      echo "none"
      ;;
  esac
}

install_homebrew() {
  print_info "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Add Homebrew to PATH for this session
  if [[ -f "/opt/homebrew/bin/brew" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -f "/usr/local/bin/brew" ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi

  if check_command brew; then
    print_success "Homebrew installed"
    return 0
  else
    print_error "Failed to install Homebrew"
    return 1
  fi
}

install_with_asdf() {
  local tool="$1"

  case $tool in
    elixir)
      print_info "Installing Erlang and Elixir via asdf..."

      # Add plugins if not already added
      if ! asdf plugin list 2>/dev/null | grep -q "^erlang$"; then
        print_info "Adding erlang plugin..."
        asdf plugin add erlang
      fi

      if ! asdf plugin list 2>/dev/null | grep -q "^elixir$"; then
        print_info "Adding elixir plugin..."
        asdf plugin add elixir
      fi

      # Install latest versions
      print_info "Installing Erlang (this may take a few minutes)..."
      asdf install erlang latest
      asdf global erlang latest

      print_info "Installing Elixir..."
      asdf install elixir latest
      asdf global elixir latest

      # Reshim to ensure binaries are available
      asdf reshim erlang
      asdf reshim elixir
      ;;

    ripgrep)
      # asdf doesn't have ripgrep, fall back to system package manager
      local os
      os=$(detect_os)
      case $os in
        macos)
          if check_command brew; then
            brew install ripgrep
          else
            print_error "Please install ripgrep manually: https://github.com/BurntSushi/ripgrep#installation"
            return 1
          fi
          ;;
        linux)
          if check_command apt-get; then
            sudo apt-get update -qq && sudo apt-get install -y ripgrep
          elif check_command dnf; then
            sudo dnf install -y ripgrep
          elif check_command pacman; then
            sudo pacman -S --noconfirm ripgrep
          else
            print_error "Please install ripgrep manually: https://github.com/BurntSushi/ripgrep#installation"
            return 1
          fi
          ;;
        *)
          print_error "Please install ripgrep manually: https://github.com/BurntSushi/ripgrep#installation"
          return 1
          ;;
      esac
      ;;
  esac
}

install_prerequisites() {
  local os="$1"
  local pkg_manager="$2"
  shift 2
  local missing=("$@")

  if [[ ${#missing[@]} -eq 0 ]]; then
    return 0
  fi

  # Handle asdf separately (installs one tool at a time)
  if [[ "$pkg_manager" == "asdf" ]]; then
    for tool in "${missing[@]}"; do
      if ! install_with_asdf "$tool"; then
        return 1
      fi
    done
    print_success "Prerequisites installed"
    return 0
  fi

  # Build package list based on what's missing
  local packages=()
  for tool in "${missing[@]}"; do
    case $tool in
      elixir) packages+=("elixir") ;;
      ripgrep) packages+=("ripgrep") ;;
    esac
  done

  if [[ ${#packages[@]} -eq 0 ]]; then
    return 0
  fi

  print_info "Installing: ${packages[*]}..."

  case $pkg_manager in
    brew)
      brew install "${packages[@]}"
      ;;
    apt)
      sudo apt-get update -qq
      sudo apt-get install -y "${packages[@]}"
      ;;
    dnf)
      sudo dnf install -y "${packages[@]}"
      ;;
    pacman)
      sudo pacman -S --noconfirm "${packages[@]}"
      ;;
    zypper)
      sudo zypper install -y "${packages[@]}"
      ;;
    *)
      print_error "No supported package manager found"
      return 1
      ;;
  esac

  if [[ $? -eq 0 ]]; then
    print_success "Prerequisites installed"
    return 0
  else
    print_error "Installation failed"
    return 1
  fi
}

get_install_instructions() {
  local os="$1"
  local pkg_manager="$2"

  case $pkg_manager in
    asdf)
      echo "  # For Elixir (via asdf - recommended for developers):"
      echo "  asdf plugin add erlang && asdf plugin add elixir"
      echo "  asdf install erlang latest && asdf global erlang latest"
      echo "  asdf install elixir latest && asdf global elixir latest"
      echo ""
      echo "  # For ripgrep:"
      if [[ "$os" == "macos" ]]; then
        echo "  brew install ripgrep"
      else
        echo "  sudo apt-get install ripgrep  # or dnf/pacman"
      fi
      ;;
    brew)
      echo "  brew install elixir ripgrep"
      ;;
    apt)
      echo "  sudo apt-get install elixir ripgrep"
      ;;
    dnf)
      echo "  sudo dnf install elixir ripgrep"
      ;;
    pacman)
      echo "  sudo pacman -S elixir ripgrep"
      ;;
    zypper)
      echo "  sudo zypper install elixir ripgrep"
      ;;
    *)
      echo "  # Recommended: Use asdf for version management"
      echo "  # Install asdf: https://asdf-vm.com/guide/getting-started.html"
      echo ""
      echo "  # Or use your package manager:"
      echo "  See: https://elixir-lang.org/install.html"
      echo "  See: https://github.com/BurntSushi/ripgrep#installation"
      ;;
  esac
}

check_prerequisites() {
  print_info "Checking prerequisites..."

  local missing=()
  local missing_display=()

  if ! check_command elixir; then
    missing+=("elixir")
    missing_display+=("Elixir")
  else
    local elixir_version
    elixir_version=$(elixir -e 'IO.puts("Elixir #{System.version()}")' 2>/dev/null)
    print_success "Elixir found: ${elixir_version:-$(elixir --short-version 2>/dev/null || echo "installed")}"
  fi

  if ! check_command mix; then
    if [[ ! " ${missing[*]} " =~ " elixir " ]]; then
      missing+=("elixir")
      missing_display+=("Mix (part of Elixir)")
    fi
  fi

  if ! check_command rg; then
    missing+=("ripgrep")
    missing_display+=("ripgrep")
  else
    print_success "ripgrep found: $(rg --version | head -1)"
  fi

  if [[ ${#missing[@]} -eq 0 ]]; then
    echo ""
    return 0
  fi

  echo ""
  print_error "Missing required tools:"
  for tool in "${missing_display[@]}"; do
    echo -e "  ${RED}✗${NC} $tool"
  done
  echo ""

  local os
  os=$(detect_os)
  local pkg_manager
  pkg_manager=$(detect_package_manager "$os")

  # Handle missing Homebrew on macOS
  if [[ "$os" == "macos" && "$pkg_manager" == "none" ]]; then
    echo "Homebrew is required to install prerequisites on macOS."
    echo ""
    if prompt_yes_no "Would you like to install Homebrew first?" "y"; then
      if ! install_homebrew; then
        echo ""
        echo "Please install Homebrew manually from: https://brew.sh"
        echo "Then run this installer again."
        exit 1
      fi
      pkg_manager="brew"
      echo ""
    else
      echo ""
      echo "Please install Homebrew from: https://brew.sh"
      echo "Then run this installer again."
      exit 1
    fi
  fi

  # Offer to install prerequisites
  if [[ "$pkg_manager" != "none" ]]; then
    if prompt_yes_no "Would you like to install missing prerequisites automatically?" "y"; then
      echo ""
      if install_prerequisites "$os" "$pkg_manager" "${missing[@]}"; then
        echo ""
        # Verify installation
        local still_missing=()
        for tool in "${missing[@]}"; do
          case $tool in
            elixir)
              if ! check_command elixir; then
                still_missing+=("elixir")
              else
                local ver
                ver=$(elixir -e 'IO.puts("Elixir #{System.version()}")' 2>/dev/null || echo "installed")
                print_success "Elixir installed: $ver"
              fi
              ;;
            ripgrep)
              if ! check_command rg; then
                still_missing+=("ripgrep")
              else
                print_success "ripgrep installed: $(rg --version | head -1)"
              fi
              ;;
          esac
        done

        if [[ ${#still_missing[@]} -gt 0 ]]; then
          print_error "Some tools failed to install: ${still_missing[*]}"
          echo ""
          echo "Please install them manually:"
          get_install_instructions "$os" "$pkg_manager"
          exit 1
        fi

        echo ""
        return 0
      else
        echo ""
        echo "Please install them manually:"
        get_install_instructions "$os" "$pkg_manager"
        exit 1
      fi
    else
      echo ""
      print_info "Installation cancelled."
      echo ""
      echo "To install manually, run:"
      get_install_instructions "$os" "$pkg_manager"
      exit 0
    fi
  else
    echo "No supported package manager found."
    echo ""
    echo "Please install the missing tools manually:"
    get_install_instructions "$os" "$pkg_manager"
    exit 1
  fi
}

build_albedo() {
  print_info "Installing dependencies..."
  mix deps.get --quiet
  print_success "Dependencies installed"

  print_info "Building Albedo..."
  mix escript.build --quiet
  print_success "Albedo built successfully"
  echo ""
}

prompt_yes_no() {
  local prompt="$1"
  local default="$2"

  if [[ "$default" == "y" ]]; then
    prompt="$prompt [Y/n]: "
  else
    prompt="$prompt [y/N]: "
  fi

  read -r -p "$prompt" response
  response=${response:-$default}

  [[ "$response" =~ ^[Yy]$ ]]
}

prompt_choice() {
  local prompt="$1"
  local default="$2"

  read -r -p "$prompt [$default]: " response
  echo "${response:-$default}"
}

setup_provider_and_key() {
  echo ""
  echo "Albedo supports these LLM providers:"
  echo "  1. Gemini (recommended - free tier available)"
  echo "  2. Claude"
  echo "  3. OpenAI"
  echo ""

  local choice
  choice=$(prompt_choice "Enter choice" "1")

  case $choice in
    1|"")
      PROVIDER="gemini"
      PROVIDER_NAME="Gemini"
      API_KEY_VAR="GEMINI_API_KEY"
      API_KEY_URL="https://aistudio.google.com"
      ;;
    2)
      PROVIDER="claude"
      PROVIDER_NAME="Claude"
      API_KEY_VAR="ANTHROPIC_API_KEY"
      API_KEY_URL="https://console.anthropic.com"
      ;;
    3)
      PROVIDER="openai"
      PROVIDER_NAME="OpenAI"
      API_KEY_VAR="OPENAI_API_KEY"
      API_KEY_URL="https://platform.openai.com"
      ;;
    *)
      PROVIDER="gemini"
      PROVIDER_NAME="Gemini"
      API_KEY_VAR="GEMINI_API_KEY"
      API_KEY_URL="https://aistudio.google.com"
      ;;
  esac

  echo ""
  echo -e "Get your API key from: ${CYAN}$API_KEY_URL${NC}"
  echo ""

  read -r -p "Enter your $PROVIDER_NAME API key (or press Enter to skip): " API_KEY

  if [[ -z "$API_KEY" ]]; then
    print_info "Skipped API key setup. You can set it later with: albedo config set-key"
  fi
}

create_config() {
  print_info "Creating configuration..."

  # Create directories
  mkdir -p "$HOME/.albedo/sessions"

  # Create config.toml with selected provider
  local config_file="$HOME/.albedo/config.toml"

  cat > "$config_file" << EOF
# Albedo Configuration
# Generated on $(date +%Y-%m-%d)

[llm]
provider = "$PROVIDER"  # gemini | claude | openai
temperature = 0.3  # Lower = more deterministic

[output]
session_dir = "~/.albedo/sessions"

[search]
tool = "ripgrep"
max_results_per_pattern = 50
exclude_patterns = [
  "node_modules",
  "_build",
  "deps",
  ".git",
  "priv/static"
]

[agents]
timeout = 300  # Timeout for each agent in seconds
EOF

  print_success "Config created at $config_file"
  print_success "Provider set to: $PROVIDER"
}

setup_shell_profile() {
  local shell_profile
  shell_profile=$(detect_shell_profile)

  # Get the directory where install.sh is located
  local albedo_dir
  albedo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  echo ""
  echo "The following will be added to $shell_profile:"
  echo ""
  echo -e "  ${CYAN}# Added by Albedo${NC}"

  if [[ -n "$API_KEY" ]]; then
    # Show masked key
    local masked_key="${API_KEY:0:8}...${API_KEY: -4}"
    echo -e "  ${CYAN}export $API_KEY_VAR=\"$masked_key\"${NC}"
  fi

  echo -e "  ${CYAN}export PATH=\"\$PATH:$albedo_dir\"${NC}"
  echo ""

  if ! prompt_yes_no "Proceed?" "y"; then
    print_info "Skipped. You can configure manually later."
    SHELL_PROFILE=""
    return
  fi

  # Check what already exists
  local lines_to_add=""
  local skipped=0

  if [[ -f "$shell_profile" ]]; then
    local content
    content=$(cat "$shell_profile")

    if [[ -n "$API_KEY" ]]; then
      if grep -q "^export $API_KEY_VAR=" "$shell_profile"; then
        # Replace existing line
        sed -i.bak "s|^export $API_KEY_VAR=.*|export $API_KEY_VAR=\"$API_KEY\"|" "$shell_profile"
        rm -f "${shell_profile}.bak"
        print_info "Replaced existing $API_KEY_VAR"
      else
        lines_to_add+="export $API_KEY_VAR=\"$API_KEY\"\n"
      fi
    fi

    if ! grep -q "PATH.*albedo" "$shell_profile"; then
      lines_to_add+="export PATH=\"\$PATH:$albedo_dir\"\n"
    else
      ((skipped++)) || true
    fi
  else
    if [[ -n "$API_KEY" ]]; then
      lines_to_add+="export $API_KEY_VAR=\"$API_KEY\"\n"
    fi
    lines_to_add+="export PATH=\"\$PATH:$albedo_dir\"\n"
  fi

  if [[ -n "$lines_to_add" ]]; then
    echo -e "\n# Added by Albedo\n$lines_to_add" >> "$shell_profile"
    local added
    added=$(echo -e "$lines_to_add" | grep -c "export" || true)
    print_success "Added $added line(s) to $shell_profile"
  fi

  if [[ $skipped -gt 0 ]]; then
    print_info "Skipped $skipped line(s) (already exist)"
  fi

  SHELL_PROFILE="$shell_profile"
}

print_completion() {
  echo ""
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${GREEN}  Installation Complete!${NC}"
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""

  if [[ -n "$SHELL_PROFILE" ]]; then
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}  IMPORTANT: Activate your shell environment${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "Your API key and PATH were added to $SHELL_PROFILE"
    echo "but your current terminal session doesn't have them yet."
    echo ""
    echo "Run this command now:"
    echo ""
    echo -e "  ${CYAN}source $SHELL_PROFILE${NC}"
    echo ""
    echo "Or restart your terminal."
    echo ""
  fi

  echo ""
  echo "Configuration:"
  echo -e "  Provider:    ${CYAN}$PROVIDER${NC}"
  echo -e "  Config:      ${CYAN}~/.albedo/config.toml${NC}"
  echo -e "  Sessions:    ${CYAN}~/.albedo/sessions/${NC}"
  echo ""
  echo "Quick start:"
  echo -e "  ${CYAN}albedo --help${NC}                          # Show help"
  echo -e "  ${CYAN}albedo config${NC}                          # View configuration"
  echo -e "  ${CYAN}albedo analyze . --task \"Add feature\"${NC}  # Analyze codebase"
  echo -e "  ${CYAN}albedo plan --name myapp --task \"...\"${NC}  # Plan new project"
  echo -e "  ${CYAN}albedo-tui${NC}                              # Interactive terminal UI"
  echo ""

  if [[ -z "$API_KEY" ]]; then
    echo -e "${YELLOW}Note: API key not set. Run 'albedo config set-key' to set it.${NC}"
    echo ""
  fi
}

main() {
  print_header

  OS=$(detect_os)
  print_info "Detected OS: $OS"

  check_prerequisites
  build_albedo

  # Provider and API key setup
  PROVIDER="gemini"
  API_KEY=""
  API_KEY_VAR="GEMINI_API_KEY"
  setup_provider_and_key

  # Create config.toml with selected provider
  create_config

  # Shell profile setup (API key + PATH)
  SHELL_PROFILE=""
  setup_shell_profile

  print_completion
}

# Run main
main
