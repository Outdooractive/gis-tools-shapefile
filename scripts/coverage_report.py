#!/usr/bin/env python3
"""Run the tests with coverage and print GISToolsShapefile coverage.

SwiftPM writes a JSON coverage report next to the build products. Reading that
report works on both macOS and Linux, so this script does not depend on
``llvm-cov`` or platform-specific object-file layouts.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE_MARKER = "/Sources/GISToolsShapefile/"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--minimum", type=float, default=0.0)
    args = parser.parse_args()

    subprocess.run(
        ["swift", "test", "--enable-code-coverage"],
        cwd=ROOT,
        check=True,
    )

    json_path = Path(subprocess.check_output(
        ["swift", "test", "--show-codecov-path"],
        cwd=ROOT,
        text=True,
    ).strip())

    report = json.loads(json_path.read_text())
    data = report.get("data", [])
    files = [
        file
        for file in (data[0].get("files", []) if data else [])
        if SOURCE_MARKER in file["filename"]
    ]

    if not files:
        print("No GISToolsShapefile coverage entries found", file=sys.stderr)
        sys.exit(2)

    rows = []
    total_lines = 0
    covered_lines = 0
    total_functions = 0
    covered_functions = 0
    total_regions = 0
    covered_regions = 0

    for file in files:
        summary = file["summary"]
        lines = summary.get("lines", {"count": 0, "covered": 0})
        functions = summary.get("functions", {"count": 0, "covered": 0})
        regions = summary.get("regions", {"count": 0, "covered": 0})

        total_lines += int(lines["count"])
        covered_lines += int(lines["covered"])
        total_functions += int(functions["count"])
        covered_functions += int(functions["covered"])
        total_regions += int(regions["count"])
        covered_regions += int(regions["covered"])

        relative = file["filename"].split(SOURCE_MARKER, 1)[1]
        percent = (
            100.0 * int(lines["covered"]) / int(lines["count"])
            if int(lines["count"]) else 0.0
        )
        rows.append((relative, int(lines["count"]), int(lines["covered"]), percent))

    rows.sort()
    print()
    print(f"{'File':48} {'Lines':>7} {'Covered':>8} {'Cover':>8}")
    print("-" * 75)
    for relative, count, covered, percent in rows:
        print(f"{relative:48} {count:7d} {covered:8d} {percent:7.2f}%")
    print("-" * 75)

    line_coverage = 100.0 * covered_lines / total_lines if total_lines else 0.0
    function_coverage = (
        100.0 * covered_functions / total_functions
        if total_functions else 0.0
    )
    region_coverage = (
        100.0 * covered_regions / total_regions
        if total_regions else 0.0
    )

    print(
        f"{'Total':48} {total_lines:7d} {covered_lines:8d} "
        f"{line_coverage:7.2f}%"
    )
    print(
        f"Functions: {function_coverage:.2f}% "
        f"({covered_functions}/{total_functions}), "
        f"regions: {region_coverage:.2f}% "
        f"({covered_regions}/{total_regions})"
    )

    if line_coverage < args.minimum:
        print(
            f"Line coverage {line_coverage:.2f}% is below the "
            f"{args.minimum:.2f}% minimum",
            file=sys.stderr,
        )
        sys.exit(1)


if __name__ == "__main__":
    main()
