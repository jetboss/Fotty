"""Offline fixtures only. Temporary directories are removed on every test exit."""
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import memory_support as memory


class PrivacyTests(unittest.TestCase):
    def test_redacts_supported_formats_without_disclosing_values(self):
        fixtures = [
            'https://audit_user:AUDIT_PASSWORD@example.invalid/private?access_token=AUDIT_KEY',
            'api_key: AUDIT_KEY', 'apiKey="AUDIT_KEY"', '{"clientSecret":"AUDIT_KEY"}',
            'password: AUDIT PASSWORD WITH SPACES',
            "password='AUDIT PASSWORD WITH SPACES'", 'Authorization: Bearer AUDIT_BEARER',
            'Authorization: Basic QVVESVQ6UEFTU1dPUkQ=',
            'private_key: |\n  AUDIT_KEY\n  SECOND_LINE\npublic: okay\n',
            '-----BEGIN PRIVATE ' + 'KEY-----\nAUDIT_KEY\n-----END PRIVATE KEY-----',
            'ghp_' + 'A' * 36,
        ]
        for fixture in fixtures:
            with self.subTest(format=fixtures.index(fixture)):
                clean = memory.redact(fixture)
                for secret in ('AUDIT_PASSWORD', 'AUDIT_KEY', 'AUDIT PASSWORD', 'AUDIT_BEARER', 'QVVESVQ6', 'SECOND_LINE', 'A' * 36):
                    self.assertNotIn(secret, clean)
                self.assertEqual(memory.privacy_issues(clean), [])

    def test_url_host_retained_without_userinfo_or_path(self):
        self.assertEqual(memory.redact('https://user:pass@example.invalid:8443/path'),
                         'https://example.invalid:8443/[URL_REDACTED]')

    def test_incomplete_signing_material_remains_a_blocker(self):
        marker = '-----BEGIN PRIVATE ' + 'KEY-----\ntruncated'
        self.assertTrue(memory.privacy_issues(memory.redact(marker)))

    def test_raw_assignments_are_rejected_without_echoing_them(self):
        issues = memory.privacy_issues('api_key: PRIVATE_FIXTURE')
        self.assertTrue(issues)
        self.assertNotIn('PRIVATE_FIXTURE', str(issues))


class MemoryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='fotty-memory-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name in memory.EXPORT_FILES:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('# General\nUnrelated healthy source.\n', encoding='utf-8')
        (self.root / 'docs/notebooklm/Current-State.md').write_text(
            '# Current state\n## PiP playback\nWebKit video suspension has a current owner.\n'
            '## FPL Coach\nManager picks require verified scoring.\n'
            '## UCL fixtures\nChampions League schedule and availability are separate.\n'
            '## CPL cricket\nA verified fixture can have no provider.\n', encoding='utf-8')
        self.output = self.root / 'docs/notebooklm/Fotty-NotebookLM-Source.md'
        self.output.write_text('LAST GOOD BUNDLE', encoding='utf-8')

    def test_acronyms_find_distinct_relevant_sections(self):
        for term, expected in [('PiP','PiP playback'),('FPL','FPL Coach'),('UCL','UCL fixtures'),('CPL','CPL cricket')]:
            self.assertIn(expected, memory.search(self.root, term))

    def test_late_domain_term_survives_dictated_wrapper(self):
        query = 'For this Fotty task investigate the current issue with a paused video when using PiP'
        self.assertIn('pip', memory.terms_for(query))
        self.assertIn('PiP playback', memory.search(self.root, query))

    def test_picture_in_picture_spelling(self):
        self.assertIn('PiP playback', memory.search(self.root, 'picture-in-picture'))

    def test_current_summary_outranks_more_title_matches_in_history(self):
        path = self.root / 'docs/notebooklm/Decisions-Log.md'
        path.write_text('## 2026-09-07: PiP video paused\nRejected experiment.\n', encoding='utf-8')
        result = memory.search(self.root, 'PiP video paused')
        self.assertLess(result.index('CURRENT SUMMARY'), result.index('DATED HISTORY'))
        self.assertIn('Recorded caveat: Rejected experiment.', result)

    def test_sibling_section_does_not_inherit_an_unrelated_date(self):
        path = self.root / 'docs/notebooklm/Risks.md'
        path.write_text('# Risks\n## 2020-01-01: Past\nPast text.\n## Undated PiP\nVideo text.\n', encoding='utf-8')
        section = next(s for s in memory.sections(self.root) if s.title == 'Undated PiP')
        self.assertEqual(section.date, '')

    def test_alias_matches_official_competition_name(self):
        self.assertIn('ucl', memory.terms_for('Champions League'))

    def test_newest_equally_relevant_history_first(self):
        path = self.root / 'docs/notebooklm/Decisions-Log.md'
        path.write_text('## 2020-01-01: Zebra\nOlder observation.\n## 2026-09-07: Zebra\nLatest observation.\n', encoding='utf-8')
        result = memory.search(self.root, 'Zebra')
        self.assertLess(result.index('Latest observation'), result.index('Older observation'))
        self.assertIn('DATED HISTORY', result)

    def test_unknown_topic_is_explicit_fallback(self):
        self.assertIn('No relevant memory sections', memory.search(self.root, 'Quokka'))

    def test_output_bounded_for_huge_history(self):
        (self.root / 'docs/notebooklm/Decisions-Log.md').write_text(
            '\n'.join('## PiP %d\n%s' % (i, 'video ' * 2000) for i in range(20)), encoding='utf-8')
        self.assertLessEqual(len(memory.search(self.root, 'PiP video')), 6000)

    def test_export_digest_and_staleness(self):
        memory.export_bundle(self.root, self.output)
        self.assertEqual(memory.health(self.root, True), [])
        self.assertEqual(list(self.output.parent.glob('.fotty-memory-*')), [])
        (self.root / 'agent/OPERATOR.md').write_text('Changed source.', encoding='utf-8')
        self.assertTrue(any('stale' in issue for issue in memory.health(self.root, True)))

    def test_privacy_failure_preserves_last_good_export(self):
        (self.root / 'agent/OPERATOR.md').write_text('-----BEGIN CERTIFICATE-----\nUNREVIEWED', encoding='utf-8')
        with self.assertRaises(ValueError):
            memory.export_bundle(self.root, self.output)
        self.assertEqual(self.output.read_text(), 'LAST GOOD BUNDLE')

    def test_missing_source_preserves_last_good_export(self):
        (self.root / 'agent/OPERATOR.md').unlink()
        with self.assertRaises(OSError):
            memory.export_bundle(self.root, self.output)
        self.assertEqual(self.output.read_text(), 'LAST GOOD BUNDLE')

    def test_replace_failure_cleans_temporary_output(self):
        with patch.object(memory.os, 'replace', side_effect=OSError('synthetic replace failure')):
            with self.assertRaises(OSError):
                memory.export_bundle(self.root, self.output)
        self.assertEqual(self.output.read_text(), 'LAST GOOD BUNDLE')
        self.assertEqual(list(self.output.parent.glob('.fotty-memory-*')), [])

    def test_interruption_cleans_temporary_output(self):
        with patch.object(memory.os, 'replace', side_effect=SystemExit(143)):
            with self.assertRaises(SystemExit):
                memory.export_bundle(self.root, self.output)
        self.assertEqual(self.output.read_text(), 'LAST GOOD BUNDLE')
        self.assertEqual(list(self.output.parent.glob('.fotty-memory-*')), [])

    def test_default_export_does_not_touch_clipboard(self):
        with patch.object(sys, 'argv', ['memory_support.py', '--root', str(self.root), 'export']), \
             patch.object(memory.subprocess, 'run') as command:
            self.assertEqual(memory.main(), 0)
        command.assert_not_called()

    def test_clipboard_requires_explicit_flag(self):
        with patch.object(sys, 'argv', ['memory_support.py', '--root', str(self.root), 'export', '--copy-path']), \
             patch.object(memory.subprocess, 'run') as command:
            self.assertEqual(memory.main(), 0)
        self.assertEqual(command.call_args.args[0], ['pbcopy'])

    def test_changed_sources_during_export_fail_closed(self):
        with patch.object(memory, 'source_digest', side_effect=['before', 'after']):
            with self.assertRaises(ValueError):
                memory.export_bundle(self.root, self.output)
        self.assertEqual(self.output.read_text(), 'LAST GOOD BUNDLE')

    def test_health_checks_missing_references_and_summary_budget(self):
        current = self.root / 'docs/notebooklm/Current-State.md'
        current.write_text('`docs/does-not-exist.md`\n' + 'a' * 8100, encoding='utf-8')
        failures = memory.health(self.root)
        self.assertTrue(any('8 KB' in item for item in failures))
        self.assertTrue(any('Broken' in item for item in failures))


if __name__ == '__main__':
    unittest.main()
