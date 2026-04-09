# PP - Pure Python AI Command-Line Agent

A general-purpose AI command-line agent written in **pure Python 3+** with zero dependencies. No virtual environments, no `pip install` required.

## Quick Start

```bash
# Make executable (if needed)
chmod +x ./pp

# Run the help menu
./pp help
```

## Features

### 🚀 Zero Dependencies
- Written in pure Python 3+
- No external packages required
- Works out of the box on any system with Python 3

### 🔧 Built-in Tools
PP provides a rich set of tools that can be called by AI models:

| Tool | Description |
|------|-------------|
| `bash` | Execute shell commands in current directory |
| `read` | Read file contents (supports offset/limit for large files) |
| `write` | Write content to files, creates directories automatically |
| `edit` | Edit files using exact text replacement |
| `context` | Collect user responses to prompts via stdin |

### 💬 Interactive Shell Commands

#### Configuration
```bash
./pp help              # Show this help menu and exit
./pp set <KEY> <VALUE> # Set a configuration value (session or global)
./pp get <KEY>         # Get a configuration value
```

#### Interaction & Tools
```bash
./pp message | m       # Send a new message to the LLM service
                       # Reads input from stdin, then sends it with context

./pp send              # Continue conversation using previous messages as context
                       # Sends all accumulated messages back to the API

./pp tools             # Process tool calls returned by the LLM
                       # Executes any requested tools (bash, read, write, edit)

./pp echo <INDEX>      # Display a message from the session history
                       # Can specify position with argument

./pp new              # Start a fresh session (clears current conversation)
```

#### Additional Commands
```bash
./pp models           # List available AI models from the configured server

./pp tree             # Display the session as a hierarchical tree structure
```

### 📝 Message Options

**For `message` command:**
- `-m <TEXT>` - Use commandline mode with specified text
- `--` - Read message content from stdin
- `-b <ID|ROOT>` - Set base message ID (use ROOT to start fresh)
- `-r` - Start a fresh conversation. Like `-b ROOT`

**For `send` command:**
- `-b <ID>` - Set base message ID

### 🎨 Editor Integration
PP integrates with your system's default editor:
```bash
# Configure custom editor (optional)
./pp set global.editor vim
```

When composing messages, PP will open your preferred editor with the previous message content pre-filled.

## Configuration

Configuration is stored in two locations:
1. `./.pp_config` - Local session configuration
2. `~/.pp_config` - Global user configuration

### Available Config Keys
- `url` - LLM API endpoint (default: http://localhost:1234)
- `model` - AI model name to use
- `timeout` - Request timeout in seconds (default: 100)
- `editor` - Default editor command
- `session` - Session file path

## Architecture Overview

```
┌─────────────────────────────────────┐
│           PP CLI Agent              │
├─────────────────────────────────────┤
│  ┌──────────────┐                   │
│  │   Shell      │◄──────────────────┼── Commands
│  │   Interface  │                  │
│  └──────────────┘                  │
│         │                          │
│  ┌──────▼─────────────────────────┐│
│  │     Session Manager            ││
│  │  (Persistent conversation)     ││
│  └────────────────────────────────┘│
│         │                          │
│  ┌──────▼─────────────────────────┐│
│  │      Tool Registry             ││
│  │   bash | read | write | edit   ││
│  └────────────────────────────────┘│
│         │                          │
│  ┌──────▼─────────────────────────┐│
│  │     LLM API Client             ││
│  │   (Configurable endpoint)      ││
│  └────────────────────────────────┘│
└─────────────────────────────────────┘
```

## Example Workflow

```bash
# Start a new session
./pp new

# Compose a message using your editor
./pp message
# [Your editor opens here]

# Send the accumulated messages to the AI
./pp send

# The AI responds and may trigger tool calls
./pp tools  # Execute any requested tools
```

## API Compatibility

PP is designed to work with any LLM API that supports:
- `/v1/chat/completions` endpoint (OpenAI-compatible)
- JSON request/response format
- Tool/function calling protocol

## License

MIT License - Feel free to use, modify, and distribute.
