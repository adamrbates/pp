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
| `edit` | Edit files using exact text replacement with confirmation |
| `context` | Collect user responses to prompts via stdin |

### 🛠️ Plugin System
PP supports a plugin system that allows you to extend functionality with custom tools:

```bash
# Create plugins directory
mkdir -p ~/.pp/plugins

# Add your custom tool
./pp help  # Will show: "Loaded X plugin tool(s)"
```

**Creating a Plugin:**

1. Create a Python file in `~/.pp/plugins/`:
```python
# ~/.pp/plugins/mytool.py

def register():
    """Register new tools with PP"""
    
    my_tool = {
        "function": my_function,
        "definition": {
            "type": "function",
            "function": {
                "name": "mytool",
                "description": "A custom tool for doing something special",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "input": {
                            "type": "string",
                            "description": "Input data to process"
                        }
                    },
                    "required": ["input"]
                }
            }
        }
    }
    
    return {"mytool": my_tool}

def my_function(config, session, args):
    """The actual tool implementation"""
    input_data = args.get("input", "")
    result = f"Processed: {input_data}"
    
    return {
        "args": args,
        "results": {
            "stdout": result,
            "stderr": "",
            "returncode": 0
        }
    }
```

**Plugin Features:**
- Automatic discovery of `.py` files in `~/.pp/plugins/`
- Each plugin should define a `register()` function that returns tool definitions
- Tools are merged into the main tools dictionary automatically
- Error handling prevents broken plugins from affecting PP functionality

### 💬 Interactive Shell Commands

#### Configuration Management
```bash
./pp help              # Show this help menu and exit

./pp config            # Manage configuration settings
                       Subcommands: show, get <KEY>, set <KEY> <VALUE>, remove <KEY>
                       Use dot-notation for nested values (e.g., apis.local.model)
                       Add -g flag to operate on global config (~/.pp/)

./pp config show       # Display full configuration as formatted JSON
./pp config get <KEY>  # Retrieve a specific value using dot-notation
./pp config set <KEY> <VALUE>   # Set a configuration value with dot-notation support
./pp config remove <KEY>    # Delete a configuration value at the given path
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

./pp aliases list     # List all defined aliases with their target messages
./pp aliases show <NAME>   # Show details for a specific alias
./pp aliases set <ALIAS_NAME> <MESSAGE_ID>   # Create or update an alias
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
1. `./.pp/config` - Local session configuration
2. `~/.pp/config` - Global user configuration

### Available Config Keys
- `url` - LLM API endpoint (default: http://localhost:1234)
- `model` - AI model name to use
- `timeout` - Request timeout in seconds (default: 100)
- `editor` - Default editor command
- `session` - Session file path
- `api` - API provider configuration
- `apis.<name>` - Nested API settings using dot notation

### Dot Notation Configuration
PP supports nested configuration keys:
```bash
# Set a deeply nested value
./pp set apis.local.model gpt-4o

# Get the value back
./pp get apis.local.model
```

## Architecture Overview

```
┌─────────────────────────────────────────────┐
│           PP CLI Agent                       │
├─────────────────────────────────────────────┤
│  ┌───────────────────┐                       │
│  │   Shell      │◄──────────────────────────► Commands
│  │   Interface     │                        │
│  └───────────────────┘                       │
│         │                                    │
│  ┌───────────────────────┐                   │
│  │     Session Manager    │                   │
│  │  (Persistent conversation)      │
│  └───────────────────────┘                   │
│         │                                    │
│  ┌───────────────────────┐                   │
│  │      Tool Registry     │                   │
│  │   bash | read | write | edit    │
│  └───────────────────────┘                   │
│         │                                    │
│  ┌───────────────────────┐                   │
│  │     LLM API Client     │                   │
│  │   (Configurable endpoint)      │
│  └───────────────────────┘                   │
│         │                                    │
│  ┌───────────────────────┐                   │
│  │     Plugin System      │                   │
│  │   ~/.pp/plugins/*.py       │
│  └───────────────────────┘                   │
└─────────────────────────────────────────────┘
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

## Session Management

PP maintains conversation history in session files:
- Each session has a unique ID stored in `.pp/sessions/<session_id>/`
- Messages are stored as JSONL files for efficient streaming
- Aliases allow quick reference to important messages

## Alias System

Create shortcuts to frequently used prompts:
```bash
# Set an alias
./pp aliases set greeting "<message_id>"

# List all aliases
./pp aliases list
```

## License

MIT License - Feel free to use, modify, and distribute.
