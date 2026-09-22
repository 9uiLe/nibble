"""Full-value comparison, bounded output and trustworthy saved-input identity."""

import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parents[1]))
from ui_observation import read_observation, summarize


class ObservationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)

    def save(self, entries, name='current', envelope=True, **context):
        path = self.root / (name + '.json')
        data = {'entries': entries, **context}
        path.write_text(json.dumps({'ok': True, 'data': data} if envelope else data, ensure_ascii=False))
        return path

    def test_source_hash_identifies_the_exact_bytes_parsed(self):
        source = self.save([{'value': 'original'}])
        raw = source.read_bytes()
        changed = raw.replace(b'original', b'changed')
        with patch.object(Path, 'read_bytes', side_effect=[raw, changed, changed]):
            report = summarize(source)
        self.assertEqual(report['elements']['items'][0]['value'], 'original')
        self.assertEqual(report['source']['sha256'], hashlib.sha256(raw).hexdigest())

    def test_both_producer_formats_preserve_whitespace_and_unicode(self):
        value = '  原文\n👩🏽‍💻\t末尾  '
        for envelope in (True, False):
            source = self.save([{'uniqueId': 'body', 'value': value, 'label': '整形済み'}], envelope=envelope)
            result = summarize(source, identifiers=['body'], text_limit=0)
            self.assertEqual(result['elements']['items'][0]['value'], value)
            self.assertEqual(result['elements']['items'][0]['id'], 'body')

    def test_count_and_text_omissions_are_explicit(self):
        source = self.save([{'label': 'abcdef', 'value': '1234567'}, {'label': 'second'}])
        result = summarize(source, limit=1, text_limit=3)['elements']
        self.assertEqual((result['total'], result['omitted']), (2, 1))
        self.assertEqual(result['items'][0]['text_lengths'], {'label': 6, 'value': 7})
        self.assertEqual(result['items'][0]['value'], '123')

    def test_missing_ids_are_distinct_from_omitted_elements(self):
        source = self.save([{'uniqueId': 'present'}, {'label': 'unidentified'}])
        result = summarize(source, identifiers=['missing', 'present', 'missing'])
        self.assertEqual(result['selection']['ids'], ['missing', 'present'])
        self.assertEqual(result['missing_ids'], ['missing'])
        self.assertEqual(result['elements']['total'], 1)
        self.assertEqual(result['observed_count'], 2)

    def test_diff_detects_tail_changes_duplicate_removal_and_disappearance(self):
        before = self.save([{'uniqueId': 'body', 'value': 'prefix old'}, {'label': 'same'},
                            {'label': 'same'}, {'uniqueId': 'gone'}], name='before')
        source = self.save([{'label': 'same'}, {'uniqueId': 'body', 'value': 'prefix new'}])
        result = summarize(source, before=before, text_limit=6)
        self.assertEqual(result['added']['total'], 1)
        self.assertEqual(result['removed']['total'], 3)
        self.assertEqual(result['added']['items'][0]['value'], 'prefix')
        selected = summarize(source, before=before, identifiers=['gone'])
        self.assertEqual(selected['missing_ids'], ['gone'])
        self.assertEqual(selected['removed']['total'], 1)

    def test_order_is_ignored_frames_are_optional_context_changes_are_visible(self):
        frame = {'x': 1, 'y': 0, 'width': 30, 'height': 20}
        before = self.save([{'label': 'a', 'frame': frame}, {'label': 'b'}], name='before', appPackage='settings')
        source = self.save([{'label': 'b'}, {'label': 'a', 'frame': {**frame, 'x': 2}}], appPackage='nibble')
        result = summarize(source, before=before)
        self.assertEqual(result['added']['total'], 0)
        self.assertTrue(result['context_changed'])
        self.assertEqual(result['before_context']['app_package'], 'settings')
        precise = summarize(source, before=before, frames=True)
        self.assertEqual(precise['added']['items'][0]['frame_points']['x'], 2)

    def test_empty_observation_is_data_not_an_assertion_of_success(self):
        result = summarize(self.save([]))
        self.assertEqual(result['elements'], {'items': [], 'total': 0, 'omitted': 0})
        self.assertNotIn('passed', result)

    def test_invalid_input_and_limits_fail(self):
        source = self.root / 'invalid.json'
        for document in ({'ok': False, 'data': {'entries': []}}, {'entries': [None]},
                         {'entries': [{'value': {}}]}, {'entries': [{'label': []}]},
                         {'entries': [{'frame': {'x': 1}}]}, {'entries': [{'states': 'selected'}]},
                         {'entries': [], 'appLabel': {}}):
            source.write_text(json.dumps(document))
            with self.subTest(document=document), self.assertRaises(ValueError):
                read_observation(source)
        for raw in ('{"entries":[],"entries":[]}', '{"entries":[{"value":NaN}]}',
                    '{"entries":[{"value":1e999}]}'):
            source.write_text(raw)
            with self.subTest(raw=raw), self.assertRaises(ValueError):
                read_observation(source)
        source = self.save([])
        for options in ({'limit': 0}, {'text_limit': -1}, {'limit': True}):
            with self.subTest(options=options), self.assertRaises(ValueError):
                summarize(source, **options)


if __name__ == '__main__':
    unittest.main()
