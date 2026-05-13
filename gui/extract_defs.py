#!/usr/bin/env python3
"""Extract function definitions from HRB_defaultConfig.m and function arguments blocks."""

import re
import json
import os
from pathlib import Path

TOOLBOX_ROOT = Path(__file__).resolve().parent.parent
GUI_DIR = TOOLBOX_ROOT / "gui"
FUNCTIONS_DIR = TOOLBOX_ROOT / "functions"

# Map module name → folder number
MODULE_FOLDERS = {
    "preprocessing": "1_preprocessing",
    "headModel": "2_headModel",
    "sourceEstimation": "3_sourceEstimation",
    "connectivity": "4_connectivity",
    "network": "5_network",
}

# Mapping from config key → HRB function file name
CONFIG_TO_FUNC = {
    "preprocessing": {
        "chanedit": "HRB_chanedit",
        "resample": "HRB_resample",
        "filter": "HRB_filter",
        "removeChannels": "HRB_removeChannels",
        "selectChannels": "HRB_selectChannels",
        "selectTime": "HRB_selectTime",
        "cleanData": "HRB_cleanData",
        "runica": "HRB_runica",
        "iclabel": "HRB_iclabel",
        "icflag": "HRB_icflag",
        "subcomp": "HRB_subcomp",
        "epoch": "HRB_epoch",
        "rejepochs": "HRB_rejepochs",
        "import": "HRB_importData",
    },
    "headModel": {},
    "sourceEstimation": {},
    "connectivity": {},
    "network": {},
}

BOILERPLATE = {"EEGLAB", "Save", "SaveName", "OutputFolder",
               "LogEnabled", "LogLevel", "LogToFile", "LogFileDir", "LogFileName",
               "SaveBefore", "SaveNameBefore", "SaveExcludedChannels"}


def parse_default_config(text):
    """Parse HRB_defaultConfig.m to extract module → func → param → default."""
    result = {}
    current_module = None
    current_func = None

    # Detect module header: e.g. "%% PREPROCESSING" or "%% HEAD MODEL"
    for line in text.splitlines():
        stripped = line.strip()

        # Detect module sections
        m = re.match(r'%%\s*(PREPROCESSING|HEAD\s*MODEL|SOURCE\s*ESTIMATION|CONNECTIVITY|NETWORK\s*ANALYSIS)', stripped, re.IGNORECASE)
        if m:
            raw = m.group(1).upper()
            if "PREPROC" in raw:
                current_module = "preprocessing"
            elif "HEAD" in raw:
                current_module = "headModel"
            elif "SOURCE" in raw:
                current_module = "sourceEstimation"
            elif "CONNECT" in raw:
                current_module = "connectivity"
            elif "NETWORK" in raw:
                current_module = "network"
            current_func = None
            if current_module not in result:
                result[current_module] = {}
            continue

        if current_module is None:
            continue

        # Detect function key: e.g. "preproc.resample.Frequency = 250;"
        m = re.match(r'(?:\w+)\.(\w+)\.(\w+)\s*=\s*(.+?);?\s*$', stripped)
        if m:
            func_key = m.group(1)
            param_name = m.group(2)
            raw_val = m.group(3).strip()

            if func_key == "logging":
                continue  # skip logging config

            if current_module not in result:
                result[current_module] = {}
            if func_key not in result[current_module]:
                result[current_module][func_key] = {}

            # Try to parse the value
            val = parse_matlab_value(raw_val)
            result[current_module][func_key][param_name] = val
            continue

        # Also match "config.general = general;" or similar (skip)
        # Match "config.preprocessing = preproc;" (skip)
        m = re.match(r'config\.(\w+)\s*=\s*\w+;', stripped)
        if m:
            continue

    return result


def parse_matlab_value(raw):
    """Convert a MATLAB literal string to Python value."""
    raw = raw.strip()
    # Strip trailing comment (% ...) first — before stripping ; because the
    # semicolon may be before spaces+comment, e.g. "250;     % comment"
    ci = raw.find(" %")
    if ci >= 0:
        before = raw[:ci]
        # Make sure we're not inside a string
        if before.count('"') % 2 == 0 and before.count("'") % 2 == 0:
            raw = before.strip()
    # Now strip trailing semicolon and whitespace
    raw = raw.rstrip(';').strip()

    if raw == "true":
        return True
    if raw == "false":
        return False

    # Empty cell: {}
    if raw == "{}":
        return []

    # Cell array: {'a', 'b'} or {"a", "b"}
    if raw.startswith("{") and raw.endswith("}"):
        inner = raw[1:-1]
        items = re.findall(r"'([^']*)'|\"([^\"]*)\"", inner)
        vals = [a or b for a, b in items]
        # Try to parse numbers too
        if not vals:
            # Might be {1, 2, 3}
            num_items = re.findall(r'([\d.eE+-]+)', inner)
            vals = [float(x) if '.' in x or 'e' in x.lower() else int(x) for x in num_items]
        return vals if len(vals) > 1 else (vals[0] if vals else [])

    # String: "hello" or 'hello'
    if (raw.startswith('"') and raw.endswith('"')) or (raw.startswith("'") and raw.endswith("'")):
        return raw[1:-1]

    # Array: [1, 2] or [1 2] or [NaN NaN]
    if raw.startswith("[") and raw.endswith("]"):
        inner = raw[1:-1].strip()
        if inner == "":
            return []
        parts = re.split(r'[\s,]+', inner)
        vals = []
        for p in parts:
            p = p.strip()
            if p.upper() == "NAN":
                vals.append(None)
            elif p.upper() == "INF":
                vals.append(float("inf"))
            elif "." in p or "e" in p.lower():
                vals.append(float(p))
            else:
                try:
                    vals.append(int(p))
                except ValueError:
                    vals.append(p)
        return vals

    # Number: 250, 0.5, etc.
    try:
        if "." in raw or "e" in raw.lower():
            return float(raw)
        return int(raw)
    except ValueError:
        pass

    # Empty: [] or nothing
    if raw == "[]" or raw == "":
        return None

    return raw


def parse_arguments_block(text):
    """Extract types, enums, sizes from the arguments(Input) block."""
    types = {}
    enums = {}
    sizes = {}

    # Find arguments(Input) block
    # Use \nend as marker to avoid matching "extended" etc.
    m = re.search(r'arguments\s*\(Input\)\s*\n(.*?)\n(\s*)end\b', text, re.DOTALL)
    if not m:
        m = re.search(r'arguments\s*\(Input\)\s*(.*?)\n\s*end\b', text, re.DOTALL)
    if not m:
        return types, enums, sizes

    block = m.group(1)

    for line in block.splitlines():
        line = line.strip()
        if not line or line.startswith("%"):
            continue
        # Remove inline comments
        ci = line.find(" %")
        if ci > 0:
            before = line[:ci]
            if before.count('"') % 2 == 0 and before.count("'") % 2 == 0:
                line = before.strip()

        # Match: opt.ParamName (dim1, dim2) type {mustBeMember(...)} = default
        m2 = re.match(
            r'^opt\.(\w+)'             # param name
            r'\s*(?:\(([^)]*)\))?'      # optional dimensions (1,2) or (1,:)
            r'\s*(\w+)'                 # type string (logical, double, string...)
            r'\s*(?:\{(.*?)\})?'        # optional constraint block {mustBeMember(...)}
            r'\s*(?:=\s*(.*))?'         # optional default value
            r'\s*$',
            line
        )
        if not m2:
            continue

        param_name = m2.group(1)

        # Dimensions
        if m2.group(2):
            dim_str = m2.group(2).strip()
            try:
                dims = []
                for d in dim_str.split(","):
                    d = d.strip()
                    if d == ":":
                        dims.append(None)
                    else:
                        dims.append(int(d))
                if len(dims) > 1 or (len(dims) == 1 and dims[0] != 1):
                    sizes[param_name] = dims
            except ValueError:
                pass

        # Type
        raw_type = m2.group(3)
        type_map = {
            "logical": "logical", "double": "double", "single": "double",
            "string": "string", "cell": "cell",
            "int8": "integer", "int16": "integer", "int32": "integer", "int64": "integer",
        }
        types[param_name] = type_map.get(raw_type, "string")

        # Constraint block → extract mustBeMember enum values
        constraint = m2.group(4)
        if constraint:
            mem = re.search(r'mustBeMember\s*\([^,]+,\s*\[(.+?)\]\)', constraint)
            if mem:
                inner = mem.group(1)
                # Extract quoted strings: "value1", "value2"
                vals = re.findall(r'"([^"]*)"', inner)
                if vals:
                    enums[param_name] = vals

    return types, enums, sizes


def human_label(func_name):
    """Convert HRB_functionName to a nice label."""
    name = func_name.replace("HRB_", "")
    # CamelCase to words
    name = re.sub(r'([a-z])([A-Z])', r'\1 \2', name)
    name = name[0].upper() + name[1:] if name else name
    return name


def main():
    # Read HRB_defaultConfig.m
    config_file = FUNCTIONS_DIR / "0_misc" / "HRB_defaultConfig.m"
    with open(config_file) as f:
        config_text = f.read()

    config_data = parse_default_config(config_text)

    # Build output
    output = {}

    for module, func_map in CONFIG_TO_FUNC.items():
        mod_config = config_data.get(module, {})
        mod_out = {}

        for config_key, func_name in func_map.items():
            # Find the function file
            folder = MODULE_FOLDERS.get(module)
            if not folder:
                continue
            func_file = FUNCTIONS_DIR / folder / f"{func_name}.m"
            if not func_file.exists():
                print(f"WARNING: {func_file} not found")
                continue

            with open(func_file) as f:
                func_text = f.read()

            # Parse arguments block
            arg_types, arg_enums, arg_sizes = parse_arguments_block(func_text)

            # Get config defaults
            func_config = mod_config.get(config_key, {})

            # Build params dict
            params = {}
            for pname, default_val in func_config.items():
                if pname in BOILERPLATE:
                    continue
                pdef = {}
                pdef["default"] = default_val
                pdef["type"] = arg_types.get(pname, "string")
                if pname in arg_enums:
                    pdef["enum"] = arg_enums[pname]
                if pname in arg_sizes:
                    pdef["size"] = arg_sizes[pname]
                params[pname] = pdef

            mod_out[config_key] = {
                "label": human_label(func_name),
                "function": func_name,
                "module": module,
                "params": params,
            }

        output[module] = mod_out

    # Write output
    gui_dir = GUI_DIR
    gui_dir.mkdir(parents=True, exist_ok=True)
    output_file = gui_dir / "function_definitions.json"

    with open(output_file, "w") as f:
        json.dump(output, f, indent=2, ensure_ascii=False)

    print(f"✅ Written {output_file}")
    print(f"   Modules: {list(output.keys())}")
    for mod, funcs in output.items():
        print(f"   {mod}: {list(funcs.keys())}")


if __name__ == "__main__":
    main()
