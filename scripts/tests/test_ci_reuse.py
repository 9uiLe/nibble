"""A PR metadata edit may reuse only a completed check for identical source and base."""

from contextlib import redirect_stdout
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch


sys.path.insert(0, str(Path(__file__).parents[1]))
import check_pr as reuse

HEAD = 'a' * 40
BASE = 'b' * 40


def event(action='edited', base=BASE):
    return {'action': action, 'number': 60, 'repository': {'full_name': 'example/repo'},
            'pull_request': {'head': {'sha': HEAD}, 'base': {'sha': base}}}


def run(identifier, *, conclusion='success', base=BASE, number=60, status='completed'):
    return {'id': identifier, 'head_sha': HEAD, 'path': reuse.WORKFLOW,
            'event': 'pull_request', 'status': status, 'conclusion': conclusion,
            'pull_requests': [{'number': number, 'base': {'sha': base}}]}


def job(check='success', conclusion='success'):
    return {'name': reuse.JOB_NAME, 'conclusion': conclusion,
            'steps': [{'name': reuse.CHECK_STEP, 'conclusion': check}]}


def source(runs, jobs):
    def get(path):
        if path.endswith('/jobs?per_page=100'):
            identifier = int(path.split('/runs/')[1].split('/')[0])
            return {'total_count': len(jobs[identifier]), 'jobs': jobs[identifier]}
        return {'total_count': len(runs), 'workflow_runs': runs}
    return get


class ReuseTests(unittest.TestCase):
    def test_reuses_latest_successful_full_check_on_same_head_and_base(self):
        self.assertTrue(reuse.can_reuse(event(), 12, source([run(12, status='in_progress'), run(9)],
                                                      {9: [job()]})))

    def test_metadata_only_success_does_not_replace_prior_full_check(self):
        self.assertTrue(reuse.can_reuse(event(), 12, source([run(11), run(9)],
                                                      {11: [job('skipped')], 9: [job()]})))

    def test_reuses_full_step_even_when_later_pr_body_check_failed(self):
        self.assertTrue(reuse.can_reuse(event(), 12, source([run(9, conclusion='failure')],
                                                      {9: [job('success', 'failure')]})))

    def test_latest_failed_or_running_full_check_forces_recheck(self):
        for latest, jobs in [(run(11, conclusion='failure'), {11: [job('failure', 'failure')], 9: [job()]}),
                             (run(11, status='in_progress'), {9: [job()]})]:
            with self.subTest(latest=latest):
                self.assertFalse(reuse.can_reuse(event(), 12, source([latest, run(9)], jobs)))

    def test_other_base_pr_or_action_cannot_reuse(self):
        for candidate in [run(9, base='c' * 40), run(9, number=61)]:
            self.assertFalse(reuse.can_reuse(event(), 12, source([candidate], {9: [job()]})))
        self.assertFalse(reuse.can_reuse(event('synchronize'), 12, source([run(9)], {9: [job()]})))

    def test_missing_or_incomplete_history_forces_recheck(self):
        self.assertFalse(reuse.can_reuse(event(), 12, source([], {})))
        self.assertFalse(reuse.can_reuse(event(), 12,
                                        lambda _: {'total_count': 2, 'workflow_runs': [run(9)]}))
        self.assertFalse(reuse.can_reuse(event(), 12, source([run(9)], {9: []})))
        self.assertFalse(reuse.can_reuse(event(), 12, source([run(11), run(9)],
                                                       {11: [{'name': reuse.JOB_NAME, 'steps': []}], 9: [job()]})))

    def test_api_failure_prints_false_so_workflow_runs_full_check(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'event.json'
            path.write_text(json.dumps(event()))
            output = io.StringIO()
            with patch.object(reuse, 'can_reuse', side_effect=OSError('API unavailable')), redirect_stdout(output):
                self.assertEqual(reuse.main(['reuse-locked-checks', '--event', str(path), '--run-id', '12']), 0)
            self.assertEqual(output.getvalue(), 'false\n')


if __name__ == '__main__':
    unittest.main()
