"""Public progress on stderr through hamio; command data and exit codes belong to callers.

Only pass public text here. Never pass signing command arguments, environment
dictionaries, credentials or native deployment logs. This module does not redact arbitrary text.
"""

from contextlib import contextmanager
import json
import os
import shutil
import subprocess
import sys


class Reporter:
    """Bounded, non-interactive display. A display failure never retries business work."""

    def __init__(self):
        self._unavailable = False

    def _write(self, text):
        try:
            sys.stderr.write(text)
            sys.stderr.flush()
        except (OSError, UnicodeError):
            # Losing the terminal must not interrupt a signing/upload operation.
            pass

    def _fallback(self, blocks):
        # JSON escapes terminal controls even when hamio cannot sanitize them.
        self._write(json.dumps({'display': 'fallback', 'blocks': blocks}, ensure_ascii=True) + '\n')

    def _render(self, blocks):
        if self._unavailable:
            self._fallback(blocks)
            return
        try:
            mode = os.environ.get('NIBBLE_UI_FORMAT') or (
                'human' if sys.stderr.isatty() and not os.environ.get('CI') else 'json')
            if mode not in {'human', 'json'}:
                raise ValueError('Invalid display mode')
            executable = shutil.which('hamio')
            if executable is None:
                raise OSError('Missing renderer')
            # Display receives no ambient tokens, Python configuration or signing settings.
            environment = {key: os.environ[key] for key in
                           ('PATH', 'LANG', 'LC_ALL', 'TERM', 'NO_COLOR') if key in os.environ}
            color = ('always' if mode == 'human' and sys.stderr.isatty()
                     and environment.get('TERM') != 'dumb' and not environment.get('NO_COLOR') else 'never')
            request = {'apiVersion': 1, 'blocks': blocks}
            result = subprocess.run([executable, 'render', '--format', mode, '--color', color],
                                    input=json.dumps(request, ensure_ascii=False), text=True,
                                    capture_output=True, timeout=3, env=environment)
            response = json.loads(result.stdout)
            if (result.returncode != 0 or response.get('apiVersion') != 1
                    or response.get('status') != 'ok'
                    or (mode == 'human' and not result.stderr.strip())
                    or (mode == 'json' and (response.get('blocks') != blocks or result.stderr))):
                raise ValueError('Invalid renderer response')
            # hamio's acknowledgement is display status, not the command's result.
            self._write(result.stderr if mode == 'human' else result.stdout)
        except (OSError, ValueError, AttributeError, subprocess.SubprocessError):
            self._unavailable = True
            self._write('nibble: hamio display unavailable; using JSON on stderr. Run in the locked Nix shell.\n')
            self._fallback(blocks)

    @staticmethod
    def _chunks(text):
        # 1,000 Unicode code points fit hamio's 4,096-byte string limit.
        value = str(text)
        return [value[index:index + 1000] for index in range(0, len(value), 1000)] or ['']

    def message(self, text, level='info'):
        for part in self._chunks(text):
            self._render([{'kind': 'message', 'level': level, 'text': part}])

    def result(self, success, text):
        parts = self._chunks(text)
        self._render([{'kind': 'result', 'success': bool(success), 'message': parts[0]}])
        for part in parts[1:]:
            self.message(part, 'info' if success else 'error')

    def check(self, title, errors, summary):
        """Display findings; callers retain the report and decide their exit code."""
        self.result(not errors, title + ': ' + ('failed' if errors else summary))
        for error in errors:
            self.message(error, 'error')

    @contextmanager
    def step(self, label):
        self.message(label + ': 開始')
        try:
            yield
        except BaseException:
            # Exceptions may contain secrets. Only the caller-provided label is displayed.
            self.message(label + ': 未完了', 'error')
            raise
        else:
            self.message(label + ': 成功', 'success')


ui = Reporter()
