#!/usr/bin/env python3
"""Build review/install archives from an explicit allowlist. No device or network."""
import argparse
import json
import re
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUNTIME = '''plugin.tcl access.tcl adapter.tcl controls.tcl core.tcl editor.tcl
hds.tcl json_body.tcl legacy.tcl profiles.tcl receipts.tcl transport.tcl usage.tcl
index.html doc.json'''.split()
DOCS = '''README.md README.zh-CN.md LICENSE THIRD_PARTY.md CHANGELOG.md API.md
docs/API.md docs/AGENTS.md docs/COMPATIBILITY.md docs/SCREENSHOTS.md
docs/VALIDATION.md docs/RELEASE.md docs/DEVELOPMENT.md docs/USAGE.md
docs/images/current-en-dark.png docs/images/current-zh-dark.png
docs/images/current-zh-light.png docs/images/profiles-en-dark.png
docs/images/history-en-dark.png docs/images/settings-en-light.png'''.split()
TESTS = [f'tests/{name}.test.tcl' for name in (
    'core', 'access', 'adapter', 'controls', 'editor', 'extensions',
    'integration', 'hds', 'legacy', 'lifecycle', 'profile_import', 'send_gate')]
SOURCE = '''.gitignore .github/workflows/test.yml package.json package-lock.json
tests/config.test.py tests/http_integration.py tests/run.py tests/dashboard.test.cjs
tests/fixtures/filter3.tcl tests/vendor/wibble.tcl tests/vendor/TCL-TK-LICENSE.txt
tools/build_release.py tools/render_release_notes.py
.github/workflows/usage-pages.yml statistics/.gitignore statistics/worker.mjs
statistics/schema.sql statistics/wrangler.example.toml statistics/README.md
statistics/README.en.md statistics/tests/worker.test.mjs statistics/tests/client.test.tcl
statistics/tests/export.test.py statistics/tools/export_summary.py
statistics/site/index.html statistics/site/data.json'''.split() + TESTS
INSTALL = RUNTIME + DOCS + ['tools/create_config.py']


def checked(name):
    relative = Path(name)
    if relative.is_absolute() or '..' in relative.parts:
        raise ValueError(f'Invalid package path: {name}')
    path = ROOT
    for part in relative.parts:
        path = path / part
        if path.is_symlink():
            raise ValueError(f'Symlink excluded: {name}')
    if not path.is_file():
        raise FileNotFoundError(name)
    return path


def archive(destination, prefix, names):
    if len(names) != len(set(names)):
        raise ValueError('Duplicate file in package list')
    files = [(name, checked(name).read_bytes()) for name in sorted(names)]
    with zipfile.ZipFile(destination, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as out:
        for name, content in files:
            info = zipfile.ZipInfo(prefix + '/' + name, (2026, 10, 27, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            out.writestr(info, content)
    with zipfile.ZipFile(destination) as result:
        if result.testzip() is not None:
            raise RuntimeError('Archive integrity check failed')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'dist')
    args = parser.parse_args()
    version = re.search(r'variable version ([0-9.]+)', checked('plugin.tcl').read_text())[1]
    for name in ('doc.json', 'package.json', 'package-lock.json'):
        if json.loads(checked(name).read_text())['version'] != version:
            raise ValueError(f'Version mismatch: {name}')
    dashboard_version = re.search(r"info\('Decent Remote','([0-9.]+) ·", checked('index.html').read_text())
    if dashboard_version is None or dashboard_version[1] != version:
        raise ValueError('Version mismatch: index.html')
    # Validate all paths before creating output.
    for name in INSTALL + SOURCE:
        checked(name)
    args.output.mkdir(parents=True, exist_ok=True)
    install = args.output / f'decent_remote-v{version}.zip'
    source = args.output / f'decent-remote-v{version}-source.zip'
    archive(install, 'decent_remote', INSTALL)
    archive(source, f'de1app-plugin-decent-remote-{version}', INSTALL + SOURCE)
    print(f'Install: {install.name} ({len(INSTALL)} files)')
    print(f'Source:  {source.name} ({len(INSTALL + SOURCE)} files)')


if __name__ == '__main__':
    main()
