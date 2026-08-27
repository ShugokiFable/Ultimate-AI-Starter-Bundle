"""Regenerate MANIFEST.json (path, size, sha256) for the whole pack.

Excludes the manifest itself so the file cannot try to hash its own output.

    python generate_manifest.py <pack-root>
"""
import hashlib
import io
import json
import os
import sys

# 'dist' holds the release zips TOOLS/Build-Release.ps1 writes. Recording
# them here makes MANIFEST describe a tree that only exists on the machine
# that built them, so a fresh clone fails verification with MISSING dist/...
SKIP_DIRS = {'.git', '.worktrees', '__pycache__', 'node_modules', 'cache', 'dist', 'artifacts', '.venv', 'venv', '.pytest_cache', '.mypy_cache', '.ruff_cache', '.tox', '.nox', 'htmlcov', '.grok', '.serena'}
SKIP_NAMES = {'MANIFEST.json', '.git', '.coverage', 'coverage.xml', '.DS_Store',
              # Written by TESTS/evidence-scenarios/check_fixtures.py when it
              # proves scenario C still fails. Output of a fixture, not content.
              'app.log', 'config.MAINTAINER.yaml'}


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else '.'
    # Only describe git-tracked files. Walking the raw filesystem pins
    # personal/scratch files into MANIFEST, and a fresh clone then fails
    # verification with MISSING for files it never had.
    #
    # -z, and NOT text mode. Plain `git ls-files` OCTAL-QUOTES any path with a
    # non-ASCII byte -- an em dash or an emoji comes back as
    #   "0-UNRESTRAINT-PACKS/AIO-INSTRUCTION \342\200\224 Compact.md"
    # quotes and all -- while os.walk yields the real name. The two never
    # matched, so those files were dropped from the manifest without a word.
    # Twelve tracked files were shipping unverified this way, and
    # verify_manifest.py could not see it: it checks that everything RECORDED
    # exists, never that everything that exists is recorded.
    import subprocess
    raw = subprocess.run(
        ['git', '-C', root, '-c', 'safe.directory=' + os.path.abspath(root),
         'ls-files', '-z'],
        capture_output=True, check=True).stdout
    tracked = set(p for p in raw.decode('utf-8').split('\0') if p)
    rows = []
    total = 0
    for dp, dirs, fs in os.walk(root):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        rel_dir = os.path.relpath(dp, root).replace('\\', '/')
        # Offline assets are the zip/whl files in this folder. Extracted
        # copies (same name, no extension) are local cache.
        if rel_dir == 'BUNDLED-TOOLS/offline':
            dirs[:] = []
        if rel_dir == '2-OPTIONAL-MANUAL-OTHER-GAMES-MEGA-PACK':
            dirs[:] = [d for d in dirs if not d.startswith('Other-Games-Modding-Skills-Mega-Pack-v2.1.0')]
        for f in sorted(fs):
            p = os.path.join(dp, f)
            rel = os.path.relpath(p, root).replace('\\', '/')
            # MANIFEST.json is skipped only at the ROOT -- that is the file
            # being written, and it cannot hash its own output. Matching the
            # bare name anywhere also excluded the vendored Forge manifest at
            # BUNDLED-TOOLS/skyrim-forge/MANIFEST.json, a tracked file that
            # then shipped unverified.
            if f == 'MANIFEST.json':
                if rel == 'MANIFEST.json':
                    continue
            elif f in SKIP_NAMES:
                continue
            if rel not in tracked:
                continue  # ponytail: untracked personal files are invisible to the pack
            data = open(p, 'rb').read()
            total += len(data)
            rows.append({'path': rel,
                         'size': len(data),
                         'sha256': hashlib.sha256(data).hexdigest()})
    rows.sort(key=lambda r: r['path'])
    out = os.path.join(root, 'MANIFEST.json')
    io.open(out, 'w', encoding='utf-8', newline='\n').write(
        json.dumps(rows, indent=1) + '\n')
    print('%d files, %.1f MB -> %s' % (len(rows), total / 1048576, out))


if __name__ == '__main__':
    main()
