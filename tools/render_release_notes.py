#!/usr/bin/env python3
"""Render GitHub Release body links after the actual repository name is known."""
import argparse
import re
from pathlib import Path
from urllib.parse import quote

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repository', required=True, help='Actual owner/repository')
    parser.add_argument('--tag', required=True, help='Existing release tag, e.g. v0.3.4')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', args.repository):
        parser.error('Use owner/repository')
    if not re.fullmatch(r'[A-Za-z0-9_.-]+', args.tag):
        parser.error('Invalid tag')
    text = (ROOT / 'docs/RELEASE.md').read_text()
    def link(match):
        mark, label, target = match.groups()
        if target.startswith(('https://', 'http://', '#')):
            return match[0]
        file = (ROOT / 'docs' / target).resolve()
        relative = file.relative_to(ROOT).as_posix()
        host = 'https://raw.githubusercontent.com' if mark else 'https://github.com'
        branch = args.tag if mark else 'blob/' + args.tag
        return f'{mark}[{label}]({host}/{args.repository}/{branch}/{quote(relative)})'
    text = re.sub(r'(!?)\[([^\]]+)\]\(([^)]+)\)', link, text)
    args.output.write_text(text, encoding='utf-8')
    print('Release body written locally; nothing uploaded.')


if __name__ == '__main__':
    main()
