#!/usr/bin/env python3
"""Merge separately generated bigram and trigram score tables."""

from __future__ import annotations

import argparse
from pathlib import Path


def copy_rows(source: Path, output, expected_kind: str) -> int:
    count = 0
    with source.open(encoding="utf-8") as input_file:
        for line in input_file:
            if line.startswith("#") or not line.strip():
                continue
            fields = line.split()
            if not fields or fields[0] != expected_kind:
                raise ValueError(f"{source}: expected {expected_kind} rows, received {fields[0] if fields else 'empty row'}")
            output.write(" ".join(fields) + "\n")
            count += 1
    return count


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bigrams", required=True, help="Input table containing only B rows")
    parser.add_argument("--trigrams", required=True, help="Input table containing only T rows")
    parser.add_argument("--output", required=True)
    parser.add_argument("--bigram-source", required=True)
    parser.add_argument("--trigram-source", required=True)
    parser.add_argument("--bigram-settings", required=True)
    parser.add_argument("--trigram-settings", required=True)
    args = parser.parse_args()

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8", newline="\n") as output:
        output.write("# gg character n-gram association table; positive PMI in natural-log units\n")
        output.write("# bigram scores are positive PMI; trigram scores are positive conditional PMI lift; each is clipped to 4.0\n")
        output.write(f"# bigram_sources={args.bigram_source}\n")
        output.write(f"# trigram_sources={args.trigram_source}\n")
        output.write(f"# bigram_settings={args.bigram_settings}\n")
        output.write(f"# trigram_settings={args.trigram_settings}\n")
        output.write("# fields: B previous_scalar_hex next_scalar_hex score, or T first_scalar_hex second_scalar_hex next_scalar_hex score\n")
        bigram_count = copy_rows(Path(args.bigrams), output, "B")
        trigram_count = copy_rows(Path(args.trigrams), output, "T")
    print(f"Merged {bigram_count:,} bigrams and {trigram_count:,} trigrams into {output_path}")


if __name__ == "__main__":
    main()
