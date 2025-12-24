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

# Detect if script is being sourced
SOURCED=false
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  SOURCED=true
fi

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

check_prerequisites() {
  print_info "Checking prerequisites..."

  local missing=()

  if ! check_command elixir; then
    missing+=("elixir")
  else
    print_success "Elixir found: $(elixir --version | head -1)"
  fi

  if ! check_command mix; then
    missing+=("mix")
  fi

  if ! check_command rg; then
    missing+=("ripgrep (rg)")
  else
    print_success "ripgrep found: $(rg --version | head -1)"
  fi

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo ""
    print_error "Missing required tools: ${missing[*]}"
    echo ""
    echo "Please install them first:"

    OS=$(detect_os)
    case $OS in
      macos)
        echo "  brew install elixir ripgrep"
        ;;
      linux)
        echo "  # For Ubuntu/Debian:"
        echo "  sudo apt install elixir ripgrep"
        echo ""
        echo "  # For Fedora:"
        echo "  sudo dnf install elixir ripgrep"
        ;;
      *)
        echo "  See: https://elixir-lang.org/install.html"
        echo "  See: https://github.com/BurntSushi/ripgrep#installation"
        ;;
    esac
    exit 1
  fi

  echo ""
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

setup_api_key() {
  echo ""
  if ! prompt_yes_no "Would you like to set up an API key?" "y"; then
    return 1
  fi

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
    print_info "Skipped API key setup."
    return 1
  fi

  return 0
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

  if [[ -n "$PROVIDER" ]]; then
    echo -e "  ${CYAN}export ALBEDO_PROVIDER=\"$PROVIDER\"${NC}"
  fi

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

    if [[ -n "$PROVIDER" ]] && ! grep -q "ALBEDO_PROVIDER" "$shell_profile"; then
      lines_to_add+="export ALBEDO_PROVIDER=\"$PROVIDER\"\n"
    else
      ((skipped++)) || true
    fi

    if [[ -n "$API_KEY" ]] && ! grep -q "$API_KEY_VAR" "$shell_profile"; then
      lines_to_add+="export $API_KEY_VAR=\"$API_KEY\"\n"
    else
      ((skipped++)) || true
    fi

    if ! grep -q "PATH.*albedo" "$shell_profile"; then
      lines_to_add+="export PATH=\"\$PATH:$albedo_dir\"\n"
    else
      ((skipped++)) || true
    fi
  else
    if [[ -n "$PROVIDER" ]]; then
      lines_to_add+="export ALBEDO_PROVIDER=\"$PROVIDER\"\n"
    fi
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

create_config_dir() {
  print_info "Creating config directory..."
  mkdir -p "$HOME/.albedo/sessions"
  print_success "Config directory created at ~/.albedo/"
}

print_completion() {
  echo ""
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${GREEN}  Installation Complete!${NC}"
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""

  if [[ -n "$SHELL_PROFILE" ]]; then
    if [[ "$SOURCED" == "true" ]]; then
      echo -e "${CYAN}Applying changes...${NC}"
      # shellcheck source=/dev/null
      source "$SHELL_PROFILE"
      echo ""
      print_success "Changes applied! You can now use 'albedo' directly."
    else
      echo "To apply changes, run:"
      echo ""
      echo -e "  ${CYAN}source $SHELL_PROFILE${NC}"
      echo ""
      echo "Or restart your terminal."
    fi
  fi

  echo ""
  echo "Quick start:"
  echo -e "  ${CYAN}albedo --help${NC}                          # Show help"
  echo -e "  ${CYAN}albedo analyze . --task \"Add feature\"${NC}  # Analyze codebase"
  echo -e "  ${CYAN}albedo plan --name myapp --task \"...\"${NC}  # Plan new project"
  echo ""
}

main() {
  print_header

  OS=$(detect_os)
  print_info "Detected OS: $OS"

  check_prerequisites
  build_albedo
  create_config_dir

  # API key setup (sets PROVIDER, API_KEY, API_KEY_VAR)
  PROVIDER=""
  API_KEY=""
  API_KEY_VAR=""
  setup_api_key || true

  # Shell profile setup
  SHELL_PROFILE=""
  setup_shell_profile

  print_completion
}

# Run main
main
