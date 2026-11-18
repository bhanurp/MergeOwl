import importlib.util
from pathlib import Path
import tempfile
import plistlib
import zipfile
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('prepare_appcast', ROOT / 'scripts/prepare_appcast.py')
appcast = importlib.util.module_from_spec(spec)
spec.loader.exec_module(appcast)


class ReleasePolicyTests(unittest.TestCase):
    def release(self, **changes):
        result = {'tag_name': 'v0.3.0', 'draft': False, 'prerelease': False,
                  'assets': [{'name': 'MergeOwl-v0.3.0-universal.zip', 'size': 100,
                              'browser_download_url': 'https://github.com/bhanurp/MergeOwl/releases/download/v0.3.0/MergeOwl-v0.3.0-universal.zip'}]}
        result.update(changes)
        return result

    def test_zip_allows_appledouble_metadata_but_rejects_path_escape(self):
        with tempfile.TemporaryDirectory() as temp:
            archive = Path(temp) / 'update.zip'
            with zipfile.ZipFile(archive, 'w') as z:
                z.writestr('MergeOwl.app/Contents/Info.plist', plistlib.dumps({'CFBundleVersion': '100'}))
                z.writestr('__MACOSX/', b'')
                z.writestr('__MACOSX/MergeOwl.app/Contents/._Info.plist', b'AppleDouble fixture')
            self.assertEqual(appcast.archive_info(archive)['CFBundleVersion'], '100')
            with zipfile.ZipFile(archive, 'a') as z:
                z.writestr('../escape', b'no')
            with self.assertRaises(ValueError):
                appcast.archive_info(archive)

    def test_accepts_only_stable_immutable_release_asset(self):
        asset = appcast.validate_release(self.release(), 'MergeOwl-v0.3.0-universal.zip', 100)
        self.assertIn('/download/v0.3.0/', asset['browser_download_url'])
        for changes in [{'draft': True}, {'prerelease': True}, {'tag_name': 'v0.3.0-beta.1'}, {'tag_name': 'v0.3.0/evil'}]:
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                appcast.validate_release(self.release(**changes), 'MergeOwl-v0.3.0-universal.zip', 100)

    def test_rejects_missing_duplicate_mutable_or_wrong_length_assets(self):
        release = self.release()
        for assets in [[], release['assets'] * 2,
                       [dict(release['assets'][0], size=99)],
                       [dict(release['assets'][0], browser_download_url='https://github.com/bhanurp/MergeOwl/releases/latest/download/MergeOwl.zip')],
                       [dict(release['assets'][0], browser_download_url='https://evil.example/update.zip')]]:
            with self.subTest(assets=assets), self.assertRaises(ValueError):
                appcast.validate_release(self.release(assets=assets), 'MergeOwl-v0.3.0-universal.zip', 100)

    def test_feed_keeps_history_and_rejects_rerun_or_decreasing_build(self):
        feed = ET.fromstring('''<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
          <sparkle:version>101</sparkle:version><sparkle:shortVersionString>0.2.9</sparkle:shortVersionString>
          <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
          <enclosure url="https://github.com/bhanurp/MergeOwl/releases/download/v0.2.9/MergeOwl.zip" />
        </item></channel></rss>''')
        self.assertEqual(len(appcast.validate_history(feed, '0.3.0', 102)), 1)
        for version, build in [('0.2.9', 102), ('0.3.0', 101), ('0.3.0', 100), ('0.2.8', 102)]:
            with self.subTest(version=version, build=build), self.assertRaises(ValueError):
                appcast.validate_history(feed, version, build)

    def test_rejects_unsigned_incomplete_or_critical_generated_entries(self):
        item = ET.fromstring('''<item xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <sparkle:version>102</sparkle:version><sparkle:shortVersionString>0.3.0</sparkle:shortVersionString>
          <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
          <enclosure url="https://github.com/bhanurp/MergeOwl/releases/download/v0.3.0/a.zip" length="100" sparkle:edSignature="sig" />
        </item>''')
        asset = {'browser_download_url': item.find('enclosure').get('url'), 'size': 100}
        appcast.validate_item(item, '0.3.0', 102, asset)
        for mutation in ['signature', 'critical', 'minimum', 'channel', 'length']:
            entry = ET.fromstring(ET.tostring(item))
            if mutation == 'signature': del entry.find('enclosure').attrib[appcast.S + 'edSignature']
            if mutation == 'critical': ET.SubElement(entry, appcast.S + 'criticalUpdate')
            if mutation == 'channel': ET.SubElement(entry, appcast.S + 'channel').text = 'beta'
            if mutation == 'minimum': entry.find(appcast.S + 'minimumSystemVersion').text = '13.0'
            if mutation == 'length': entry.find('enclosure').set('length', '99')
            with self.subTest(mutation=mutation), self.assertRaises(ValueError):
                appcast.validate_item(entry, '0.3.0', 102, asset)


if __name__ == '__main__':
    unittest.main()
