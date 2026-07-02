# Multi-Vendor Agentic Coder Docker Templates (Colima Compatible)

An isolated, secure containerized development environment framework designed specifically for running autonomous coding agents on your local web applications. It supports multiple LLM CLI agents (Gemini, Claude, Mistral) via a pluggable, unified runner interface and shares a single global safety guidelines configuration.

### 💡 Why Colima? (Enterprise Licensing Benefits)
Docker Desktop requires a paid subscription for commercial use in larger organizations (defined as **more than 250 employees OR more than $10 million in annual revenue**). 

To run containerized development environments without requiring a paid subscription, developers can use free, open-source alternatives depending on their host operating system:
* **macOS**: Use **Colima**, a lightweight, open-source tool that runs a standard Docker Engine inside a macOS VM.
* **Windows**: Colima is not supported on Windows. Use **WSL2 (Windows Subsystem for Linux)** with a native Docker Engine installation.
* **Linux**: Colima is redundant on Linux. The Docker Engine runs natively on Linux free of charge.

This project is fully compatible with native Docker engines, WSL2 environments, and Colima setups out of the box.

---

## Workspace Structure

The project is structured with pluggable configs and a centralized runner at the root:

```text
/Users/localkevin/workspace/Agentic Docker Image/
├── run-agent.sh                 # Central Bash runner script
├── run-agent.ps1                # Central PowerShell runner script
├── guidelines.txt               # Global safety guidelines (appended to all prompts)
├── prompt.txt / prompt.md       # Shared prompt file (either is supported)
├── README.md                    # This instructions file
├── config/                      # Pluggable driver configurations
│   ├── gemini.conf              # Gemini driver config (Bash)
│   ├── gemini.psd1              # Gemini driver config (PowerShell)
│   ├── mistral.conf             # Mistral driver config (Bash)
│   ├── mistral.psd1             # Mistral driver config (PowerShell)
│   ├── claude.conf              # Claude driver config (Bash)
│   └── claude.psd1              # Claude driver config (PowerShell)
├── gemini/
│   └── Dockerfile               # Gemini (Antigravity CLI) Docker build
├── mistral/
│   └── Dockerfile               # Mistral (Vibe CLI) Docker build
└── claude/
    └── Dockerfile               # Claude (Claude Code CLI) Docker build
```

---

## 🔒 Security Model & Sandbox Execution

### **No Git (`git` is omitted)**
To ensure maximum security, **Git is not installed on any of the Docker images**. 

This creates a strict security boundary:
1. The agent running inside the container cannot access your host's global Git credentials or SSH keys.
2. The agent cannot write unauthorized commits, modify Git history, or execute `git push` to your remote repositories.
3. You review all changes on your host machine using your local Git client before staging and pushing.

### **Execution Roles (Read-Write vs. Read-Only)**
To prevent agents from being "too eager" to modify the workspace, the runner supports role-based workspace mounting:
* **Coder Mode (`default`)**: Mounts the workspace as read-write (`rw`). The agent is allowed to edit code, initialize files, and execute scripts.
* **Design/Spec Mode (`design` / `spec`)**: Mounts the workspace as **read-only** (`ro`). This physical boundary guarantees that the container cannot modify any files. The runner automatically appends specific design and planning instructions to guide the agent.

---

## Technical Stack & Shared Tooling

All Docker images include the following pre-configured runtimes and developer tools:

### Installed Runtimes & CLIs
* **Node.js** (v20.x) & **npm** (v10.x)
* **TypeScript** (v6.x) & `ts-node`
* **Python** (v3.11.x) & `pip`
* **Global Linters & Formatters**: `eslint`, `prettier`
* **Bundlers**: `webpack`, `webpack-cli`
* **CLI Utilities**: `curl`, `ca-certificates`, `wget`, `jq`, `ripgrep` (`rg`), and `build-essential`.

### Python Virtual Environment
To bypass PEP 668 restrictions ("externally-managed-environment") in modern Debian systems, a global virtual environment is pre-configured at `/opt/venv` and injected directly into the container's `PATH`. Any python packages installed by agents will automatically compile inside this environment safely.

---

## Global Guidelines (`guidelines.txt`)

The `guidelines.txt` file at the root of the project contains shared rules and safety boundaries. The runner script will **automatically append** the contents of `guidelines.txt` to the end of every prompt you run. 

This is highly useful for defining permanent system instructions or safety rules for the agent.

---

## Command Syntax & Options

The centralized runner supports the following options:

```bash
run-agent.sh [options] [workspace_path] [prompt_arguments]
```

### Options:
* `-c | --container | --engine <name>`: The engine driver to load from `config/` (`gemini`, `claude`, `mistral`). Defaults to `gemini`.
* `-r | --role | --mode <role>`: The execution role (`coder`, `design`, `spec`). Defaults to `coder`.
* `-p | --prompt <string>`: Directly passes the prompt.

---

## Vendor Details & Authentication

Ensure **Colima** (or your local Docker daemon) is active on your host machine: `colima start`

### 1. Gemini (Antigravity CLI)
* **Command:** `agy`
* **Auth Modes:**
  - **API Key:** Export `GEMINI_API_KEY="your_key"` on your host.
  - **Google One OAuth:** Unset `GEMINI_API_KEY` on your host. Runs interactively to complete browser OAuth.
* **Volume Persistence:** Mounts named volume `agentic-coder-gemini` to `/home/node/.gemini` to save settings and OAuth credentials.

### 2. Mistral (Vibe CLI)
* **Command:** `vibe`
* **Auth Modes:**
  - **API Key:** Export `MISTRAL_API_KEY="your_key"` on your host.
  - **Interactive Setup:** Unset `MISTRAL_API_KEY` and run interactively to input your Mistral API key.
* **Volume Persistence:** Mounts named volume `agentic-coder-vibe` to `/home/node/.vibe` to preserve `config.toml`.

### 3. Claude (Claude Code)
* **Command:** `claude`
* **Auth Modes:**
  - **API Key:** Export `ANTHROPIC_API_KEY="your_key"` on your host.
  - **Anthropic OAuth:** Unset `ANTHROPIC_API_KEY` and run interactively to copy-paste browser OAuth credentials.
* **Volume Persistence:** Mounts named volume `agentic-coder-claude` to `/home/node/.claude` to store active browser OAuth sessions.

---

## 💻 Zsh Aliases for Easy Execution

You can add these global aliases to your `~/.zshrc` to launch the agents easily from anywhere on your Mac:

```bash
# Central Agent Runner
alias run-agent='"/Users/localkevin/workspace/Agentic Docker Image/run-agent.sh"'

# Quick Engine Launchers
alias agy-run='run-agent -c gemini'
alias vibe-run='run-agent -c mistral'
alias claude-run='run-agent -c claude'

# Read-Only Specification/Design Mode
alias spec-run='run-agent -r design'
```

Reload your profile (`source ~/.zshrc`), then execute them like:
```bash
# Run Claude as a coder with a prompt
claude-run /path/to/web-app "Refactor buttons to typescript"

# Run Gemini in Read-Only Design Mode to draft code specs
spec-run -c gemini /path/to/web-app "Draft an architecture plan for task management"
```
