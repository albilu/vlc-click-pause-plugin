#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later
"""Embed a gettext catalog so VLC 3's cached module labels stay localized."""

import argparse
import gettext
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    lines = ["/* Generated from the selected PO catalog. Do not edit. */"]
    if args.catalog is None:
        lines.append("#define _(message) (message)")
    else:
        with args.catalog.open("rb") as source:
            catalog = gettext.GNUTranslations(source)
        lines.extend([
            "#include <string.h>",
            "static inline const char *clickpause_translate(const char *message)",
            "{",
        ])
        for message, translation in sorted(catalog._catalog.items()):
            if not message:
                continue
            if not isinstance(message, str) or not isinstance(translation, str):
                parser.error("only singular messages are supported")
            # JSON string escaping also produces valid C string literals.
            original = json.dumps(message, ensure_ascii=False)
            translated = json.dumps(translation, ensure_ascii=False)
            lines.append(f"    if (strcmp(message, {original}) == 0)")
            lines.append(f"        return {translated};")
        lines.extend([
            "    return message;",
            "}",
            "#define _(message) clickpause_translate(message)",
        ])
    args.output.write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
