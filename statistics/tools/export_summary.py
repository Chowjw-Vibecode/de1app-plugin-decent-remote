#!/usr/bin/env python3
"""Export only validated public country totals; never installation records."""
import argparse
import datetime
import json
import re
import tempfile
from pathlib import Path
from urllib.parse import urlsplit
from urllib.request import Request, build_opener, HTTPRedirectHandler

FIELDS = {'schema', 'generated_at', 'scope', 'total_installations', 'active_30d', 'countries'}

def validate(data):
    if not isinstance(data, dict) or set(data) != FIELDS or type(data['schema']) is not int or data['schema'] != 1:
        raise ValueError('Unexpected summary fields')
    if not isinstance(data['generated_at'], str):
        raise ValueError('Invalid generation time')
    try:
        timestamp = datetime.datetime.fromisoformat(data['generated_at'].replace('Z', '+00:00'))
        if timestamp.tzinfo is None:
            raise ValueError()
    except ValueError:
        raise ValueError('Invalid generation time') from None
    if data['scope'] != 'reporting installations; not people or all users':
        raise ValueError('Unexpected statistics scope')
    def count(value):
        if type(value) is not int or not 0 <= value <= 10**9:
            raise ValueError('Invalid installation count')
        return value
    total, active = count(data['total_installations']), count(data['active_30d'])
    rows = data['countries']
    if not isinstance(rows, list) or len(rows) > 300:
        raise ValueError('Invalid country list')
    seen = set()
    for row in rows:
        if not isinstance(row, dict) or set(row) != {'country', 'installations', 'active_30d'}:
            raise ValueError('Unexpected country fields')
        code = row['country']
        if not isinstance(code, str) or not re.fullmatch('[A-Z]{2}', code) or code in seen:
            raise ValueError('Invalid country code')
        seen.add(code)
        if count(row['active_30d']) > count(row['installations']):
            raise ValueError('Active count exceeds total')
    if total != sum(r['installations'] for r in rows) or active != sum(r['active_30d'] for r in rows) or active > total:
        raise ValueError('Country totals do not reconcile')
    return data

class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None

def fetch(url):
    parsed = urlsplit(url)
    if parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password or parsed.path != '/v1/summary' or parsed.query or parsed.fragment:
        raise ValueError('Use the public HTTPS /v1/summary endpoint')
    req = Request(url, headers={'Accept': 'application/json', 'User-Agent': 'DecentRemoteSummary'})
    with build_opener(NoRedirect()).open(req, timeout=15) as response:
        raw = response.read(65537)
    if len(raw) > 65536:
        raise ValueError('Summary exceeds size limit')
    return validate(json.loads(raw))

def write_summary(data, path):
    data = validate(data)
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent, prefix='.'+path.name+'.', suffix='.tmp', delete=False) as f:
        temporary = Path(f.name)
    try:
        temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)

if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--url', required=True)
    p.add_argument('--output', type=Path, default=Path(__file__).resolve().parents[1] / 'site/data.json')
    args = p.parse_args()
    write_summary(fetch(args.url), args.output)
