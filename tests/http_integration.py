#!/usr/bin/env python3
"""Real loopback HTTP with the device's wibble source; hardware is always mocked.
Usage: python3 http_integration.py --wibble /path/wibble.tcl --tcl /path/tclsh8.6
"""
import argparse
import http.client
import json
import pathlib
import subprocess
import tempfile
import urllib.parse

p = argparse.ArgumentParser()
p.add_argument('--wibble', required=True, type=pathlib.Path)
p.add_argument('--tcl', default='tclsh8.6')
p.add_argument('--tcllib', default='')
a = p.parse_args()
base = pathlib.Path(__file__).resolve().parent.parent
# Tcl arguments travel via argv, never executable string interpolation.
script = r'''
lassign $argv wibble root plugin tcllib
if {$tcllib ne {}} {lappend auto_path $tcllib}
source $wibble
source [file join $plugin core.tcl]
source [file join $plugin transport.tcl]
source [file join $plugin profiles.tcl]
source [file join $plugin legacy.tcl]
set ::plugins::decent_remote::directory $plugin
set ::plugins::decent_remote::api::token abcdefghijklmnopqrstuvwxyz
set ::plugins::decent_remote::api::root $root
set ::plugins::decent_remote::api::allow_start 1
set ::plugins::decent_remote::api::adapter fake
set ::fake_calls 0
proc fake {op payload} {
    incr ::fake_calls
    switch $op {
        legacy.status {return {is_active true espresso_count 2 steaming_count 3}}
        legacy.details {return {state Espresso espresso_elapsed {0 1 2} espresso_pressure {1 2 3}}}
        legacy.sdb {return {{filename 1234 shot_desc 测试 grinder_dose_weight 19}}}
    }
    return [dict create operation $op recipe $payload calls $::fake_calls]
}
::wibble::handle / ::plugins::decent_remote::http::handle
set ::plugins::decent_remote::http::bind_address 127.0.0.1
set listener [::wibble::listen 0 ::plugins::decent_remote::http::socket]
puts [lindex [fconfigure $listener -sockname] end]
flush stdout
after 60000 {set done 1}
vwait done
close $listener
'''
with tempfile.TemporaryDirectory(prefix='decent-http-test-') as td:
    root = pathlib.Path(td)
    (root / 'profiles').mkdir()
    (root / 'history').mkdir()
    (root / 'history_v2').mkdir()
    (root / 'history' / '1234.shot').write_text('profile_title 中文', encoding='utf8')
    (root / 'history_v2' / '1234.json').write_text('{"title":"中文"}', encoding='utf8')
    (root / 'profiles' / '中文.tcl').write_text('profile_title 中文\n', encoding='utf8')
    server = root / 'server.tcl'
    server.write_text(script, encoding='utf8')
    proc = subprocess.Popen([a.tcl, str(server), str(a.wibble.resolve()), str(root), str(base), a.tcllib], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        line = proc.stdout.readline().strip()
        if not line.isdigit():
            raise RuntimeError(f'Server did not start: {line} {proc.stderr.read()}')
        port = int(line)
        requests = 0
        def request(method, path, body=None, request_id=None, auth=True, extra=None):
            global requests
            requests += 1
            headers = {'Connection': 'close'}
            if auth:
                headers['Authorization'] = 'Bearer abcdefghijklmnopqrstuvwxyz'
            if request_id:
                headers['X-Request-ID'] = request_id
            if body is not None:
                body = body.encode('utf8')
                headers['Content-Type'] = 'application/json'
            headers.update(extra or {})
            c = http.client.HTTPConnection('127.0.0.1', port, timeout=3)
            c.request(method, path, body, headers)
            r = c.getresponse()
            result = r.status, r.read(), dict(r.getheaders())
            c.close()
            assert result[2].get('connection') == 'close', result
            assert result[2].get('cache-control') == 'no-store', result
            assert result[2].get('referrer-policy') == 'no-referrer', result
            return result
        def expect(code, method, path, body=None, request_id=None, auth=True, extra=None):
            result = request(method, path, body, request_id, auth, extra)
            assert result[0] == code, (method, path, result)
            return result
        expect(401, 'GET', '/api/v1/status', auth=False)
        expect(200, 'GET', '/api/v1/status')
        name = urllib.parse.quote('中文.tcl')
        result = expect(200, 'GET', '/api/profile/' + name)
        assert result[1].decode('utf8') == 'profile_title 中文\n'
        result = expect(200, 'PUT', '/api/profile/' + name, request_id='select-001')
        assert result[1].decode('utf8') == '中文.tcl'
        expect(400, 'PUT', '/api/profile/' + name, '{}', 'select-002')
        result = expect(200, 'POST', '/api/v1/recipe', '{"dose_g":18,"title":"中文"}', 'recipe-001')
        assert json.loads(result[1])['recipe']['title'] == '中文'
        expect(409, 'POST', '/api/v1/recipe', '{"dose_g":18}', 'recipe-001')
        expect(400, 'POST', '/api/v1/recipe', '', 'recipe-002')
        expect(405, 'PATCH', '/api/v1/recipe', '{"dose_g":18}', 'recipe-003')
        expect(400, 'GET', '/api/v1/status?ignored=true')
        expect(400, 'GET', '/api/profile/%FF.tcl')
        expect(400, 'GET', '/api/profile/%2e%2e/secret.tcl')
        first_count = int(json.loads(expect(200, 'GET', '/api/v1/status')[1])['calls'])
        for action in ('espresso', 'flush', 'steam', 'hotwater'):
            result = expect(403, 'POST', '/api/v1/machine/' + action, '{}', 'start-' + action)
            assert json.loads(result[1])['error'] == 'start_disabled'
            expect(409, 'POST', '/api/v1/machine/' + action, '{}', 'start-' + action)
        result = expect(200, 'GET', '/api/v1/status')
        assert int(json.loads(result[1])['calls']) == first_count + 1
        token = 'abcdefghijklmnopqrstuvwxyz'
        expect(403, 'GET', '/api/status', auth=False)
        result = expect(200, 'GET', '/api/status?auth=' + token, auth=False)
        assert json.loads(result[1])['is_active'] == 'true'
        result = expect(200, 'GET', '/api/status/details?auth=' + token, auth=False)
        assert json.loads(result[1])['espresso_pressure'] == [1, 2, 3]
        expect(400, 'GET', '/api/status?auth=' + token + '&auth=' + token, auth=False)
        expect(200, 'POST', '/api/status?auth=' + token, '{"active":false}', auth=False)
        expect(200, 'GET', '/api/profile/?auth=' + token, auth=False)
        expect(200, 'POST', '/api/profile?auth=' + token, 'profile_title 新曲线', auth=False, extra={'filename': urllib.parse.quote('新曲线.tcl')})
        result = expect(200, 'GET', '/api/profile/' + urllib.parse.quote('新曲线.tcl') + '?auth=' + token + '&download=true', auth=False)
        assert result[1].decode('utf8') == 'profile_title 新曲线'
        expect(422, 'POST', '/api/profile', 'profile_title bad stress_test 1', extra={'filename': 'bad.tcl'})
        expect(422, 'POST', '/api/profile', 'profile_title bad', extra={'filename': '../bad.tcl'})
        expect(200, 'GET', '/api/shot/')
        result = expect(200, 'GET', '/api/shot/1234.shot?auth=' + token + '&download=true', auth=False)
        assert result[1].decode('utf8') == 'profile_title 中文'
        result = expect(200, 'GET', '/api/v2/shot/1234')
        assert json.loads(result[1])['title'] == '中文'
        expect(200, 'PUT', '/api/v2/shot/1234')
        result = expect(200, 'GET', '/api/v2/shots')
        assert json.loads(result[1])[0]['shot_desc'] == '测试'
        expect(200, 'GET', '/api/flush')
        expect(200, 'GET', '/api/help')
        result = expect(200, 'GET', '/?auth=' + token, auth=False)
        assert b'id="connect-button"' in result[1]
        expect(403, 'POST', '/api/status', '{"active":true}', extra={'Origin': 'http://evil.local'})
        expect(200, 'POST', '/api/status', '{"active":true}', extra={'Origin': f'http://127.0.0.1:{port}'})
        # Verify actual closure, not merely a Connection response header.
        import socket
        requests += 1
        with socket.create_connection(('127.0.0.1', port), timeout=3) as sock:
            sock.sendall((f'GET /api/v1/status HTTP/1.1\r\nHost: localhost\r\nAuthorization: Bearer {token}\r\nConnection: keep-alive\r\n\r\n').encode())
            received = b''
            while True:
                chunk = sock.recv(65536)
                if not chunk: break
                received += chunk
            assert b'200' in received.split(b'\r\n')[0]
        # Parser-level failures happen before the route; never echo/log secrets.
        for raw in (
            f'POST /api/status?auth={token} HTTP/1.1\r\nHost: localhost\r\nAuthorization: Bearer {token}\r\n\r\n',
            f'POST /api/status HTTP/1.1\r\nHost: localhost\r\nAuthorization: Bearer {token}\r\nContent-Length: nope\r\n\r\n',
            'BAD\r\n\r\n',
        ):
            requests += 1
            with socket.create_connection(('127.0.0.1', port), timeout=3) as sock:
                sock.sendall(raw.encode())
                received = b''
                while chunk := sock.recv(65536):
                    received += chunk
                assert b'400' in received.split(b'\r\n')[0], received
                assert token.encode() not in received
                assert b'\r\n\r\n' in received, repr(received)
                body = received.split(b'\r\n\r\n', 1)[1]
                assert json.loads(body) == {'error': 'invalid_http_request'}
        expect(200, 'GET', '/api/v1/status')
        # Body arrives later: exercise the real asynchronous reader, not only
        # requests already buffered when the connection is accepted.
        import time
        requests += 1
        with socket.create_connection(('127.0.0.1', port), timeout=3) as sock:
            sock.sendall((f'POST /api/status HTTP/1.1\r\nHost: localhost\r\nAuthorization: Bearer {token}\r\nContent-Type: application/json\r\nContent-Length: 15\r\n\r\n').encode())
            time.sleep(0.03)
            sock.sendall(b'{"active":true}')
            received = b''
            while chunk := sock.recv(65536):
                received += chunk
            assert b'200' in received.split(b'\r\n')[0], received
        print(f'PASS: {requests} real HTTP requests; legacy routes, UTF-8, native-call mocks, replay protection, socket closure, delayed bodies and secret-free malformed requests.')
    finally:
        proc.terminate()
        stdout, stderr = proc.communicate(timeout=5)
        assert 'abcdefghijklmnopqrstuvwxyz' not in stdout + stderr, 'Access key leaked to server output'
