"""Report measured throughput and distribution without hiding failures."""
import importlib.util
from pathlib import Path
import sys
import unittest
import json
import tempfile
from contextlib import nullcontext
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parents[1]))
import benchmark_store as store
spec = importlib.util.spec_from_file_location('benchmark_verification', Path(__file__).parents[1] / 'benchmark_verification.py')
benchmark = importlib.util.module_from_spec(spec)
spec.loader.exec_module(benchmark)


class SummaryTests(unittest.TestCase):
    def test_failures_and_elapsed_window_are_included_in_throughput(self):
        result = benchmark.summarize([{'status': 'passed', 'seconds': 10},
                                      {'status': 'passed', 'seconds': 20},
                                      {'status': 'failed', 'seconds': 30}], 90)
        self.assertEqual(result['failed'], 1)
        self.assertEqual(result['median_seconds'], 15)
        self.assertEqual(result['range_seconds'], 10)
        self.assertEqual(result['observed_cycles_per_hour'], 80)
        self.assertEqual(result['measurement_window_seconds'], 90)

    def test_no_success_is_not_reported_as_zero_latency(self):
        result = benchmark.summarize([{'status': 'failed', 'seconds': 3}], 3)
        self.assertIsNone(result['median_seconds'])
        self.assertEqual(result['observed_cycles_per_hour'], 0)


class StoreMeasurementTests(unittest.TestCase):
    def test_source_selection_tracks_roles_across_layouts_and_rejects_collisions(self):
        domain = ['app/Shared/Domain/Snippet.swift', 'app/Shared/Persistence/SnippetStore.swift']
        for folder in ['Editing', 'Application']:
            selected = store.source_files([*domain, f'app/Shared/{folder}/EditorModel.swift',
                                           'app/Shared/Interface/SnippetHeading.swift',
                                           'app/Shared/Application/LibraryModel.swift'])
            self.assertEqual({path.name for path in selected}, {'Snippet.swift', 'SnippetStore.swift', 'EditorModel.swift'})
        with self.assertRaises(ValueError):
            store.source_files(domain)
        with self.assertRaises(ValueError):
            store.source_files([*domain, 'app/Shared/Editing/EditorModel.swift', 'app/Shared/Application/EditorModel.swift'])

    def test_interruption_preserves_partial_measurements_as_failed(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'run'
            def interrupted(args, output, manifest):
                manifest['runs'].append({'variant': 'baseline', 'sample': 1})
                raise KeyboardInterrupt
            with patch.object(sys, 'argv', ['benchmark_store.py', '--device', 'dedicated', '--baseline-ref', 'HEAD', '--output', str(output)]), \
                    patch.object(store, 'simulator_lock', return_value=nullcontext()), \
                    patch.object(store, 'measure', side_effect=interrupted):
                with self.assertRaises(KeyboardInterrupt):
                    store.main()
            result = json.loads((output / 'results.json').read_text())
            self.assertEqual(result['status'], 'failed')
            self.assertEqual(result['error'], 'KeyboardInterrupt')
            self.assertEqual(result['runs'], [{'variant': 'baseline', 'sample': 1}])
