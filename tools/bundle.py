"""Inline the player into a watchface entry script using only the standard library."""

import argparse
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
IMPORT = 'local ShufflePlayer = require("shuffle_player")'


def bundle(entry: str, module: str) -> str:
    if entry.splitlines().count(IMPORT) != 1:
        raise ValueError(f"entry must contain exactly one standalone line: {IMPORT}")
    replacement = "local ShufflePlayer = (function()\n" + module.rstrip() + "\nend)()"
    return "\n".join(replacement if line == IMPORT else line for line in entry.splitlines()) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--entry", type=Path, default=ROOT / "examples/main.lua")
    parser.add_argument("--output", type=Path, default=ROOT / "dist/main.lua")
    arguments = parser.parse_args()
    source = bundle(arguments.entry.read_text(encoding="utf-8"),
                    (ROOT / "src/shuffle_player.lua").read_text(encoding="utf-8"))
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(source, encoding="utf-8")
    print(arguments.output)


if __name__ == "__main__":
    main()
