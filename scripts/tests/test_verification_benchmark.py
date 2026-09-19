"""Report measured throughput and distribution without hiding failures."""
import importlib.util
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).parents[1]))
spec = importlib.util.spec_from_file_location('benchmark_verification', Path(__file__).parents[1] / 'benchmark-verification.py')
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
