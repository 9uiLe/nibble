"""Create traceable PNG viewing artifacts outside recorded iOS runs using Apple sips."""

import hashlib
import json
from pathlib import Path
import struct
import subprocess
import tempfile
import zlib

from verification_evidence import digest

SIPS = Path('/usr/bin/sips')


def png_size(data):
    """Validate the PNG container; the renderer must also decode its image data."""
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        raise ValueError('Expected a PNG screenshot or extracted frame')
    offset, dimensions, has_data = 8, None, False
    while offset + 12 <= len(data):
        length = struct.unpack_from('>I', data, offset)[0]
        end = offset + 12 + length
        if end > len(data):
            raise ValueError('Truncated PNG chunk')
        kind, body = data[offset + 4:offset + 8], data[offset + 8:end - 4]
        if zlib.crc32(kind + body) != struct.unpack_from('>I', data, end - 4)[0]:
            raise ValueError('Invalid PNG checksum')
        if dimensions is None and kind != b'IHDR':
            raise ValueError('PNG must begin with IHDR')
        if kind == b'IHDR':
            if dimensions is not None or length != 13:
                raise ValueError('Invalid PNG header')
            dimensions = struct.unpack('>II', body[:8])
            if not all(dimensions):
                raise ValueError('Invalid PNG dimensions')
        if kind == b'IDAT':
            has_data = True
        if kind == b'IEND':
            if length or not has_data or end != len(data):
                raise ValueError('Invalid PNG end or missing image data')
            return dimensions
        offset = end
    raise ValueError('Incomplete PNG')


def _render(source, destination, options, commands):
    command = [str(SIPS), '-s', 'format', 'png', *options, str(source), '--out', str(destination)]
    event = {'argv': command}
    commands.append(event)
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.SubprocessError) as error:
        event['error'] = type(error).__name__
        raise ValueError('PNG conversion could not complete') from error
    event.update(exit_code=result.returncode, stdout=result.stdout, stderr=result.stderr)
    if result.returncode:
        raise ValueError('PNG conversion failed; inspect failure.json')
    return png_size(destination.read_bytes())


def create_preview(source, output, *, max_edge=960, crop=None):
    """Publish preview.json only after decoding, geometry and source-identity checks."""
    source, output = source.resolve(), output.resolve()
    for parent in (output, *output.parents):
        if (parent / 'manifest.json').exists():
            raise ValueError('Write previews outside all recorded runs')
    if output.exists():
        raise FileExistsError('Preview output already exists: ' + str(output))
    if type(max_edge) is not int or max_edge <= 0:
        raise ValueError('max-edge must be positive')
    raw = source.read_bytes()
    width, height = png_size(raw)
    bounds = (0, 0, width, height) if crop is None else tuple(crop)
    if len(bounds) != 4 or any(type(value) is not int for value in bounds):
        raise ValueError('Crop needs four integer pixel coordinates')
    x, y, cropped_width, cropped_height = bounds
    if (min(x, y) < 0 or min(cropped_width, cropped_height) <= 0
            or x + cropped_width > width or y + cropped_height > height):
        raise ValueError('Crop must fit the original PNG')
    if not SIPS.is_file():
        raise ValueError('Image previews require macOS /usr/bin/sips')
    identity = {'path': str(source), 'sha256': hashlib.sha256(raw).hexdigest(),
                'size_pixels': [width, height]}
    output.mkdir(parents=True, exist_ok=False)
    commands = []
    try:
        # A private copy binds all conversion stages to the bytes identified above.
        with tempfile.TemporaryDirectory(prefix='.work-', dir=output) as temporary:
            workspace = Path(temporary)
            snapshot, rendered = workspace / 'source.png', workspace / 'rendered.png'
            snapshot.write_bytes(raw)
            options = []
            if crop is not None:
                options = ['--cropToHeightWidth', str(cropped_height), str(cropped_width),
                           '--cropOffset', str(y), str(x)]
            elif max(width, height) > max_edge:
                options = ['--resampleHeightWidthMax', str(max_edge)]
            result_width, result_height = _render(snapshot, rendered, options, commands)
            if crop is not None:
                if (result_width, result_height) != (cropped_width, cropped_height):
                    raise ValueError('Crop output dimensions do not match the requested region')
                if max(cropped_width, cropped_height) > max_edge:
                    scaled = workspace / 'scaled.png'
                    result_width, result_height = _render(
                        rendered, scaled, ['--resampleHeightWidthMax', str(max_edge)], commands)
                    rendered = scaled
            if (max(result_width, result_height) != min(max_edge, max(cropped_width, cropped_height))
                    or result_width > cropped_width or result_height > cropped_height
                    or abs(result_width * cropped_height - result_height * cropped_width)
                    > max(cropped_width, cropped_height)):
                raise ValueError('Preview dimensions do not preserve the requested scale')
            if digest(source) != identity['sha256']:
                raise ValueError('Source changed while creating the preview')
            image = output / 'preview.png'
            rendered.rename(image)
        report = {'schema_version': 1, 'kind': 'image_preview', 'source': identity,
                  'preview': {'path': str(image), 'sha256': digest(image),
                              'size_pixels': [result_width, result_height]},
                  'transform': {'crop_pixels': list(bounds), 'max_edge': max_edge,
                                'source_pixels_per_preview_pixel':
                                [cropped_width / result_width, cropped_height / result_height]},
                  'record': str(output / 'preview.json')}
        with (output / 'preview.json').open('x') as stream:
            stream.write(json.dumps({**report, 'commands': commands}, ensure_ascii=False, indent=2) + '\n')
        return report
    except (OSError, ValueError, KeyboardInterrupt) as error:
        (output / 'preview.json').unlink(missing_ok=True)
        with (output / 'failure.json').open('x') as stream:
            json.dump({'schema_version': 1, 'kind': 'image_preview_failure', 'source': identity,
                       'error': str(error) or 'Interrupted', 'commands': commands}, stream,
                      ensure_ascii=False, indent=2)
        raise
