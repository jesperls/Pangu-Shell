#!/usr/bin/env python3

import fcntl
import html
import json
import math
import os
from pathlib import Path
import re
import sys
import tempfile


EDITABLE = {"boolean", "slider", "combolist", "color", "textinput", "file", "directory"}


def config_home():
    return Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")


def read_object(path, optional=False):
    try:
        value = json.loads(path.read_text())
    except FileNotFoundError:
        if optional:
            return {}
        raise
    if not isinstance(value, dict):
        raise ValueError(f"Expected an object in {path}")
    return value


def overrides(directory):
    home = config_home()
    try:
        legacy = read_object(home / "Linux Wallpaper Engine/wallpaper-overrides.json", True)
        inherited = legacy.get("overrides", {}).get(directory, {}).get("customProperties", {})
    except (OSError, ValueError, AttributeError):
        inherited = {}
    saved = read_object(home / "pangu/wallpaper-engine.json", True)
    own = saved.get(directory, {})
    if not isinstance(own, dict):
        raise ValueError("Invalid saved wallpaper properties")
    return {**(inherited if isinstance(inherited, dict) else {}), **own}


def label(value):
    return html.unescape(re.sub(r"<[^>]*>", " ", str(value))).strip()


def number(value):
    result = float(value)
    if not math.isfinite(result):
        raise ValueError("Expected a finite number")
    return result


def normalize(prop, value):
    kind = prop["type"]
    if kind == "boolean":
        if value in (True, 1, "1", "true"):
            return "1"
        if value in (False, 0, "0", "false"):
            return "0"
        raise ValueError("Expected a switch value")
    if kind == "slider":
        value = number(value)
        if not prop["min"] <= value <= prop["max"]:
            raise ValueError("Value is outside the slider range")
        return format(value, ".12g")
    if kind == "combolist":
        value = str(value)
        if value not in [option["value"] for option in prop["options"]]:
            raise ValueError("Expected one of the available choices")
        return value
    if kind == "color":
        channels = [number(channel) for channel in str(value).split()]
        if len(channels) != 3 or any(channel < 0 or channel > 1 for channel in channels):
            raise ValueError("Expected three RGB channels between 0 and 1")
        return " ".join(format(channel, ".12g") for channel in channels)
    if kind in {"textinput", "file", "directory"}:
        if not isinstance(value, str) or "\0" in value:
            raise ValueError("Expected text without null characters")
        return value
    raise ValueError("Unsupported property type")


def properties(directory):
    project = read_object(Path(directory) / "project.json")
    general = project.get("general", {})
    raw = general.get("properties", project.get("properties", {})) if isinstance(general, dict) else {}
    if not isinstance(raw, dict):
        raise ValueError("Invalid wallpaper property definitions")
    raw = dict(raw)
    if "schemecolor" not in raw and isinstance(project.get("schemecolor"), str):
        raw["schemecolor"] = {"type": "color", "value": project["schemecolor"], "text": "Theme color", "order": -1}
    result = []
    for key, definition in raw.items():
        if not isinstance(definition, dict):
            continue
        prop = {"name": key, "label": label(definition.get("text", key)) or key,
                "type": {"bool": "boolean", "combo": "combolist"}.get(definition.get("type"), definition.get("type", "unknown")),
                "order": 0, "supported": False}
        if prop["label"].startswith("ui_"):
            prop["label"] = "Theme color" if key == "schemecolor" else key.replace("_", " ")
        try:
            prop["order"] = number(definition.get("order", 0))
            if prop["type"] == "slider":
                prop.update(min=number(definition.get("min", 0)), max=number(definition.get("max", 1)), step=number(definition.get("step", 0.01)))
                if prop["max"] <= prop["min"] or prop["step"] <= 0:
                    raise ValueError("Invalid slider range")
            elif prop["type"] == "combolist":
                options = definition.get("options", [])
                if isinstance(options, dict):
                    options = [{"label": k, "value": v} for k, v in options.items()]
                prop["options"] = [{"label": label(option.get("label", option.get("text", option["value"]))), "value": str(option["value"])} for option in options]
            if prop["type"] in EDITABLE:
                prop["default"] = normalize(prop, definition.get("value"))
                prop["supported"] = True
        except (ValueError, TypeError, KeyError, AttributeError, OverflowError):
            pass
        result.append(prop)
    return sorted(result, key=lambda prop: prop["order"])


def load(directory):
    props = properties(directory)
    saved = overrides(directory)
    values = {}
    for prop in props:
        if not prop["supported"]:
            continue
        try:
            values[prop["name"]] = normalize(prop, saved.get(prop["name"], prop["default"]))
        except (ValueError, TypeError, OverflowError):
            values[prop["name"]] = prop["default"]
    return {"properties": props, "values": values}


def save(directory, values):
    if not isinstance(values, dict):
        raise ValueError("Expected property values")
    props = {prop["name"]: prop for prop in properties(directory) if prop["supported"]}
    normalized = {}
    for key, value in values.items():
        if key not in props:
            raise ValueError(f"Unknown or unsupported property: {key}")
        normalized[key] = normalize(props[key], value)
    path = config_home() / "pangu/wallpaper-engine.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.with_suffix(".lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        data = read_object(path, True)
        data[directory] = {**data.get(directory, {}), **normalized}
        descriptor, temporary = tempfile.mkstemp(prefix=path.name + ".", dir=path.parent)
        try:
            with os.fdopen(descriptor, "w") as stream:
                json.dump(data, stream, indent=2, allow_nan=False)
                stream.write("\n")
            os.replace(temporary, path)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)


def arguments(directory):
    for key, value in overrides(directory).items():
        if isinstance(value, bool):
            value = "1" if value else "0"
        if isinstance(value, (str, int, float)) and "\0" not in key and "=" not in key and "\0" not in str(value):
            sys.stdout.buffer.write(f"{key}={value}".encode() + b"\0")


def main():
    try:
        command, directory = sys.argv[1:3]
        if command == "load":
            print(json.dumps(load(directory), allow_nan=False))
        elif command == "save":
            save(directory, json.loads(sys.argv[3]))
        elif command == "arguments":
            arguments(directory)
        else:
            raise ValueError("Unknown command")
    except (OSError, ValueError, TypeError, KeyError) as error:
        print(f"Could not read or save wallpaper settings: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
