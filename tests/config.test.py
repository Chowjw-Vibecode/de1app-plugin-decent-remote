#!/usr/bin/env python3
"""Fresh configuration and native-loader-shaped startup, entirely local/mocked.
Run with Python 3. Optional TCLSH and TCLLIBPATH select a Tcl/Tcllib runtime.
"""
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
GENERATOR = ROOT / 'tools' / 'create_config.py'


class ConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='decent-config-test-')
        self.root = Path(self.temp.name)
        self.output = self.root / 'settings.tdb'

    def tearDown(self):
        self.temp.cleanup()

    def create(self, *args):
        return subprocess.run([sys.executable, str(GENERATOR), '--output', str(self.output), *args], capture_output=True, text=True)

    def values(self):
        return dict(line.split(' ', 1) for line in self.output.read_text(encoding='utf8').splitlines())

    def startup(self, data=None):
        # No real wibble listener, native BLE, app launch or device connection.
        script = r'''
lassign $argv plugin config root
package provide wibble 0.4
namespace eval ::wibble {
    variable zonehandlers {}
    proc listen {port args} {incr ::listen_calls; return mock_listener}
    proc handle {prefix cmd args} {variable zonehandlers; lappend zonehandlers $prefix $cmd $args}
}
proc homedir {} {return $::test_root}
proc plugin_directory {} {return plugins}
proc save_plugin_settings {args} {error "new configuration must not need a legacy migration"}
set ::test_root $root
set ::listen_calls 0
set ::hardware_calls 0
foreach name {start_idle start_sleep start_espresso start_water start_steam start_flush userdata_append} {
    proc ::$name {args} {incr ::hardware_calls; error "unexpected hardware call"}
}
proc decentscale_enable_lcd {} {incr ::hardware_calls}
proc decentscale_disable_lcd {{poweroff 1}} {incr ::hardware_calls}
set ::settings(enabled_plugins) {decent_remote}
# Classic loader: populate settings array before sourcing the plugin.
namespace eval ::plugins::decent_remote {variable settings; array set settings {}}
set f [open $config r]; fconfigure $f -encoding utf-8
array set ::plugins::decent_remote::settings [read $f]; close $f
source $plugin
::plugins::decent_remote::main
if {!$::plugins::decent_remote::started || $::listen_calls != 1 || $::hardware_calls != 0} {error "startup side effects"}
if {[info exists ::plugins::decent_remote::settings(allow_start)]} {error "obsolete remote start option"}
puts "OK $::plugins::decent_remote::settings(hds_enabled) $::plugins::decent_remote::hds::installed"
'''
        if data is not None:
            self.output.write_text(data, encoding='utf8')
        runner = self.root / 'startup.tcl'
        runner.write_text(script, encoding='utf8')
        tcl = os.environ.get('TCLSH') or shutil.which('tclsh8.6') or shutil.which('tclsh')
        self.assertIsNotNone(tcl, 'Install Tcl/Tcllib or set TCLSH')
        env = os.environ.copy()
        result = subprocess.run([tcl, str(runner), str(ROOT / 'plugin.tcl'), str(self.output), str(self.root)], capture_output=True, text=True, env=env)
        self.assertEqual(result.returncode, 0, 'Mock startup failed (details withheld to avoid printing configuration)')
        return result.stdout.strip()

    def test_fresh_default_config(self):
        result = self.create()
        self.assertEqual(result.returncode, 0)
        values = self.values()
        self.assertEqual(values['token'], 'admin1234')
        self.assertEqual({k: values[k] for k in ('port', 'hds_enabled')}, {'port': '8888', 'hds_enabled': '0'})
        self.assertNotIn(values['token'], result.stdout + result.stderr)
        if os.name == 'posix':
            self.assertEqual(stat.S_IMODE(self.output.stat().st_mode), 0o600)

    def test_existing_configuration_not_overwritten(self):
        self.output.write_text('retain this exact file', encoding='utf8')
        result = self.create()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.output.read_text(), 'retain this exact file')

    def test_invalid_port_creates_nothing(self):
        for port in ('0', '1023', '65536', 'invalid'):
            self.assertNotEqual(self.create('--port', port).returncode, 0)
            self.assertFalse(self.output.exists())

    def test_explicit_options(self):
        self.assertEqual(self.create('--port', '9001', '--hds').returncode, 0)
        self.assertEqual(self.values()['port'], '9001')
        self.assertEqual(self.values()['hds_enabled'], '1')
        self.assertNotIn('allow_start', self.values())

    def test_unique_secrets(self):
        self.create('--random-key'); first = self.values()['token']
        self.assertRegex(first, r'^[0-9a-f]{64}$')
        self.output.unlink(); self.create('--random-key')
        self.assertNotEqual(first, self.values()['token'])

    def test_fresh_start_without_legacy_rest(self):
        self.create()
        self.assertFalse((self.root / 'plugins' / 'advanced_rest_api').exists())
        self.assertEqual(self.startup(), 'OK 0 0')

    def test_existing_hds_enable_is_preserved(self):
        self.create('--hds')
        self.assertEqual(self.startup(), 'OK 1 1')

    def test_missing_hds_key_defaults_off(self):
        self.create()
        data = re.sub(r'^hds_enabled .*\n', '', self.output.read_text(), flags=re.M)
        self.assertEqual(self.startup(data), 'OK 0 0')


if __name__ == '__main__':
    unittest.main()
