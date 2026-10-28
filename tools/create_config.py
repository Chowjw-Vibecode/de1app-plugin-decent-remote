#!/usr/bin/env python3
"""Create a fresh local config. Never contacts de1app or prints the secret."""
import argparse
import os
from pathlib import Path
import secrets


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True, help='New settings.tdb file; existing files are never overwritten')
    parser.add_argument('--port', type=int, default=8888)
    parser.add_argument('--hds', action='store_true', help='Enable optional Decent/HDS soft sleep integration')
    parser.add_argument('--random-key', action='store_true', help='Use a random key instead of the default admin1234')
    args = parser.parse_args()
    if not 1024 <= args.port <= 65535:
        parser.error('port must be between 1024 and 65535')
    token = secrets.token_hex(32) if args.random_key else 'admin1234'
    content = f'port {args.port}\ntoken {token}\nallow_start 0\nhds_enabled {int(args.hds)}\n'
    try:
        descriptor = os.open(args.output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        parser.error('output already exists; no configuration was changed')
    with os.fdopen(descriptor, 'w', encoding='utf8') as out:
        out.write(content)
    print(f'Created {args.output}. Keep it private; it contains the access token. Remote starts are disabled.')


if __name__ == '__main__':
    main()
