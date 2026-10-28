import copy
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('exporter', Path(__file__).parents[1] / 'tools/export_summary.py')
exporter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(exporter)
BASE = dict(schema=1, generated_at='2026-10-27T00:00:00Z', scope='reporting installations; not people or all users', total_installations=2, active_30d=1, countries=[dict(country='CN', installations=2, active_30d=1)])

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

if __name__=='__main__': unittest.main()
