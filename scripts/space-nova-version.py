#!/usr/bin/env python3
"""Space Nova's authoritative release version is in the root umbrella mix.exs.

Generate desktop version metadata in build workspaces, not in release commits.
"""
import argparse
import json
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[1]
VERSION_PATTERN = re.compile(r'(?m)^(\s*version:\s*)"(\d+\.\d+\.\d+)"(\s*,)')
CARGO_PACKAGE = re.compile(r'(?ms)(^\[package\]\s*)(.*?)(?=^\[|\Z)')
CARGO_VERSION = re.compile(r'(?m)^(version\s*=\s*)"\d+\.\d+\.\d+"')

def umbrella_version(root):
    matches = list(VERSION_PATTERN.finditer((root / 'mix.exs').read_text()))
    if len(matches) != 1:
        raise ValueError('Expected exactly one umbrella project version in mix.exs')
    return matches[0].group(2)

def validate_version(value):
    if not re.fullmatch(r'(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)', value):
        raise ValueError('Version must be numeric X.Y.Z')
    return tuple(map(int, value.split('.')))

def set_version(root, version):
    new = validate_version(version)
    current = umbrella_version(root)
    if new <= validate_version(current):
        raise ValueError(f'{version} must be newer than {current}')
    path = root / 'mix.exs'
    original = path.read_text()
    path.write_text(VERSION_PATTERN.sub(lambda m: f'{m.group(1)}"{version}"{m.group(3)}', original, count=1))
    print(f'Updated umbrella mix.exs: {current} -> {version}')

def sync_client_metadata(root, version):
    client = root / 'clients' / 'tauri'
    paths = [client / 'package.json', client / 'package-lock.json', client / 'src-tauri' / 'tauri.conf.json']
    for path in paths:
        data = json.loads(path.read_text())
        data['version'] = version
        if path.name == 'package-lock.json':
            data['packages']['']['version'] = version
        path.write_text(json.dumps(data, indent=2) + '\n')

    cargo_path = client / 'src-tauri' / 'Cargo.toml'
    cargo = cargo_path.read_text()
    package = CARGO_PACKAGE.search(cargo)
    if not package:
        raise ValueError('Missing Cargo [package] section')
    section = package.group(2)
    if len(CARGO_VERSION.findall(section)) != 1:
        raise ValueError('Expected one Cargo package version')
    replacement = CARGO_VERSION.sub(lambda m: f'{m.group(1)}"{version}"', section, count=1)
    cargo_path.write_text(cargo[:package.start(2)] + replacement + cargo[package.end(2):])
    print(f'Generated Tauri/npm/Cargo build metadata: {version}')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['get', 'check', 'set', 'sync'])
    parser.add_argument('version', nargs='?')
    parser.add_argument('--root', type=pathlib.Path, default=ROOT)
    args = parser.parse_args()
    root = args.root.resolve()
    try:
        current = umbrella_version(root)
        if args.command == 'get':
            print(current)
        elif args.command == 'check':
            if not args.version or args.version != current:
                raise ValueError(f'Expected root version {args.version}, found {current}')
            validate_version(current)
            print(f'Validated umbrella release version {current}')
        elif args.command == 'set':
            if not args.version:
                raise ValueError('set requires a new version')
            set_version(root, args.version)
        elif args.command == 'sync':
            if args.version and args.version != current:
                raise ValueError(f'Expected version {args.version}, found {current}')
            sync_client_metadata(root, current)
    except (ValueError, KeyError, OSError) as exc:
        parser.exit(1, f'Error: {exc}\n')

if __name__ == '__main__':
    main()
