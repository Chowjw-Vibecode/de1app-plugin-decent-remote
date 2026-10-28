#!/usr/bin/env python3
"""Offline regression runner. Never opens a device connection."""
import argparse
import datetime
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys

parser = argparse.ArgumentParser()
parser.add_argument('--tcl86', default=os.environ.get('TCLSH') or shutil.which('tclsh8.6') or shutil.which('tclsh'))
parser.add_argument('--tcllib', default='', help='Optional Tcllib directory; otherwise use Tcl package discovery')
parser.add_argument('--browser', action='store_true', help='Run isolated Chromium dashboard checks too')
parser.add_argument('--output', type=pathlib.Path, help='Save the verified result as JSON')
args = parser.parse_args()
if not args.tcl86:
    parser.error('Install Tcl 8.6 or provide --tcl86 /path/to/tclsh8.6')
root = pathlib.Path(__file__).resolve().parent
results = []
env = os.environ.copy()
env['TCLSH'] = args.tcl86
if args.tcllib:
    env['TCLLIBPATH'] = '{' + args.tcllib + '} ' + env.get('TCLLIBPATH', '')
for name in ('core', 'access', 'adapter', 'controls', 'editor', 'extensions', 'integration', 'hds', 'legacy', 'lifecycle', 'profile_import', 'send_gate'):
    proc = subprocess.run([args.tcl86, str(root / f'{name}.test.tcl')], capture_output=True, text=True, env=env)
    match = re.search(r'Total\s+(\d+)\s+Passed\s+(\d+)\s+Skipped\s+(\d+)\s+Failed\s+(\d+)', proc.stdout)
    if proc.returncode or not match or match[3] != '0' or match[4] != '0':
        print(proc.stdout, proc.stderr)
        raise SystemExit(f'FAIL: {name}')
    results.append(dict(suite=name, total=int(match[1]), passed=int(match[2])))
proc = subprocess.run([sys.executable, str(root / 'config.test.py')], capture_output=True, text=True, env=env)
if proc.returncode:
    print(proc.stdout, proc.stderr)
    raise SystemExit('FAIL: first-install configuration')
results.append(dict(suite='config', total=8, passed=8))
proc = subprocess.run([sys.executable, str(root / 'http_integration.py'), '--wibble', str(root / 'vendor/wibble.tcl'), '--tcl', args.tcl86, '--tcllib', args.tcllib], capture_output=True, text=True, env=env)
if proc.returncode or 'PASS:' not in proc.stdout:
    print(proc.stdout, proc.stderr)
    raise SystemExit('FAIL: real HTTP')
version = re.search(r'variable version ([0-9.]+)', (root.parent / 'plugin.tcl').read_text())[1]
report = {'checked_at': datetime.datetime.now().astimezone().isoformat(timespec='seconds'), 'version': version, 'unit_suites': results, 'unit_total': sum(r['total'] for r in results), 'http': proc.stdout.strip(), 'hardware': 'mocked; no real device commands', 'scope': 'offline regression; this runner does not deploy to a tablet'}
if args.browser:
    proc = subprocess.run(['node', str(root / 'dashboard.test.cjs')], capture_output=True, text=True, env=env)
    match = re.search(r'(\{\n  "passed":[\s\S]*\})\s*$', proc.stdout)
    if proc.returncode or not match:
        print(proc.stdout, proc.stderr)
        raise SystemExit('FAIL: dashboard')
    report['browser'] = json.loads(match[1])
    if report['browser']['failed']:
        raise SystemExit('FAIL: dashboard results')
serialized = json.dumps(report, ensure_ascii=False, indent=2) + '\n'
if args.output:
    args.output.write_text(serialized, encoding='utf8')
print(serialized, end='')
