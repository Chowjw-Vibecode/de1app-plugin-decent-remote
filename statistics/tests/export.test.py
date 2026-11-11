import copy
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('exporter', Path(__file__).parents[1] / 'tools/export_summary.py')
exporter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(exporter)
BASE = dict(schema=1, generated_at='2026-10-27T00:00:00Z', scope='reporting installations; not people or all users', total_installations=2, active_30d=1, countries=[dict(country='CN', installations=2, active_30d=1)])
PRODUCT_BASE = dict(BASE, schema=2, products=[
    dict(product='decent_remote', total_installations=1, active_30d=0, countries=[dict(country='CN', installations=1, active_30d=0)]),
    dict(product='this_cup', total_installations=1, active_30d=1, countries=[dict(country='CN', installations=1, active_30d=1)]),
])

class Export(unittest.TestCase):
    def test_valid_and_empty(self):
        self.assertEqual(exporter.validate(copy.deepcopy(BASE)), BASE)
        data = dict(BASE, total_installations=0, active_30d=0, countries=[])
        self.assertEqual(exporter.validate(data), data)
    def test_private_or_unknown_fields_rejected(self):
        for private in ('install_id', 'id_hash', 'ip', 'token'):
            data = dict(BASE, **{private: 'private'})
            with self.assertRaises(ValueError): exporter.validate(data)
            data = copy.deepcopy(BASE); data['countries'][0][private] = 'private'
            with self.assertRaises(ValueError): exporter.validate(data)
    def test_invalid_counts(self):
        for n in (-1, True, 1.5, '2'):
            data = dict(BASE, total_installations=n)
            with self.assertRaises(ValueError): exporter.validate(data)
        data = dict(BASE, active_30d=3)
        with self.assertRaises(ValueError): exporter.validate(data)
    def test_invalid_country_and_totals(self):
        for code in ('<script>', 'China', 'cn', None):
            data=copy.deepcopy(BASE);data['countries'][0]['country']=code
            with self.assertRaises(ValueError): exporter.validate(data)
        data=copy.deepcopy(BASE);data['countries']*=2
        with self.assertRaises(ValueError): exporter.validate(data)
    def test_failed_validation_preserves_prior_file(self):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'data.json';exporter.write_summary(BASE,path);old=path.read_bytes()
            with self.assertRaises(ValueError): exporter.write_summary(dict(BASE, secret='x'),path)
            self.assertEqual(path.read_bytes(),old)
    def test_schema_requires_an_integer_version(self):
        for version in (True, 1.0, '1', None):
            with self.assertRaises(ValueError):
                exporter.validate(dict(BASE, schema=version))
    def test_timestamp_requires_valid_date_and_timezone(self):
        for value in ('private-marker', '2026-02-30T00:00:00Z', '2026-10-27T00:00:00', ''):
            with self.assertRaisesRegex(ValueError, '^Invalid generation time$'):
                exporter.validate(dict(BASE, generated_at=value))
    def test_failed_atomic_write_keeps_existing_tmp_named_output(self):
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'data.tmp';exporter.write_summary(BASE,path);old=path.read_bytes()
            original=Path.write_text
            def interrupted(target, *args, **kwargs):
                original(target, 'partial output', encoding='utf-8')
                raise OSError('synthetic write interruption')
            with patch.object(Path, 'write_text', interrupted):
                with self.assertRaises(OSError): exporter.write_summary(BASE,path)
            self.assertEqual(path.read_bytes(),old)
            self.assertEqual(list(Path(folder).iterdir()),[path])
    def test_unsafe_urls_rejected_before_network(self):
        for url in ('http://usage.test/v1/summary','https://user:pass@usage.test/v1/summary','https://usage.test/private','https://usage.test/v1/summary?token=secret'):
            with self.assertRaises(ValueError): exporter.fetch(url)
    def test_product_summary_and_zero_category_are_valid(self):
        self.assertEqual(exporter.validate(copy.deepcopy(PRODUCT_BASE)), PRODUCT_BASE)
        data = copy.deepcopy(PRODUCT_BASE)
        data['products'][0].update(total_installations=2, active_30d=1, countries=copy.deepcopy(BASE['countries']))
        data['products'][1].update(total_installations=0, active_30d=0, countries=[])
        self.assertEqual(exporter.validate(data), data)
    def test_product_fields_names_and_duplicate_categories_are_rejected(self):
        for name in ('unknown', None, [], 1, 'decent_remote'):
            data = copy.deepcopy(PRODUCT_BASE);data['products'][1]['product'] = name
            with self.assertRaises(ValueError): exporter.validate(data)
        for field in ('install_id', 'id_hash', 'ip', 'device_id'):
            data = copy.deepcopy(PRODUCT_BASE);data['products'][1][field] = 'private'
            with self.assertRaises(ValueError): exporter.validate(data)
            data = copy.deepcopy(PRODUCT_BASE);data['products'][1]['countries'][0][field] = 'private'
            with self.assertRaises(ValueError): exporter.validate(data)
        for products in (None, {}, [], PRODUCT_BASE['products'][:1]):
            with self.assertRaises(ValueError): exporter.validate(dict(PRODUCT_BASE, products=products))
    def test_product_totals_must_reconcile_by_country_and_count(self):
        data = copy.deepcopy(PRODUCT_BASE);data['products'][1]['countries'][0]['country'] = 'US'
        with self.assertRaisesRegex(ValueError, 'Product totals'): exporter.validate(data)
        data = copy.deepcopy(PRODUCT_BASE);data['products'][1]['countries'][0]['installations'] = 2
        with self.assertRaises(ValueError): exporter.validate(data)
        data = copy.deepcopy(PRODUCT_BASE);data['products'][1]['active_30d'] = True
        with self.assertRaises(ValueError): exporter.validate(data)
    def test_products_flag_upgrades_url_and_requires_v2(self):
        with patch.object(exporter, 'build_opener') as make_opener:
            opener = make_opener.return_value
            for path in ('/v1/summary', '/v2/summary'):
                opener.open.return_value = io.BytesIO(json.dumps(PRODUCT_BASE).encode())
                self.assertEqual(exporter.fetch('https://usage.test'+path, products=True), PRODUCT_BASE)
                self.assertEqual(opener.open.call_args.args[0].full_url, 'https://usage.test/v2/summary')
            opener.open.return_value = io.BytesIO(json.dumps(BASE).encode())
            with self.assertRaisesRegex(ValueError, 'Product summary'): exporter.fetch('https://usage.test/v1/summary', products=True)
    def test_invalid_product_data_keeps_prior_snapshot(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)/'data.json';exporter.write_summary(PRODUCT_BASE,path);old = path.read_bytes()
            data = copy.deepcopy(PRODUCT_BASE);data['products'][1]['countries'][0]['country'] = 'US'
            with self.assertRaises(ValueError): exporter.write_summary(data,path)
            self.assertEqual(path.read_bytes(),old)

    def test_optional_version_summary_unknown_empty_and_legacy_are_valid(self):
        for version in (None, '0.2.31', '0.2.29-rc.11', '1.2.3-alpha.1+build.005', '1.2.3-'+'a'*58):
            data = copy.deepcopy(PRODUCT_BASE)
            data['products'][1]['versions'] = [dict(version=version, installations=1, active_30d=1)]
            self.assertEqual(exporter.validate(data), data)
        data = copy.deepcopy(PRODUCT_BASE)
        data['products'][0].update(total_installations=2, active_30d=1, countries=copy.deepcopy(BASE['countries']), versions=[dict(version='0.3.5', installations=1, active_30d=1), dict(version=None, installations=1, active_30d=0)])
        data['products'][1].update(total_installations=0, active_30d=0, countries=[], versions=[])
        self.assertEqual(exporter.validate(data), data)
        self.assertEqual(exporter.validate(copy.deepcopy(BASE)), BASE)
        self.assertEqual(exporter.validate(copy.deepcopy(PRODUCT_BASE)), PRODUCT_BASE)
    def test_version_formats_and_unknown_fields_are_rejected(self):
        for version in ('', 'v1.2.3', '1.2', '01.2.3', '1.02.3', '1.2.03', '1.2.3-01', '1.2.3-a..b', '1.2.3+', '1.2.3+bad space', '1.2.3-'+'a'*59, 1, True, [], {}):
            data = copy.deepcopy(PRODUCT_BASE)
            data['products'][1]['versions'] = [dict(version=version, installations=1, active_30d=1)]
            with self.assertRaises(ValueError): exporter.validate(data)
        for private in ('install_id', 'id_hash', 'ip', 'device_id', 'token', 'country'):
            data = copy.deepcopy(PRODUCT_BASE)
            data['products'][1]['versions'] = [dict(version='0.2.31', installations=1, active_30d=1, **{private:'private'})]
            with self.assertRaises(ValueError): exporter.validate(data)
        with self.assertRaises(ValueError): exporter.validate(dict(BASE, versions=[]))
    def test_version_counts_duplicates_and_reconciliation(self):
        def product_with(rows):
            data = copy.deepcopy(PRODUCT_BASE)
            data['products'][1]['versions'] = rows
            return data
        for rows in (None, {}, '0.2.31', [], [dict(version='0.2.31', installations=1)], [None], [dict(version='0.2.31', installations=2, active_30d=1)], [dict(version='0.2.31', installations=1, active_30d=0)]):
            with self.assertRaises(ValueError): exporter.validate(product_with(rows))
        for version in (None, '0.2.31'):
            with self.assertRaises(ValueError): exporter.validate(product_with([dict(version=version, installations=1, active_30d=1), dict(version=version, installations=0, active_30d=0)]))
        for field in ('installations','active_30d'):
            for n in (-1, True, 1.5, '1', 10**9+1):
                row = dict(version='0.2.31', installations=1, active_30d=1); row[field] = n
                with self.assertRaises(ValueError): exporter.validate(product_with([row]))
        with self.assertRaises(ValueError): exporter.validate(product_with([dict(version='0.2.31', installations=1, active_30d=2)]))
    def test_versions_preserved_in_export_and_invalid_data_keeps_snapshot(self):
        data = copy.deepcopy(PRODUCT_BASE)
        data['products'][0]['versions'] = [dict(version=None, installations=1, active_30d=0)]
        data['products'][1]['versions'] = [dict(version='0.2.31', installations=1, active_30d=1)]
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)/'data.json'; exporter.write_summary(data,path); old = path.read_bytes()
            self.assertEqual(json.loads(old),data)
            invalid = copy.deepcopy(data); invalid['products'][1]['versions'][0]['installations'] = 2
            with self.assertRaises(ValueError): exporter.write_summary(invalid,path)
            self.assertEqual(path.read_bytes(),old)

if __name__=='__main__': unittest.main()
