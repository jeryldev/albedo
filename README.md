# Albedo

> **Codebase-to-Tickets CLI Tool** - Gain clarity on any codebase and turn ideas into actionable work.

[![Status: Beta](https://img.shields.io/badge/Status-Beta-yellow.svg)](https://github.com/jeryldev/albedo)
[![Elixir](https://img.shields.io/badge/Elixir-1.15+-purple.svg)](https://elixir-lang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

## What is Albedo?

In alchemy, **albedo** (Latin for "whiteness") is the second stage of the *magnum opus* - the purification phase where **clarity emerges from chaos**. After the initial *nigredo* (decomposition), albedo represents the moment of illumination and understanding.

This project embodies that concept: **Albedo brings clarity to codebases**, helping you understand unfamiliar code and transform vague feature ideas into clear, actionable implementation plans.

Albedo acts as a **senior technical leader** that:
- Investigates your codebase structure, conventions, and patterns
- Understands the domain and technology stack
- Locates code relevant to your feature request
- Traces dependencies and impact areas
- Produces detailed tickets with implementation guidance

## Status

**This project is in beta and actively being developed.** Expect breaking changes. Contributions and feedback are welcome!

## Quick Start

### Prerequisites

- Elixir 1.15+ and Erlang/OTP 26+
- [ripgrep](https://github.com/BurntSushi/ripgrep) (`brew install ripgrep` or `apt install ripgrep`)
- An API key from one of: Google AI (Gemini), Anthropic (Claude), or OpenAI

### Installation

```bash
# Clone the repository
git clone https://github.com/jeryldev/albedo.git
cd albedo

# Install dependencies
mix deps.get

# Build the CLI
mix escript.build

# Initialize configuration
./albedo init
```

### Adding to PATH (Optional)

To run `albedo` from anywhere instead of `./albedo`:

#### macOS / Linux

Add to your `~/.zshrc` or `~/.bashrc`:

```bash
# Option 1: Add the albedo directory to PATH
export PATH="$PATH:/path/to/albedo"

# Option 2: Or create a symlink to a directory already in PATH
sudo ln -sf /path/to/albedo/albedo /usr/local/bin/albedo
```

Then reload your shell:
```bash
source ~/.zshrc  # or source ~/.bashrc
```

#### Windows (PowerShell)

```powershell
# Add to your PowerShell profile
$env:Path += ";C:\path\to\albedo"

# Or permanently add to system PATH (run as Administrator)
[Environment]::SetEnvironmentVariable("Path", $env:Path + ";C:\path\to\albedo", "User")
```

#### Windows (Command Prompt)

```cmd
# Temporarily for current session
set PATH=%PATH%;C:\path\to\albedo

# Permanently (run as Administrator)
setx PATH "%PATH%;C:\path\to\albedo"
```

After adding to PATH, you can run Albedo from anywhere:
```bash
albedo --help
albedo analyze ~/projects/myapp --task "Add user authentication"
```

### Setting Up API Keys

Albedo supports three LLM providers. You only need **one** to get started.

#### Option 1: Google Gemini (Recommended - Free tier available)

1. Go to [Google AI Studio](https://aistudio.google.com)
2. Click "Get API Key" and create a new key
3. Set the environment variable:
   ```bash
   export GEMINI_API_KEY="your-api-key-here"
   ```

#### Option 2: Anthropic Claude

1. Go to [Anthropic Console](https://console.anthropic.com)
2. Create an API key under Settings
3. Set the environment variable:
   ```bash
   export ANTHROPIC_API_KEY="your-api-key-here"
   ```

#### Option 3: OpenAI

1. Go to [OpenAI Platform](https://platform.openai.com)
2. Create an API key under API Keys
3. Set the environment variable:
   ```bash
   export OPENAI_API_KEY="your-api-key-here"
   ```

### Configure Your Provider

Edit `~/.albedo/config.toml` to set your preferred provider:

```toml
[llm]
provider = "gemini"  # or "claude" or "openai"

[llm.gemini]
api_key_env = "GEMINI_API_KEY"
model = "gemini-2.0-flash"

[llm.claude]
api_key_env = "ANTHROPIC_API_KEY"
model = "claude-sonnet-4-20250514"

[llm.openai]
api_key_env = "OPENAI_API_KEY"
model = "gpt-4o"
```

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
Session: 2024-12-24_sqlite-storage
Output: ~/.albedo/sessions/2024-12-24_sqlite-storage/FEATURE.md

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
| `albedo init` | Initialize configuration (first-time setup) |
| `albedo analyze <path> --task "..."` | Analyze a codebase with a feature request |
| `albedo plan --name <name> --task "..."` | Plan a new project from scratch (greenfield) |
| `albedo resume <session_path>` | Resume an incomplete analysis session |
| `albedo sessions` | List recent analysis sessions |
| `albedo show <session_id>` | Display a session's FEATURE.md output |
| `albedo replan <session_path>` | Re-run the planning phase |

### Options

| Option | Alias | Description |
|--------|-------|-------------|
| `--task <desc>` | `-t` | Task/feature description (required for analyze/plan) |
| `--name <name>` | `-n` | Project name (required for plan command) |
| `--stack <stack>` | | Tech stack hint: `phoenix`, `rails`, `nextjs`, `fastapi`, etc. |
| `--database <db>` | | Database hint: `postgres`, `mysql`, `sqlite`, `mongodb` |
| `--interactive` | `-i` | Enable interactive clarifying questions |
| `--output <format>` | `-o` | Output format: `markdown` (default), `linear`, `jira` |
| `--project <name>` | `-p` | Project/team name for ticket system integration |
| `--scope <scope>` | `-s` | Planning scope: `full` (default), `minimal` |
| `--help` | `-h` | Show help message |
| `--version` | `-v` | Show version |

## Greenfield Planning: Building from Scratch

Albedo can also plan brand new projects that don't exist yet. Use the `plan` command when you're starting from scratch.

**Note:** You don't need to create a project folder first. Albedo produces a planning document with tickets - it doesn't create the actual project files. After planning, you create the project and implement based on the generated tickets.

**Where are session files stored?**

All sessions (both `analyze` and `plan`) are stored in `~/.albedo/sessions/`:

```
~/.albedo/
├── config.toml                     # Your configuration
└── sessions/
    └── 2024-12-24_my-todo-app/     # Session folder (date + task slug)
        ├── session.json            # Session state and metadata
        ├── 00_domain_research.md   # Domain analysis
        ├── 01_tech_stack.md        # Tech stack detection (skipped for greenfield)
        ├── 02_architecture.md      # Architecture mapping (skipped for greenfield)
        ├── 03_conventions.md       # Code conventions (skipped for greenfield)
        ├── 04_feature_location.md  # Relevant code locations (skipped for greenfield)
        ├── 05_impact_analysis.md   # Dependency tracing (skipped for greenfield)
        └── FEATURE.md              # Final tickets and implementation plan
```

For greenfield projects, only `00_domain_research.md` and `FEATURE.md` are generated since there's no codebase to analyze.

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
  ├─ Change planning...
  │  └─ ✓ Saved FEATURE.md

Planning complete!
Session: 2024-12-24_e-commerce-api
Output: ~/.albedo/sessions/2024-12-24_e-commerce-api/FEATURE.md

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
