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
PRODUCTS = {'decent_remote', 'this_cup'}
COUNTRY_FIELDS = {'total_installations', 'active_30d', 'countries'}
VERSION = re.compile(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-((?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)(?:\.(?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*))*))?(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?')

def validate(data):
    if not isinstance(data, dict) or type(data.get('schema')) is not int or data['schema'] not in (1, 2):
        raise ValueError('Unexpected summary fields')
    expected = FIELDS | ({'products'} if data['schema'] == 2 else set())
    if set(data) != expected:
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
    validate_countries(data)
    if data['schema'] == 2:
        products = data['products']
        if not isinstance(products, list) or len(products) != len(PRODUCTS):
            raise ValueError('Invalid product list')
        seen, combined = set(), {}
        for product in products:
            if not isinstance(product, dict) or set(product) not in (COUNTRY_FIELDS | {'product'}, COUNTRY_FIELDS | {'product', 'versions'}):
                raise ValueError('Unexpected product fields')
            name = product['product']
            if not isinstance(name, str) or name not in PRODUCTS or name in seen:
                raise ValueError('Invalid product')
            seen.add(name)
            validate_countries(product)
            if 'versions' in product:
                validate_versions(product)
            for row in product['countries']:
                total, active = combined.get(row['country'], (0, 0))
                combined[row['country']] = (total + row['installations'], active + row['active_30d'])
        actual = {r['country']: (r['installations'], r['active_30d']) for r in data['countries']}
        if actual != combined:
            raise ValueError('Product totals do not reconcile')
    return data

def count(value):
    if type(value) is not int or not 0 <= value <= 10**9:
        raise ValueError('Invalid installation count')
    return value

def validate_versions(data):
    rows = data['versions']
    if not isinstance(rows, list) or len(rows) > 1000:
        raise ValueError('Invalid version list')
    seen = set()
    for row in rows:
        if not isinstance(row, dict) or set(row) != {'version', 'installations', 'active_30d'}:
            raise ValueError('Unexpected version fields')
        version = row['version']
        if version is not None and (not isinstance(version, str) or len(version) > 64 or not VERSION.fullmatch(version)):
            raise ValueError('Invalid version')
        if version in seen:
            raise ValueError('Duplicate version')
        seen.add(version)
        if count(row['active_30d']) > count(row['installations']):
            raise ValueError('Active count exceeds total')
    if sum(row['installations'] for row in rows) != data['total_installations'] or sum(row['active_30d'] for row in rows) != data['active_30d']:
        raise ValueError('Version totals do not reconcile')

def validate_countries(data):
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

class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None

def fetch(url, products=False):
    parsed = urlsplit(url)
    if parsed.scheme != 'https' or not parsed.hostname or parsed.username or parsed.password or parsed.path not in ('/v1/summary', '/v2/summary') or parsed.query or parsed.fragment:
        raise ValueError('Use a public HTTPS summary endpoint')
    if products:
        url = parsed._replace(path='/v2/summary').geturl()
    req = Request(url, headers={'Accept': 'application/json', 'User-Agent': 'DecentRemoteSummary'})
    with build_opener(NoRedirect()).open(req, timeout=15) as response:
        raw = response.read(65537)
    if len(raw) > 65536:
        raise ValueError('Summary exceeds size limit')
    data = validate(json.loads(raw))
    if products and data['schema'] != 2:
        raise ValueError('Product summary is not available')
    return data

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
    p.add_argument('--products', action='store_true', help='Fetch /v2/summary, also when the configured URL still ends in /v1/summary')
    p.add_argument('--output', type=Path, default=Path(__file__).resolve().parents[1] / 'site/data.json')
    args = p.parse_args()
    write_summary(fetch(args.url, products=args.products), args.output)
