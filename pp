#!/bin/env python3

from urllib.request import Request, urlopen
import json
import os.path
import uuid
import sys

def fetch(url, data, timeout):
    request = Request(
        url,
        data=json.dumps(data).encode('utf-8'),
        headers={
            'Content-Type': 'application/json',
            'Accept': 'application/json'
        },
        method='POST'
    )

    with urlopen(request, timeout=timeout) as response:
        result = json.loads(response.read().decode('utf-8'))
        return result

def load_session(file):
    messages = []
    if os.path.isfile(file):
        with open(file) as handle:
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
    msg["id"] = uuid.uuid4().hex
    msg["parent"] = session.get("head")
    session["head"] = msg["id"]
    session["lut"][msg["id"]] = msg
    session["order"].append(msg["id"])
    with open(config["session"], "a") as f:
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
    return messages

def load_config():
    if not os.path.isfile(".pp_config"):
        json.dump({}, open(".pp_config", "w"))
    config = json.load(open(".pp_config"))
    if "session" not in config:
        new_session(config)
    return config

def dump_config(config):
    json.dump(config, open(".pp_config", "w"))

def stage_one_set_url(config, args):
    config["url"] = args[0]
    dump_config(config)
    return True

def stage_one_set_model(config, args):
    config["model"] = args[0]
    dump_config(config)
    return True

stage_one = {
    "url": stage_one_set_url,
    "model": stage_one_set_model,
}
stage_two = {}

def main():
    config = load_config()
    if len(sys.argv) > 1 and sys.argv[1] in stage_one:
        if stage_one[sys.argv[1]](config, sys.argv[2:]):
            sys.exit(0)
    session = load_session(config["session"])
    if len(sys.argv) > 1 and sys.argv[1] in stage_two:
        if stage_two[sys.argv[1]](config, session, sys.argv[2:]):
            sys.exit(0)

    if len(sys.argv) == 1:
        msg = sys.stdin.read()
        append_session(config, session, {"role": "user", "content": msg})
    
    data = {
        "messages": messages_from_session(session),
        "model": config.get("model", "")
    }

    result = fetch(
        config.get("url", "http://localhost:1234/v1/chat/completions"),
        data,
        config.get("timeout", 100))
    print(result)

if __name__ == "__main__":
    main()
