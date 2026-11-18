#!/usr/bin/env python3
"""Exercise Sparkle with disposable apps and keys. Never install MergeOwl.

Loopback HTTP is permitted ONLY in this fixture's Info.plist. Real app
configuration requires HTTPS and a signed feed. No production Keychain access.
"""
import argparse
import base64
import contextlib
import functools
import http.server
import json
import os
from pathlib import Path
import plistlib
import shutil
import socket
import subprocess
import tempfile
import threading
import time
import uuid
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
S = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'


def run(*args, **kwargs):
    result = subprocess.run(list(map(str, args)), capture_output=True, **kwargs)
    if result.returncode:
        raise RuntimeError('Fixture command failed: ' + str(args[0]) + '\n' + result.stderr.decode()[-2000:])
    return result.stdout.decode().strip()


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


class InterruptingHandler(QuietHandler):
    def do_GET(self):
        if self.path.endswith('.zip'):
            archive = Path(self.translate_path(self.path))
            data = archive.read_bytes()
            self.send_response(200)
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data[:len(data) // 2])
            self.wfile.flush()
            self.close_connection = True
            self.connection.shutdown(socket.SHUT_RDWR)
            self.connection.close()
        else:
            super().do_GET()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sparkle-root', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--case', choices=['upgrade', 'tampered', 'wrong-key', 'tampered-feed', 'unsigned', 'equal', 'downgrade', 'offline', 'interrupted', 'unwritable'], default='upgrade')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    output = args.output.resolve()
    sparkle = args.sparkle_root.resolve()
    framework = sparkle / 'Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework'
    # All private seeds, apps and downloaded archives are temporary; evidence
    # outside the temporary root contains only events/public metadata.
    with tempfile.TemporaryDirectory(prefix='mergeowl-signed-upgrade-') as temp:
        scratch = Path(temp)
        seed = scratch / 'test-seed'
        seed.write_text(base64.b64encode(os.urandom(32)).decode())
        seed.chmod(0o600)
        public = run('swift', ROOT / 'scripts/update_public_key.swift', seed)
        compiled = scratch / 'Probe'
        run('swiftc', '-parse-as-library', ROOT / 'Tests/UpdaterTests/UpgradeProbe.swift',
            ROOT / 'Sources/PRPulseApp/Services/AppUpdateService.swift', ROOT / 'Sources/PRPulseApp/Services/SparkleUpdateDriver.swift',
            '-F', framework.parent, '-framework', 'Sparkle',
            '-Xlinker', '-rpath', '-Xlinker', '@executable_path/../Frameworks', '-o', compiled)
        web = scratch / 'web'
        web.mkdir()
        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(InterruptingHandler if args.case == 'interrupted' else QuietHandler, directory=str(web)))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            feed_url = f'http://127.0.0.1:{server.server_port}/appcast.xml'
            bundle_id = 'test.mergeowl.upgrade.' + uuid.uuid4().hex
            (output / 'bundle-id.txt').write_text(bundle_id)
            def app(path, build):
                (path / 'Contents/MacOS').mkdir(parents=True)
                shutil.copy2(compiled, path / 'Contents/MacOS/Probe')
                info = {'CFBundleExecutable': 'Probe', 'CFBundleIdentifier': bundle_id,
                        'CFBundleName': 'MergeOwl disposable update probe', 'CFBundlePackageType': 'APPL',
                        'CFBundleVersion': str(build), 'CFBundleShortVersionString': f'0.0.{build}',
                        'LSMinimumSystemVersion': '14.0', 'LSUIElement': True,
                        'SUFeedURL': feed_url, 'SUPublicEDKey': public,
                        'SUVerifyUpdateBeforeExtraction': True, 'SURequireSignedFeed': True,
                        'SUEnableAutomaticChecks': False, 'SUAutomaticallyUpdate': True, 'SUAllowsAutomaticUpdates': True,
                        'NSAppTransportSecurity': {'NSAllowsLocalNetworking': True, 'NSAllowsArbitraryLoads': True}}
                (path / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
                run('bash', ROOT / 'scripts/package_sparkle.sh', path, framework)
                run('codesign', '--force', '--deep', '--sign', '-', path)
                run('codesign', '--verify', '--deep', '--strict', path)
            install = scratch / 'install/MergeOwl.app'
            newer = scratch / 'new/MergeOwl.app'
            app(install, 1)
            app(newer, 2)
            archive = web / 'MergeOwl-0.0.2.zip'
            run('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', newer, archive)
            run(sparkle / 'bin/generate_appcast', '--ed-key-file', seed,
                '--download-url-prefix', feed_url.rsplit('/', 1)[0] + '/',
                '--maximum-deltas', '0', '--maximum-versions', '0', web)
            feed = web / 'appcast.xml'
            run(sparkle / 'bin/sign_update', '--verify', '--ed-key-file', seed, feed)
            if args.case in ['wrong-key', 'unsigned', 'equal', 'downgrade']:
                tree = ET.parse(feed)
                if args.case == 'wrong-key':
                    wrong_seed = scratch / 'wrong-seed'
                    wrong_seed.write_text(base64.b64encode(os.urandom(32)).decode())
                    wrong_seed.chmod(0o600)
                    signature = run(sparkle / 'bin/sign_update', '--ed-key-file', wrong_seed, '-p', archive)
                    tree.find('./channel/item/enclosure').set(S + 'edSignature', signature)
                elif args.case == 'unsigned':
                    del tree.find('./channel/item/enclosure').attrib[S + 'edSignature']
                else:
                    tree.find('./channel/item/' + S + 'version').text = '1' if args.case == 'equal' else '0'
                tree.write(feed, encoding='utf-8', xml_declaration=True)
                run(sparkle / 'bin/sign_update', '--ed-key-file', seed, feed)
                run(sparkle / 'bin/sign_update', '--verify', '--ed-key-file', seed, feed)
            elif args.case == 'tampered':
                with archive.open('ab') as target: target.write(b'changed after signing')
            elif args.case == 'tampered-feed':
                original = feed.read_bytes()
                changed = original.replace(b'>2</sparkle:version>', b'>9</sparkle:version>', 1)
                if changed == original: raise RuntimeError('Could not modify signed feed version')
                feed.write_bytes(changed)
            elif args.case == 'offline':
                server.shutdown()
                server.server_close()
            if args.case == 'unwritable': install.parent.chmod(0o555)
            env = dict(os.environ, MERGEOWL_PROBE_LOG=str(output / 'upgrade-events.log'))
            process = subprocess.Popen([str(install / 'Contents/MacOS/Probe')], env=env,
                                       stdout=subprocess.DEVNULL, stderr=(output / 'framework-stderr.log').open('wb'))
            try:
                process.wait(timeout=60)
            except subprocess.TimeoutExpired:
                process.terminate()
                process.wait(timeout=5)
                raise RuntimeError('Isolated updater host timed out; no pass claimed')
            if args.case == 'upgrade':
                deadline = time.monotonic() + 25
                while time.monotonic() < deadline:
                    if plistlib.loads((install / 'Contents/Info.plist').read_bytes())['CFBundleVersion'] == '2':
                        break
                    time.sleep(0.25)
                else:
                    raise RuntimeError('Natural-quit replacement did not finish; inspect fixture events')
            else:
                events = (output / 'upgrade-events.log').read_text()
                expected = ('no-update' if args.case in ['downgrade', 'equal'] else 'attention-without-focus' if args.case == 'unwritable' else 'error:')
                rejected = expected in events or (args.case == 'unsigned' and 'no-update' in events)
                if not rejected or 'ready:' in events or 'timeout' in events:
                    raise RuntimeError('Negative case did not fail safely; inspect fixture events')
                if plistlib.loads((install / 'Contents/Info.plist').read_bytes())['CFBundleVersion'] != '1':
                    raise RuntimeError('Rejected update modified the installed test host')
            run('codesign', '--verify', '--deep', '--strict', install)
            env['MERGEOWL_PROBE_VERIFY'] = '1'
            run(install / 'Contents/MacOS/Probe', env=env, timeout=15)
            events = (output / 'upgrade-events.log').read_text()
            required = ['launch:1', 'continuity:preserved-fixture']
            if args.case == 'upgrade': required += ['ready:2', 'launch:2']
            if not all(e in events for e in required):
                raise RuntimeError('Missing staged/launch/persistence evidence')
            (output / 'result.json').write_text(json.dumps({'case': args.case, 'result': 'pass',
                'preferences': 'preserved', 'production_app_touched': False,
                'limits': ['loopback HTTP test feed', 'ad-hoc test host', 'no production Keychain or Developer ID continuity test']}, indent=2))
            # Remove only this unique fixture's defaults, never application data.
            run('defaults', 'delete', bundle_id)
        finally:
            if (scratch / 'install').exists(): (scratch / 'install').chmod(0o755)
            if (output / 'bundle-id.txt').exists():
                subprocess.run(['defaults', 'delete', (output / 'bundle-id.txt').read_text()], capture_output=True)
            server.shutdown()
    print('Isolated Sparkle case passed: ' + args.case)


if __name__ == '__main__':
    main()
