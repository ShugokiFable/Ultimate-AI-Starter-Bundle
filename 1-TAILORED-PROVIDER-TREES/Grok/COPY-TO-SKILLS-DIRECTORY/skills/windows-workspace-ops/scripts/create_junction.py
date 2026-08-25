#!/usr/bin/env python3
"""Create an NTFS junction without admin, reliably from git-bash/Hermes.

Why not `cmd /c mklink /J`? From the MSYS bash on this machine the spawned
cmd can run with the wrong CWD (junction lands at the drive root) and MSYS
mangles the Z:\\... target into /z/Z:/... .

Usage:
    python create_junction.py <target> <link>
    python create_junction.py --clean <link>        # remove stray/mangled junction

Examples:
    python create_junction.py "Z:\\Backup\\!Skyrim AE\\...\\NPC Pathing NG 2.4.0\\extern\\CommonLibSSE" ^
                              "Z:\\Backup\\!Skyrim AE\\...\\NPC Pathing NG 2.5.0\\extern\\CommonLibSSE"

Verifies the link resolves to the target afterwards (checks the target exists
via a marker probe). Exit code 0 = created and verified.
"""
from __future__ import annotations

import argparse
import os
import sys


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("target", nargs="?", help="junction target (the real directory)")
    parser.add_argument("link", nargs="?", help="junction link path to create")
    parser.add_argument("--clean", metavar="LINK", help="remove an existing (possibly stray) junction")
    args = parser.parse_args()

    if args.clean:
        if not os.path.isdir(args.clean):
            print(f"nothing to clean: {args.clean} is not a directory/junction", file=sys.stderr)
            return 1
        os.rmdir(args.clean)  # works on junctions without admin
        print(f"removed junction: {args.clean}")
        return 0

    if not args.target or not args.link:
        parser.error("target and link are required (or use --clean LINK)")

    if os.path.exists(args.link):
        print(f"refusing: link already exists: {args.link}", file=sys.stderr)
        return 1
    if not os.path.isdir(args.target):
        print(f"refusing: target is not a directory: {args.target}", file=sys.stderr)
        return 1

    import _winapi
    _winapi.CreateJunction(os.path.normpath(args.target), os.path.normpath(args.link))

    # Verify it resolves: follow the junction and stat a marker inside.
    if not os.path.isdir(args.link):
        print(f"FAILED: {args.link} does not resolve", file=sys.stderr)
        return 1

    # Probe the first entry of the target so a silent empty-target edge case
    # cannot pass verification.
    try:
        marker = next(os.scandir(args.link)).path
        if not os.path.exists(marker):
            raise OSError("marker does not exist")
    except (StopIteration, OSError) as exc:
        print(f"FAILED: junction target appears empty/unreadable: {exc}", file=sys.stderr)
        return 1

    print(f"junction created: {os.path.normpath(args.link)} -> {os.path.normpath(args.target)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())