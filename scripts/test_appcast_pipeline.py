#!/usr/bin/env python3
"""Real Sparkle signing-tool smoke test with throwaway, never-launched bundles."""
import argparse
import base64
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('prepare_appcast', ROOT / 'scripts/prepare_appcast.py')
feed = importlib.util.module_from_spec(spec)
spec.loader.exec_module(feed)


def run(*args):
    result = subprocess.run(list(map(str, args)), capture_output=True)
    if result.returncode:
        raise RuntimeError('Fixture command failed: ' + str(args[0]))
    return result.stdout.decode().strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sparkle-bin', required=True, type=Path)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='mergeowl-feed-fixture-') as scratch:
        stage = Path(scratch)
        seed = stage / 'test-seed'
        seed.write_text(base64.b64encode(os.urandom(32)).decode())
        seed.chmod(0o600)
        public = run('swift', ROOT / 'scripts/update_public_key.swift', seed)
        previous = None
        for version, build in [('0.3.0', 100), ('0.3.1', 101)]:
            work = stage / version
            bundle = work / 'MergeOwl.app'
            (bundle / 'Contents/MacOS').mkdir(parents=True)
            # This fixture is metadata/signing input only and is NEVER launched.
            shutil.copyfile('/bin/echo', bundle / 'Contents/MacOS/MergeOwl')
            (bundle / 'Contents/MacOS/MergeOwl').chmod(0o755)
            info = {'CFBundleExecutable': 'MergeOwl', 'CFBundleIdentifier': 'io.bhanurp.prpulse',
                    'CFBundlePackageType': 'APPL', 'CFBundleVersion': str(build),
                    'CFBundleShortVersionString': version, 'LSMinimumSystemVersion': '14.0',
                    'SUPublicEDKey': public, 'SUFeedURL': feed.REPO + '/releases/latest/download/appcast.xml',
                    'PRPulseUpdatesEnabled': True, 'SURequireSignedFeed': True, 'SUVerifyUpdateBeforeExtraction': True}
            (bundle / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
            run('codesign', '--force', '--sign', '-', bundle)
            archive = work / f'MergeOwl-{version}-macOS-universal.zip'
            run('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', bundle, archive)
            metadata = work / 'release.json'
            tag = 'v' + version
            metadata.write_text(json.dumps({'tag_name': tag, 'draft': False, 'prerelease': False, 'assets': [{
                'name': archive.name, 'size': archive.stat().st_size,
                'browser_download_url': f'{feed.REPO}/releases/download/{tag}/{archive.name}'}]}))
            options = SimpleNamespace(archive=archive, release_json=metadata, sparkle_bin=args.sparkle_bin.resolve(),
                ed_key_file=seed, public_key=public, previous_feed=previous, output=work / 'prepared/appcast.xml')
            feed.prepare(options)
            previous = options.output
        # Simulate a signed feed already uploaded before a failed promotion.
        # Recovery must verify and preserve those exact immutable bytes.
        import xml.etree.ElementTree as ET
        tree = ET.parse(previous)
        ET.SubElement(tree.find('./channel/item'), 'description').text = 'Published feed must remain byte-for-byte immutable'
        tree.write(previous, encoding='utf-8', xml_declaration=True)
        run(args.sparkle_bin / 'sign_update', '--ed-key-file', seed, previous)
        options.verify_existing_feed = previous
        options.output = stage / 'recovered.xml'
        feed.prepare(options)
        if options.output.read_bytes() != previous.read_bytes():
            raise RuntimeError('Recovery regenerated the already published immutable feed')
        options.verify_existing_feed = None
        # A rerun cannot replace an existing output. A duplicated historical
        # version/build also fails even with a new output filename.
        for output in [previous, stage / 'duplicate.xml']:
            options.output = output
            options.previous_feed = previous
            try:
                feed.prepare(options)
            except ValueError:
                pass
            else:
                raise RuntimeError('Duplicate publication unexpectedly accepted')
        original = previous.read_bytes()
        tampered = original.replace(b'>101</', b'>999</', 1)
        if original == tampered: raise RuntimeError('Could not modify signed feed content')
        previous.write_bytes(tampered)
        options.output = stage / 'bad-history.xml'
        try:
            feed.prepare(options)
        except ValueError as error:
            if 'Sparkle signing or feed verification failed' not in str(error):
                raise RuntimeError('Tampered feed did not reach signature verification') from error
        else:
            raise RuntimeError('Unauthenticated previous feed unexpectedly accepted')
    print('Real Sparkle archive/feed signatures, history retention and rerun/tamper rejection passed.')


if __name__ == '__main__':
    main()
