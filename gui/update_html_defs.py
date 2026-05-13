#!/usr/bin/env python3
"""Inline the latest function_definitions.json into pipeline-builder.html.

Usage:
    python3 gui/update_html_defs.py

Run this after regenerating function_definitions.json to update the HTML.
"""

import json, re, sys
from pathlib import Path

GUI_DIR = Path(__file__).resolve().parent
JSON_FILE = GUI_DIR / "function_definitions.json"
HTML_FILE = GUI_DIR / "pipeline-builder.html"


def main():
    if not JSON_FILE.exists():
        print(f"❌ {JSON_FILE} not found. Run extract_defs.py first.")
        sys.exit(1)

    with open(JSON_FILE) as f:
        data = json.load(f)

    json_str = json.dumps(data, indent=2)

    with open(HTML_FILE) as f:
        html = f.read()

    # Replace the inline JSON variable assignment
    pattern = r'(let functionDefinitions = )\{[\s\S]*?;\n\nfunction loadDefinitions'
    replacement = r'\1' + json_str + r';\n\nfunction loadDefinitions'

    if not re.search(pattern, html):
        print("❌ Could not find inline definitions placeholder in HTML.")
        sys.exit(1)

    new_html = re.sub(pattern, replacement, html)

    with open(HTML_FILE, 'w') as f:
        f.write(new_html)

    # Count functions
    total = sum(len(funcs) for funcs in data.values())
    print(f"✅ Updated {HTML_FILE}")
    print(f"   Inlined {total} functions across {len(data)} modules")


if __name__ == "__main__":
    main()
