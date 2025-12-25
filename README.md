# Albedo

> **Ideas-to-Tickets CLI Tool** - Turn feature ideas into actionable implementation plans.

[![Status: Beta](https://img.shields.io/badge/Status-Beta-yellow.svg)](https://github.com/jeryldev/albedo)
[![Elixir](https://img.shields.io/badge/Elixir-1.15+-purple.svg)](https://elixir-lang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

## What is Albedo?

In alchemy, **albedo** (Latin for "whiteness") is the second stage of the *magnum opus* - the purification phase where **clarity emerges from chaos**. After the initial *nigredo* (decomposition), albedo represents the moment of illumination and understanding.

This project embodies that concept: **Albedo brings clarity to your ideas**, helping you transform vague feature requests into clear, actionable implementation plans.

### For Existing Codebases

Albedo analyzes your codebase and generates implementation tickets:
- Investigates structure, conventions, and patterns
- Locates code relevant to your feature request
- Traces dependencies and impact areas
- Produces detailed tickets with file-level guidance

### For New Projects (Greenfield)

Albedo helps you plan projects from scratch:
- Researches the problem domain
- Recommends tech stack and architecture
- Designs initial project structure
- Generates setup and implementation tickets

## Status

**This project is in beta and actively being developed.** Expect breaking changes. Contributions and feedback are welcome!

## Quick Start

### Prerequisites

- **Elixir 1.15+** and **Erlang/OTP 26+**
- **[ripgrep](https://github.com/BurntSushi/ripgrep)** - Fast code search tool
- An **API key** from one of: Google AI (Gemini), Anthropic (Claude), or OpenAI

### Installation

```bash
# Clone and install
git clone https://github.com/jeryldev/albedo.git
cd albedo
./install.sh
```

The interactive installer will:
1. **Check prerequisites** - Detect Elixir and ripgrep
2. **Offer to install missing tools** - Uses asdf (recommended) or Homebrew/apt
3. **Build the CLI** - Compile and create the `albedo` binary
4. **Set up your provider** - Choose Gemini, Claude, or OpenAI
5. **Configure your API key** - Store securely in shell profile
6. **Add to PATH** - Make `albedo` available globally

**Important:** After installation, run `source ~/.zshrc` (or `~/.bashrc`) to activate your API key and PATH in the current terminal, or restart your terminal.

#### Recommended: Using asdf for Version Management

For Elixir developers, we recommend [asdf](https://asdf-vm.com/) for managing Elixir/Erlang versions. The installer will automatically detect and use asdf if available.

```bash
# If you don't have asdf, install it first:
# https://asdf-vm.com/guide/getting-started.html

# Then add Erlang and Elixir plugins
asdf plugin add erlang
asdf plugin add elixir
asdf install erlang latest && asdf global erlang latest
asdf install elixir latest && asdf global elixir latest
```

### Supported Providers

| Provider | Get API Key | Free Tier |
|----------|-------------|-----------|
| **Google Gemini** (default) | [Google AI Studio](https://aistudio.google.com) | Yes |
| Anthropic Claude | [Anthropic Console](https://console.anthropic.com) | No |
| OpenAI | [OpenAI Platform](https://platform.openai.com) | No |

<details>
<summary>Manual setup (without install.sh)</summary>

```bash
# Build manually
mix deps.get
mix escript.build

# Add to ~/.zshrc or ~/.bashrc
export GEMINI_API_KEY="your-api-key"      # Your API key
export PATH="$PATH:/path/to/albedo"       # Add to PATH
```

Then run: `source ~/.zshrc`

Provider is configured in `~/.albedo/config.toml` (created on first run).
Use `albedo config set-provider` to change providers.

</details>

## Quick Demo

<!-- TODO: Add screen recording here -->

## Example: Analyzing a Python CLI Todo App

Let's say you want to build a CLI todo list application in Python. First, create a simple project:

```bash
# Create a sample Python project
mkdir ~/projects/pytodo && cd ~/projects/pytodo

# Create a basic structure
mkdir -p src tests
touch src/__init__.py src/main.py src/todo.py requirements.txt
echo "click>=8.0" > requirements.txt
```

Add some starter code to `src/todo.py`:
```python
class TodoItem:
    def __init__(self, title, completed=False):
        self.title = title
        self.completed = completed

class TodoList:
    def __init__(self):
        self.items = []

    def add(self, title):
        self.items.append(TodoItem(title))

    def list_all(self):
        return self.items
```

Now, ask Albedo to plan a feature:

```bash
./albedo analyze ~/projects/pytodo \
  --task "Add persistent storage using SQLite so todos survive restarts. Include CLI commands for add, list, complete, and delete."
```

Albedo will:
1. **Research the domain** - Understand todo list concepts and SQLite patterns
2. **Analyze the tech stack** - Detect Python, Click CLI framework, etc.
3. **Map the architecture** - Understand your module structure
4. **Identify conventions** - Learn your coding style
5. **Locate relevant code** - Find `TodoItem`, `TodoList` classes
6. **Trace dependencies** - See what depends on your data models
7. **Generate tickets** - Produce a `FEATURE.md` with actionable implementation steps

Output example:
```
Analysis complete!
Session: 2025-01-15_sqlite-storage
Output: ~/.albedo/sessions/2025-01-15_sqlite-storage/FEATURE.md

Summary:
  - 5 tickets generated
  - 8 story points estimated
  - 3 files to create
  - 2 files to modify
  - 1 risk identified
```

## Commands

| Command | Description |
|---------|-------------|
| `albedo init` | Initialize configuration and check prerequisites |
| `albedo analyze <path> --task "..."` | Analyze a codebase with a feature request |
| `albedo plan --name <name> --task "..."` | Plan a new project from scratch (greenfield) |
| `albedo resume <session_path>` | Resume an incomplete analysis session |
| `albedo sessions` | List recent analysis sessions |
| `albedo show <session_id>` | Display a session's FEATURE.md output |
| `albedo replan <session_path>` | Re-run the planning phase |
| `albedo path <session_id>` | Print session path (for use with cd) |
| `albedo config [subcommand]` | Manage configuration (show, set-provider, set-key) |
| `albedo tickets` | List tickets from the latest session |
| `albedo tickets show <id>` | Show detailed ticket information |
| `albedo tickets start <id>` | Mark a ticket as in-progress |
| `albedo tickets done <id> [id...]` | Mark ticket(s) as completed |
| `albedo tickets reset [--all]` | Reset ticket status to pending |
| `albedo tickets edit <id>` | Edit ticket priority/points |
| `albedo tickets export [--format]` | Export tickets (json, csv, markdown, github) |

### Options

| Option | Alias | Description |
|--------|-------|-------------|
| `--task <desc>` | `-t` | Task/feature description (required for analyze/plan) |
| `--name <name>` | `-n` | Project name (required for plan command) |
| `--session <name>` | `-S` | Custom session name (optional, for easier reference) |
| `--stack <stack>` | | Tech stack hint: `phoenix`, `rails`, `nextjs`, `fastapi`, etc. |
| `--database <db>` | | Database hint: `postgres`, `mysql`, `sqlite`, `mongodb` |
| `--interactive` | `-i` | Enable interactive clarifying questions |
| `--scope <scope>` | `-s` | Planning scope: `full` (default), `minimal` |
| `--help` | `-h` | Show help message |
| `--version` | `-v` | Show version |

### Configuration Management

```bash
# Show current configuration (provider, API key status, paths)
albedo config

# Change LLM provider (gemini, claude, openai)
albedo config set-provider

# Set API key for current provider
albedo config set-key
```

### Ticket Management

After analysis, manage your implementation tickets:

```bash
# List all tickets from the latest session
albedo tickets

# List tickets from a specific session
albedo tickets --session my-feature

# Filter by status
albedo tickets --status pending
albedo tickets --status in_progress
albedo tickets --status completed

# View ticket details
albedo tickets show 1

# Update ticket status
albedo tickets start 1        # Mark as in-progress
albedo tickets done 1 2 3     # Mark multiple as completed
albedo tickets reset 1        # Reset to pending
albedo tickets reset --all    # Reset all tickets

# Edit ticket priority and points
albedo tickets edit 1 --priority high   # Change priority
albedo tickets edit 1 --points 5        # Change story points
albedo tickets edit 1 -p medium --points 3  # Both at once

# Export tickets
albedo tickets export                          # JSON to stdout
albedo tickets export --format csv -o out.csv  # CSV to file
albedo tickets export --format markdown        # Markdown checklist
albedo tickets export --format github          # GitHub Issues format
```

## Greenfield Planning: Building from Scratch

Albedo can also plan brand new projects that don't exist yet. Use the `plan` command when you're starting from scratch.

**Note:** You don't need to create a project folder first. Albedo produces a planning document with tickets - it doesn't create the actual project files. After planning, you create the project and implement based on the generated tickets.

**Where are session files stored?**

All sessions (both `analyze` and `plan`) are stored in `~/.albedo/sessions/`:

```
~/.albedo/
├── config.toml                     # Your configuration
└── sessions/
    ├── auth-feature/               # Custom session name (--session auth-feature)
    └── 2025-01-15_my-todo-app_0042/  # Auto-generated (date + task slug + id)
        ├── session.json            # Session state and metadata
        ├── 00_domain_research.md   # Domain analysis
        ├── 01_tech_stack.md        # Tech stack recommendations
        ├── 02_architecture.md      # Architecture design
        ├── 03_conventions.md       # Code conventions (existing codebases only)
        ├── 04_feature_location.md  # Relevant code locations (existing codebases only)
        ├── 05_impact_analysis.md   # Dependency tracing (existing codebases only)
        └── FEATURE.md              # Final tickets and implementation plan
```

**Tip:** Use `--session` or `-S` to give your session a memorable name:
```bash
albedo analyze ~/myapp --task "Add auth" --session auth-feature
albedo show auth-feature       # View the output
cd $(albedo path auth-feature) # Jump to session folder
```

For greenfield projects, phases 03-05 are skipped since there's no codebase to analyze. The tool generates domain research, tech stack recommendations, architecture design, and implementation tickets.

```bash
# No folder needed - just run from anywhere
albedo plan \
  --name my_todo_app \
  --task "Build a todo app with user authentication, tags, and sharing" \
  --stack phoenix \
  --database postgres
```

### When to Use Greenfield vs Analyze

| Use `analyze` when... | Use `plan` when... |
|-----------------------|-------------------|
| You have an existing codebase | You're starting from scratch |
| Adding features to existing code | Building a new project |
| Modifying or refactoring | Designing initial architecture |

### Greenfield Example

```bash
./albedo plan \
  --name shop_api \
  --task "Build an e-commerce REST API with products, orders, and payments" \
  --stack phoenix \
  --database postgres
```

Output:
```
Planning greenfield project: shop_api
──────────────────────────────────────────────────
  ├─ Domain research...
  │  └─ ✓ Saved 00_domain_research.md
  ├─ Tech stack...
  │  └─ ✓ Saved 01_tech_stack.md
  ├─ Architecture...
  │  └─ ✓ Saved 02_architecture.md
  ├─ Change planning...
  │  └─ ✓ Saved FEATURE.md

Planning complete!
Session: 2025-01-15_e-commerce-api
Output: ~/.albedo/sessions/2025-01-15_e-commerce-api/FEATURE.md

Summary:
  • 12 tickets generated
  • 21 story points estimated
  • 15 files to create
  • Recommended stack: Phoenix + Ecto + PostgreSQL
  • 8 setup steps
```

The greenfield plan includes:
- Project structure recommendations
- Technology stack guidance
- Initial architecture design
- Setup/installation tickets
- Feature implementation tickets
- Testing strategy

## How It Works

Albedo runs a 7-phase analysis pipeline:

```
Phase 0: Domain Research      - Understand the business domain
Phase 1a: Tech Stack          - Detect languages, frameworks, databases
Phase 1b: Architecture        - Map module structure and relationships
Phase 1c: Conventions         - Learn coding patterns and styles
Phase 2: Feature Location     - Find code related to your task
Phase 3: Impact Analysis      - Trace dependencies and side effects
Phase 4: Change Planning      - Generate detailed implementation tickets
```

Each phase builds context for the next, resulting in tickets that understand your codebase deeply.

## Development

```bash
# Run tests
mix test

# Run with warnings as errors
mix compile --warnings-as-errors

# Run static analysis
mix credo --strict

# Format code
mix format
```

## Contributing

Contributions are welcome! This project is in active development.

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Run tests (`mix test`)
5. Commit (`git commit -m 'Add amazing feature'`)
6. Push (`git push origin feature/amazing-feature`)
7. Open a Pull Request

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- Built with [Elixir](https://elixir-lang.org/)
- Uses [Owl](https://github.com/fuelen/owl) for terminal UI
- Powered by Gemini, Claude, and OpenAI language models
