#!/usr/bin/env python3
"""Prepare, but never publish, a stable signed Sparkle feed.

Use the pinned Sparkle signing/generation tools with an explicit seed file.
Private tool diagnostics are deliberately not forwarded: malformed seed errors
in upstream tools can include key material. No Keychain fallback is allowed.
"""
import argparse
import base64
import json
from pathlib import Path, PurePosixPath
import plistlib
import posixpath
import stat
import re
import shutil
import subprocess
import tempfile
from urllib.parse import quote
import xml.etree.ElementTree as ET
import zipfile

S = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
REPO = 'https://github.com/bhanurp/MergeOwl'
STABLE = re.compile(r'0|[1-9][0-9]*')


def version_tuple(version):
    parts = version.split('.')
    if len(parts) != 3 or not all(STABLE.fullmatch(p) for p in parts):
        raise ValueError('Only three-component stable versions are permitted')
    return tuple(map(int, parts))


def validate_release(release, filename, size):
    tag = release.get('tag_name', '')
    if not tag.startswith('v'):
        raise ValueError('Expected stable v-prefixed release tag')
    version_tuple(tag[1:])
    if release.get('draft') is not False or release.get('prerelease') is not False:
        raise ValueError('Draft and prerelease updates are forbidden')
    assets = [a for a in release.get('assets', []) if a.get('name') == filename]
    expected = f'{REPO}/releases/download/{tag}/{quote(filename)}'
    if len(assets) != 1 or assets[0].get('size') != size or size <= 0 or assets[0].get('browser_download_url') != expected:
        raise ValueError('Missing, duplicate, mutable or mismatched release asset')
    return assets[0]


def validate_history(root, version, build):
    if build <= 0:
        raise ValueError('Build number must be positive')
    items = root.findall('./channel/item')
    if root.tag != 'rss' or len(root.findall('channel')) != 1:
        raise ValueError('Expected a single RSS channel')
    seen_builds, seen_versions = set(), set()
    for item in items:
        old_build = int(item.findtext(S + 'version', '0'))
        old_version = item.findtext(S + 'shortVersionString', '')
        if old_build in seen_builds or old_version in seen_versions:
            raise ValueError('Duplicate historical feed entry')
        seen_builds.add(old_build)
        seen_versions.add(old_version)
        if old_build <= 0 or old_build >= build or version_tuple(old_version) >= version_tuple(version):
            raise ValueError('Duplicate or decreasing version/build; publication reruns are not allowed')
    return items


def validate_item(item, version, build, asset):
    enclosure = item.find('enclosure')
    if (item.findtext(S + 'version') != str(build)
            or item.findtext(S + 'shortVersionString') != version
            or item.findtext(S + 'minimumSystemVersion') != '14.0'
            or item.find(S + 'criticalUpdate') is not None
            or item.find(S + 'channel') is not None
            or enclosure is None
            or enclosure.get('url') != asset['browser_download_url']
            or enclosure.get('length') != str(asset['size'])
            or not enclosure.get(S + 'edSignature')):
        raise ValueError('Generated feed entry violates release metadata or no-interruption policy')


def archive_info(archive):
    with zipfile.ZipFile(archive) as z:
        names = z.namelist()
        if len(set(names)) != len(names) or sum(i.file_size for i in z.infolist()) > 1_000_000_000:
            raise ValueError('Invalid or oversized archive')
        for name in names:
            path = PurePosixPath(name)
            if path.is_absolute() or '..' in path.parts or not path.parts:
                raise ValueError('Archive contains an unsafe path')
            metadata = path.parts[0] == '__MACOSX'
            if metadata:
                if name == '__MACOSX/' and not stat.S_ISLNK(z.getinfo(name).external_attr >> 16):
                    continue
                # ditto --sequesterRsrc writes AppleDouble resource-fork entries.
                if len(path.parts) < 2 or path.parts[1] not in ['MergeOwl.app', '._MergeOwl.app']:
                    raise ValueError('Invalid AppleDouble metadata path')
                if not name.endswith('/') and not path.name.startswith('._'):
                    raise ValueError('Unexpected executable/data in metadata directory')
            elif path.parts[0] != 'MergeOwl.app':
                raise ValueError('Archive must contain only one MergeOwl.app')
            entry = z.getinfo(name)
            if stat.S_ISLNK(entry.external_attr >> 16):
                target = z.read(name).decode('utf-8')
                resolved = posixpath.normpath(posixpath.join(str(path.parent), target))
                if metadata or target.startswith('/') or not resolved.startswith('MergeOwl.app/'):
                    raise ValueError('Archive symlink escapes the app bundle')
        return plistlib.loads(z.read('MergeOwl.app/Contents/Info.plist'))


def run_private(command):
    result = subprocess.run(list(map(str, command)), capture_output=True)
    if result.returncode:
        raise ValueError('Sparkle signing or feed verification failed; no feed was published')
    return result.stdout.decode().strip()


def prepare(args):
    archive = args.archive.resolve()
    info = archive_info(archive)
    release = json.loads(args.release_json.read_text())
    asset = validate_release(release, archive.name, archive.stat().st_size)
    version = release['tag_name'][1:]
    build = int(info['CFBundleVersion'])
    public_key = args.public_key.strip()
    if len(base64.b64decode(public_key, validate=True)) != 32:
        raise ValueError('Expected a 32-byte public update key')
    if (info.get('CFBundleShortVersionString') != version
            or info.get('CFBundleIdentifier') != 'io.bhanurp.prpulse'
            or info.get('CFBundleExecutable') != 'MergeOwl'
            or info.get('LSMinimumSystemVersion') != '14.0'
            or info.get('SUPublicEDKey') != public_key
            or info.get('SUFeedURL') != REPO + '/releases/latest/download/appcast.xml'
            or not all(info.get(k) is True for k in ['PRPulseUpdatesEnabled', 'SURequireSignedFeed', 'SUVerifyUpdateBeforeExtraction'])):
        raise ValueError('Archive version, identity, OS or embedded update trust does not match')
    if args.output.exists():
        raise ValueError('Output already exists; refusing to replace a prepared feed')
    derive = Path(__file__).with_name('update_public_key.swift')
    derived_key = run_private(['swift', derive, args.ed_key_file])
    if derived_key != public_key:
        raise ValueError('Signing key does not match embedded public key')
    signer = args.sparkle_bin / 'sign_update'
    generator = args.sparkle_bin / 'generate_appcast'
    old_items = []
    if args.previous_feed:
        run_private([signer, '--verify', '--ed-key-file', args.ed_key_file, args.previous_feed])
        old_root = ET.parse(args.previous_feed).getroot()
        old_items = validate_history(old_root, version, build)
    else:
        validate_history(ET.fromstring('<rss><channel/></rss>'), version, build)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='mergeowl-appcast-') as scratch:
        stage = Path(scratch)
        shutil.copyfile(archive, stage / archive.name)
        if args.previous_feed:
            shutil.copyfile(args.previous_feed, stage / 'appcast.xml')
        run_private([generator, '--ed-key-file', args.ed_key_file,
                     '--download-url-prefix', asset['browser_download_url'].rsplit('/', 1)[0] + '/',
                     '--link', f'{REPO}/releases/tag/{release["tag_name"]}',
                     '--maximum-versions', '0', '--maximum-deltas', '0', '--versions', str(build), stage])
        feed = stage / 'appcast.xml'
        run_private([signer, '--verify', '--ed-key-file', args.ed_key_file, feed])
        root = ET.parse(feed).getroot()
        new_items = root.findall('./channel/item')
        current = [i for i in new_items if i.findtext(S + 'version') == str(build)]
        if len(current) != 1 or len(new_items) != len(old_items) + 1:
            raise ValueError('Generated feed dropped history or duplicated updates')
        validate_item(current[0], version, build, asset)
        # Older OS/architecture-compatible entries must survive unchanged.
        for old in old_items:
            if not any(ET.tostring(i) == ET.tostring(old) for i in new_items):
                raise ValueError('Generated feed changed a historical entry')
        enclosure = current[0].find('enclosure')
        run_private([signer, '--verify', '--ed-key-file', args.ed_key_file,
                     archive, enclosure.get(S + 'edSignature')])
        # Exclusive creation also prevents a competing prepare process overwriting output.
        with args.output.open('xb') as target:
            target.write(feed.read_bytes())
    print('Signed appcast prepared and verified; nothing published.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['archive', 'release-json', 'sparkle-bin', 'ed-key-file', 'output']:
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--public-key', required=True)
    parser.add_argument('--previous-feed', type=Path)
    args = parser.parse_args()
    try:
        prepare(args)
    except (ValueError, OSError, KeyError, zipfile.BadZipFile, ET.ParseError, plistlib.InvalidFileException):
        parser.exit(1, 'Appcast preparation failed validation; no feed was published.\n')


if __name__ == '__main__':
    main()
