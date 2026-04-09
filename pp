#!/usr/bin/env python3

import re
from urllib.request import Request, urlopen
from urllib.error import HTTPError
from pathlib import Path
import json
import os.path
import uuid
import sys
import subprocess
import tempfile
import threading

DEFAULT_TIMEOUT = 100
DEFAULT_URL = "http://localhost:1234"

SEPARATOR_MESSAGE = "".join(["=" for _ in range(80)]) + "\nEverything above this will be removed\n" + "".join(["=" for _ in range(80)])

def run_spinner(action, should_stop):
    while not should_stop.is_set():
        sys.stdout.write(f'\r  {action}... ')  # Initial message
        sys.stdout.flush()
        for char in SPINNER_CHARS:
            sys.stdout.write(f'\r{char} {action}... ')
            sys.stdout.flush()
            threading.Event().wait(0.1)  # Small delay between frames
    sys.stdout.write('\r                        ')  # Clear the last line
    sys.stdout.flush()

def bash(config, session, args):
    file = f".pp_bash_{uuid.uuid4().hex}.sh"
    with open(file, "w", encoding="utf-8") as handle:
        handle.write("# This code will execute when closed.\n")
        handle.write("# Delete all content to cancel.\n\n")
        handle.write(args["command"])
    
    editor_cmd = config.get("editor", os.environ.get('EDITOR', 'nano'))
    subprocess.call(editor_cmd.split() + [file])
    if len(open(file, encoding="utf-8").read().strip()) == 0:
        print("user canceled command", file=sys.stderr)

    should_stop = threading.Event()
    spinner_thread = threading.Thread(target=run_spinner, args=("Bashing", should_stop))
    spinner_thread.start()

    result = subprocess.run(
        ["bash", file],
        shell=False,
        capture_output=True,
        text=True,
        timeout=int(config.get("timeout", DEFAULT_TIMEOUT))
    )

    should_stop.set()
    spinner_thread.join()

    return {
        'stdout': result.stdout,
        'stderr': result.stderr,
        'returncode': result.returncode
    }

def tool_read(config, session, args):
    cmd = ["tail", "-n", f"+{args.get('offset', 0)}", args["path"]]
    if "limit" in args:
        cmd.extend(["|", "head", "-n", f"{args.get('limit', 0)}"])
    result = subprocess.run(
        cmd,
        shell=False,
        capture_output=True,
        text=True,
        timeout=int(config.get("timeout", DEFAULT_TIMEOUT))
    )
    
    return {
        'stdout': result.stdout,
        'stderr': result.stderr,
        'returncode': result.returncode
    }

def tool_write(config, session, args):
    path = args["path"]
    content = args["content"]
    
    directory = os.path.dirname(path)
    if directory and not os.path.exists(directory):
        try:
            os.makedirs(directory, exist_ok=True)
        except OSError as e:
            return {
                'stdout': f"Error creating directory: {e}",
                'stderr': str(e),
                'returncode': 1
            }
    
    try:
        with open(path, "w", encoding="utf-8") as f:
            f.write(content)
        return {
            'stdout': f"Successfully wrote {len(content)} bytes to {path}",
            'stderr': '',
            'returncode': 0
        }
    except IOError as e:
        return {
            'stdout': f"Error writing file: {e}",
            'stderr': str(e),
            'returncode': 1
        }

def tool_context(config, session, args):
    prompts = args.get('prompts', [])
    
    context_data = []
    for i, prompt in enumerate(prompts):
        print(prompt)
        item_data = {
            'index': i,
            'prompt': prompt,
            'result': input(" : "),
        }
        context_data.append(item_data)
    
    return {
        'stdout': json.dumps(context_data, indent=2),
        'stderr': '',
        'returncode': 0
    }

def tool_edit(config, session, args):
    file = open(args["path"], encoding="utf-8").read()
    modified = file[:]
    for edit in args.get("edits", []):
        if ("oldText" not in edit or "newText" not in edit):
            print("Incorrect parameters.")
            print(json.dumps(edit, indent=2))
            continue
        modified = modified.replace(edit.get("oldText", ""), edit.get("newText", ""))
    open(args["path"], "w", encoding="utf-8").write(modified)
    return {
        'stdout': '',
        'stderr': '',
        'returncode': 0
    }

tools = {
    "bash": {
        "function": bash,
        "definition": {
            "type": "function",
            "function": {
                "name": "bash",
                "description": "Execute a bash command in the current working directory. Returns stdout and stderr. Output is truncated to last ${DEFAULT_MAX_LINES} lines or ${DEFAULT_MAX_BYTES / 1024}KB (whichever is hit first). If truncated, full output is saved to a temp file.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "command": {
                            "type": "string",
                            "description": "Bash command to execute"
                        }
                    },
                    "required": ["command"]
                }
            }
        }
    },
    "read": {
        "function": tool_read,
        "definition": {
            "type": "function",
            "function": {
                "name": "read",
                "description": "Read the contents of a file. Supports text files and images (jpg, png, gif, webp). Images are sent as attachments. For text files, output is truncated to ${DEFAULT_MAX_LINES} lines or ${DEFAULT_MAX_BYTES / 1024}KB (whichever is hit first). Use offset/limit for large files. When you need the full file, continue with offset until complete.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "path": {
                            "type": "string",
                            "description": "Path to the file to read (relative or absolute)"
                        },
                        "offset": {
                            "type": "integer",
                            "description": "Line number to start reading from (1-indexed)"
                        },
                        "limit": {
                            "type": "integer",
                            "description": "Maximum number of lines to read"
                        },
                    },
                    "required": ["path"]
                }
            }
        }
    },
    "write": {
        "function": tool_write,
        "definition": {
            "type": "function",
            "function": {
                "name": "write",
                "description": "Write content to a file. Creates the file if it doesn't exist, overwrites if it does. Automatically creates parent directories.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "path": {
                            "type": "string",
                            "description": "Path to the file to write (relative or absolute)"
                        },
                        "content": {
                            "type": "string",
                            "description": "Content to write to the file"
                        },
                    },
                    "required": ["path", "content"]
                }
            }
        }
    },
    "edit": {
        "function": tool_edit,
        "definition": {
            "type": "function",
            "function": {
                "name": "edit",
                "description": "Edit a single file using exact text replacement. Every edits[].oldText must match a unique, non-overlapping region of the original file. If two changes affect the same block or nearby lines, merge them into one edit instead of emitting overlapping edits. Do not include large unchanged regions just to connect distant changes.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "path": {
                            "type": "string",
                            "description": "Path to the file to write (relative or absolute)"
                        },
                        "edits": {
                            "type": "array",
                            "items": {
                                "type": "object",
                                "properties": {
                                    "oldText": {
                                        "type": "string",
                                        "description": "The old text to match and replace"
                                    },
                                    "newText": {
                                        "type": "string",
                                        "description": "The new text to replace the matched text with"
                                    }
                                },
                                "required": [
                                    "oldText",
                                    "newText"
                                ]
                            }
                        }
                    },
                    "required": ["path", "edits"]
                }
            }
        }
    },
    "context": {
        "function": tool_context,
        "definition": {
            "type": "function",
            "function": {
                "name": "context",
                "description": "Collects user responses to a series of prompts. Prints each prompt, reads user input from stdin for each one, returns responses as indexed JSON array.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "prompts": {
                            "type": "array",
                            "items": {"type": "string"},
                            "description": "List of prompts to display and collect responses for"
                        },
                        "source": {
                            "type": "string",
                            "description": "Source identifier for this context (e.g., 'user', 'system', 'file')"
                        },
                        "metadata": {
                            "type": "object",
                            "description": "Additional metadata about this context, can include per-item data in a dict"
                        }
                    },
                    "required": ["prompts"]
                }
            }
        }
    },
}

# Spinner animation characters
SPINNER_CHARS = '|/-\\'  # Unicode spinner frames

def fetch(url, data=None, timeout=DEFAULT_TIMEOUT, method="POST"):
    request = Request(
        url,
        data=data,
        headers={
            'Content-Type': 'application/json',
            'Accept': 'application/json'
        },
        method=method
    )
    
    should_stop = threading.Event()
    spinner_thread = threading.Thread(target=run_spinner, args=("Fetching", should_stop))
    spinner_thread.start()
    
    try:
        with urlopen(request, timeout=timeout) as response:
            return json.loads(response.read().decode('utf-8'))
    except HTTPError as e:
        print(e.status, file=sys.stderr)
        print(e.fp.read(), file=sys.stderr)
        raise e
    finally:
        should_stop.set()
        spinner_thread.join()

def load_session(file):
    messages = []
    if os.path.isfile(file):
        with open(file, encoding="utf-8") as handle:
            for line in handle:
                messages.append(json.loads(line))
    session = {}
    session["lut"] = {}
    session["order"] = []
    for message in messages:
        session["lut"][message["id"]] = message
        session["order"].append(message["id"])
    if len(messages) > 0:
        session["head"] = messages[-1]["id"]
    return session

def append_session(config, session, msg):
    msg["parent"] = session.get("head")
    msg["id"] = uuid.uuid4().hex
    session["head"] = msg["id"]
    session["lut"][msg["id"]] = msg
    session["order"].append(msg["id"])
    with open(config["session"], "a", encoding="utf-8") as f:
        json.dump(msg, f)
        f.write("\n")

def new_session(config):
    config["session"] = ".pp_session_" + uuid.uuid4().hex
    dump_config(config)

def messages_from_session(session):
    messages = []
    parent = session.get("head")
    while parent:
        m = session["lut"][parent]
        messages.append(m)
        parent = m.get("parent")
    return list(reversed(messages))

def load_config():
    config = {}
    if not os.path.isfile(Path.home() / ".pp_config"):
        json.dump({}, open(Path.home() / ".pp_config", "w", encoding="utf-8"))
    config.update(json.load(open(Path.home() / ".pp_config", encoding="utf-8")))
    if not os.path.isfile(".pp_config"):
        json.dump({}, open(".pp_config", "w", encoding="utf-8"))
    config.update(json.load(open(".pp_config", encoding="utf-8")))
    if "session" not in config:
        new_session(config)
    return config

def dump_config(config):
    json.dump(config, open(".pp_config", "w", encoding="utf-8"))
    return []

def stage_one_help(config, args):
    print("""
================================================================================
                                PP HELP MENU
================================================================================
Configuration
--------------------------------------------------------------------------------

  help              Show this help menu and exit

  set <KEY> <VALUE> Set a configuration value (session or global)

  get <KEY>         Get a configuration value

Interaction & Tools
--------------------------------------------------------------------------------

  message | m       Send a new message to the LLM service
                    Reads input from stdin, then sends it with context

  send              Continue conversation using previous messages as context
                    Sends all accumulated messages back to the API

  tools             Process tool calls returned by the LLM
                    Executes any requested tools (bash, read, write, edit)

  echo <INDEX>      Display a message from the session history
                    Can specify position with argument

  new              Start a fresh session (clears current conversation)

  models           List available AI models from the configured server

  tree             Display the session as a hierarchical tree structure

Options for 'message' command:
--------------------------------------------------------------------------------

  -m <TEXT>         Use commandline mode with specified text
  --                Read message content from stdin
  -b <ID|ROOT>      Set base message ID (use ROOT to start fresh)
  -r                Start a fresh conversation. Like `-b ROOT`

Options for 'send' command:
--------------------------------------------------------------------------------

  -b <ID>           Set base message ID

--------------------------------------------------------------------------------
""")
    return []

def stage_one_set(config, args):
    if len(args) < 2:
        print("expected key value arguments.", file=sys.stderr)
        return [[stage_one_help]]
    if args[0].startswith("global."):
        key = args[0][7:]
        global_config = json.load(open(Path.home() / ".pp_config", encoding="utf-8"))
        global_config[key] = args[1]
        json.dump(global_config, open(Path.home() / ".pp_config", "w", encoding="utf-8"))
        return []
    config[args[0]] = args[1]
    dump_config(config)
    return []

def stage_one_get(config, args):
    if len(args) < 1:
        print("expected key arguments.", file=sys.stderr)
        return [[stage_one_help]]
    if args[0].startswith("global."):
        key = args[0][7:]
        global_config = json.load(open(Path.home() / ".pp_config", encoding="utf-8"))
        print(global_config.get(args[0], ""))
        return []
    print(config.get(args[0], ""))
    return []

def stage_two_message(config, session, args):
    role = "user"
    processed = 0

    method = "editor"
    while len(args) > processed:
        if len(args) > processed + 1 and args[processed] == "-m":
            method = "commandline"
            processed += 1
            contents = ' '.join(args[processed])
            processed += 1
            print(f"Using -m flag with {len(contents)} characters", file=sys.stderr)
        elif len(args) > processed + 1 and args[processed] == '--':
            method = "stdin"
            processed += 1
            # Join all subsequent arguments as the message content
            contents = sys.stdin.read()
            print(f"Using stdin with {len(contents)} characters", file=sys.stderr)
        elif len(args) > processed + 1 and args[processed] == '-b':
            processed += 1
            head = args[processed]
            if head == "ROOT":
                head = None
            elif head not in session["lut"]:
                print(f"message id {repr(head)} not found.", file=sys.stderr)
            session["head"] = head
            processed += 1
        elif len(args) > processed and args[processed] == '-r':
            processed += 1
            session["head"] = None
        else:
            print(f"unknown arguments {repr(args[processed:])}", file=sys.stderr)
    
    if method == "editor":
        contents = get_editor_contents(config, session)
    
    # Append the edited content to session
    append_session(config, session, {"role": role, "content": contents})
    
    return [[stage_two_echo_message], [stage_two_send]]

def get_editor_contents(config, session):
    # Step 1: Determine the Editor Command (like $EDITOR in git)
    editor_cmd = config.get("editor", os.environ.get('EDITOR', 'nano'))
    
    print(f"Using editor: {editor_cmd}", file=sys.stderr)
    
    # Step 2: Create a temporary file with the previous message content
    temp_fd, temp_path = tempfile.mkstemp(suffix='.pp_message')
    try:
        os.close(temp_fd)  # Close fd immediately
        
        # Get the current message content (from session if exists, else empty)
        current_msg_id = session.get("head")
        
        # Write previous content to temp file (or empty for new messages)
        with open(temp_path, 'w', encoding="utf-8") as f:
            if current_msg_id and current_msg_id in session["lut"]:
                echo_message(session["lut"][current_msg_id], f)
            print("", file=f)
            print(SEPARATOR_MESSAGE, file=f)
            print("", file=f)
        
        print(f"Created temporary file: {temp_path}", file=sys.stderr)
        
        # Step 3: Execute the Editor Command on the temp file
        result = subprocess.call(editor_cmd.split() + [temp_path])
        
        if result != 0:
            print(f"Editor exited with code {result.returncode}", file=sys.stderr)
            print(result.stderr, file=sys.stderr)
            return ""
        
        # Step 4: Read the edited content from temp file instead of stdin
        new_content = open(temp_path, encoding="utf-8").read()

        parts = new_content.split(SEPARATOR_MESSAGE)
        if (len(parts) > 1):
            new_content = parts[-1]
        
        print(f"Editor produced {len(new_content)} characters", file=sys.stderr)

        return new_content
        
    finally:
        # Clean up temporary file
        try:
            os.unlink(temp_path)
        except OSError:
            pass

def stage_two_send(config, session, args):
    processed = 0
    while len(args) > processed:
        if len(args) > processed + 1 and args[processed] == '-b':
            processed += 1
            head = args[processed]
            if head not in session["lut"]:
                print(f"message id {repr(head)} not found.", file=sys.stderr)
            session["head"] = head
            processed += 1

    data = {
        "messages": messages_from_session(session),
        "model": config.get("model", ""),
        "tools": [tools[t]["definition"] for t in tools],
    }

    result = fetch(
        f"{config.get('url', DEFAULT_URL)}/v1/chat/completions",
        data=json.dumps(data).encode('utf-8'),
        timeout=int(config.get("timeout", 100)))

    message = result.get("choices", [{}])[0].get("message")

    if (not message):
        print("no message returned from service.", file=sys.stderr)
        print(json.dumps(result, indent=2), file=sys.stderr)
        return []

    append_session(config, session, message)
    return [[stage_two_echo_message], [stage_two_process_tool_calls]]

def stage_two_process_tool_calls(config, session, args):
    tool_calls = session["lut"].get(session.get("head"), {}).get("tool_calls", [])
    for tool_call in tool_calls:
        id = tool_call.get("id")
        tool = tools.get(tool_call.get("function", {}).get("name"))
        args_data = json.loads(tool_call.get("function", {}).get("arguments", "{}"))
        if id is None:
            print("tool id not found.", file=sys.stderr)
            print(json.dumps(tool_call, indent=2), file=sys.stderr)
            return []
        if tool is None:
            print("tool not found.", file=sys.stderr)
            print(json.dumps(tool_call, indent=2), file=sys.stderr)
            return []
        content = tool["function"](config, session, args_data)
        if not content:
            print("tool did not return any content.", file=sys.stderr)
            print(json.dumps(tool_call, indent=2), file=sys.stderr)
            return []
        message = {
            "role": "tool",
            "tool_call_id": id,
            "content": json.dumps(content)
        }
        append_session(config, session, message)
    if len(args)>0 and args[0]==False:
        return []
    if len(tool_calls) > 0:
        return [[stage_two_send]]
    else:
        return []

def stage_two_echo_message(config, session, args):
    message = session["lut"].get(session.get("head"))
    pos = 0
    if len(args)>0:
        pos = int(args[0])
    while pos > 0 and message is not None:
        pos -= 1
        message = session["lut"].get(message.get("parent"))
        
    if message is None:
        print("no messages found.", file=sys.stderr)
        return []
    echo_message(message)
    return []

def stage_two_new_session(config, session, args):
    """
    Start a new session.
    
    This command creates a fresh session and returns to the help menu.
    """
    print("Starting new session...")
    new_session(config)
    return []

def stage_two_pop(config, session, args):
    """
    Pop the second-to-last message from the session.
    
    This command retrieves the second-to-last message in the session,
    assigns it a new unique ID, and pushes it back to the session.
    The original last message becomes the parent of the popped message.
    """
    # Get all messages in order
    messages = []
    parent = session.get("head")
    while parent:
        m = session["lut"].get(parent)
        if m:
            messages.append(m)
        parent = m.get("parent")
    
    popped_message = {}
    # Get the second-to-last message (index -2)
    if len(messages) > 1:
        popped_message = messages[-2]
    
    # Create a new ID for the popped message
    new_id = uuid.uuid4().hex
    
    # Update the popped message with new ID and parent pointer to last message
    popped_message["id"] = new_id
    del(popped_message["parent"])
    
    # Append the modified message back to session
    append_session(config, session, popped_message)
    
    return []

def stage_two_list_models(config, session, args):
    """
    List models available from the configured server.
    
    Makes a GET request to /v1/models endpoint and prints the JSON response.
    """
    
    result = fetch(
        f"{config.get('url', DEFAULT_URL)}/v1/models",
        timeout=int(config.get("timeout", DEFAULT_TIMEOUT)),
        method="GET")
    
    for model in result.get("data", []):
        if "id" not in model:
            continue
        print(model["id"])
    return []


def stage_two_tree(config, session, args):
    """
    Display the session as a tree structure.
    
    Shows all messages in a hierarchical format with proper indentation
    and branching characters (├─, └─, │).
    """
    # Build children map for each node
    children = {}
    for msg_id in session["order"]:
        msg = session["lut"][msg_id]
        parent_id = msg.get("parent")
        if parent_id is None:
            continue
        if parent_id not in children:
            children[parent_id] = []
        children[parent_id].append(msg)
    
    def print_tree(node, prefix="", is_last=True):
        """
        Recursively print the tree structure.
        
        Args:
            node: The message object to print
            prefix: Indentation string for this level
            is_last: Whether this is the last child of its parent
        """
        # Determine connector character
        if is_last:
            connector = "└─"
            next_prefix = prefix + "    "
        else:
            connector = "├─"
            next_prefix = prefix + "│   "
        
        # Get role and content for display
        msg = node if isinstance(node, dict) else session["lut"].get(node)
        if not msg:
            return
        
        role = msg.get("role", "unknown")

        if role != "user":
            next_prefix = prefix

        # Clean up whitespace: replace multiple newlines with single, strip edges
        content = msg.get("content", "")
        content = re.sub(r'\n', ' ', content)
        content = re.sub(r'\t', ' ', content)
        content = re.sub(r' {2,}', ' ', content)
        content = content.strip()
        if len(content) > 50:
            content = content[:50] + "..."
        
        # Print this node
        print(f"{prefix}{connector} {role} ({msg['id']}):")
        if len(content) > 0:
            print(f"{prefix}  {content}")
        for tool_call in msg.get("tool_calls", []):
            tool_call = tool_call.get('function', {})
            tool_summary = f"{tool_call['name']}: {tool_call['arguments']}"
            if len(tool_summary) > 50:
                tool_summary = tool_summary[:50] + "..."
            print(f"{prefix}  [ {tool_summary} ]")

        # Get children of this node
        child_list = children.get(node["id"], [])
        if not child_list:
            return
        
        # Print each child recursively
        for i, child in enumerate(child_list):
            is_child_last = (i == len(child_list) - 1)
            print_tree(child, next_prefix, is_child_last)
    
    # Find and print all root nodes
    roots = [msg_id for msg_id in session["order"] if session["lut"][msg_id].get("parent") is None]
    
    if not roots:
        print("No root nodes found in session.")
        return []
    
    # Print each tree rooted at a root node
    for i, root_id in enumerate(roots):
        is_root_last = (i == len(roots) - 1)
        print_tree(session["lut"][root_id], prefix="", is_last=is_root_last)
    
    return []


# Color codes for ANSI terminal output
COLOR_RESET = '\033[0m'
COLOR_USER = '\033[1;34m'    # Blue for user messages
COLOR_ASSISTANT = '\033[1;32m'  # Green for assistant
COLOR_SYSTEM = '\033[1;33m'     # Yellow for system
COLOR_TOOL = '\033[1;35m'      # Magenta for tool output
COLOR_HEADER = '\033[1;37m'    # White for headers
COLOR_FOOTER = '\033[0;90m'    # Dim gray for footers
def echo_message(message, file=sys.stdout):
    role = message.get('role', 'Unknown')
    content = message.get('content', '')
    reasoning_content = message.get('reasoning_content', '')
    tool_calls = message.get('tool_calls', [])
    
    # Determine color based on role
    if role == 'user':
        prefix_color = COLOR_USER
    elif role == 'assistant':
        prefix_color = COLOR_ASSISTANT
    elif role == 'system':
        prefix_color = COLOR_SYSTEM
    else:
        prefix_color = COLOR_RESET
    
    # Print message header with separator
    print(f"\n{'='*60}", file=file)
    print(f"{COLOR_HEADER}  MESSAGE: {role.upper()} {'(' + str(len(content)) + ' chars)'}{COLOR_RESET}", file=file)
    print(f"{'='*60}", file=file)
    
    # Print reasoning if present
    if reasoning_content and len(reasoning_content.strip()) > 0:
        print(f"\n{COLOR_TOOL}## Reasoning{COLOR_RESET}", file=file)
        print(reasoning_content, file=file)

    # Print content with appropriate formatting
    if content:
        print(f"\n{prefix_color}## {role.title()} Response{COLOR_RESET}\n", file=file)
        print(content, file=file)
    
    # Print tool calls if present
    if tool_calls and len(tool_calls) > 0:
        print(f"\n{COLOR_TOOL}## Tool Calls{COLOR_RESET}", file=file)
        for i, tc in enumerate(tool_calls):
            call_id = tc.get('id', f'call_{i}')
            func_name = tc.get('function', {}).get('name', 'unknown')
            args = tc.get('function', {}).get('arguments', '{}')
            print(f"\n  * {func_name} [{call_id}]", file=file)
            print("    ```", file=file)
            print("    ".join(args.splitlines()), file=file)
            print("    ```", file=file)
    
    # Print footer
    print(f"{'-'*60}", file=file)

stage_one = {
    "help": stage_one_help,
    stage_one_help: stage_one_help,
    "set": stage_one_set,
    "get": stage_one_get,
}
stage_two = {
    "message": stage_two_message,
    "m": stage_two_message,
    "send": stage_two_send,
    stage_two_send: stage_two_send,
    "tools": stage_two_process_tool_calls,
    stage_two_process_tool_calls: stage_two_process_tool_calls,
    "echo": stage_two_echo_message,
    stage_two_echo_message: stage_two_echo_message,
    "new": stage_two_new_session,
    "pop": stage_two_pop,
    "models": stage_two_list_models,
    "tree": stage_two_tree,
}

def main():
    commands = []
    if len(sys.argv) > 1:
        commands.append(sys.argv[1:])
    else:
        commands.append(["help"])
    while len(commands) > 0:
        args = commands.pop(0)
        config = load_config()
        if args[0] in stage_one:
            commands.extend(stage_one[args[0]](config, args[1:]))
            continue
        session = load_session(config["session"])
        if args[0] in stage_two:
            commands.extend(stage_two[args[0]](config, session, args[1:]))
            continue
        print(f"unknown command {args[0]}.", file=sys.stderr)
        break

if __name__ == "__main__":
    main()
