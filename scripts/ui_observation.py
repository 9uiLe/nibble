"""Read saved accessibility observations and produce bounded, traceable reports."""

from collections import Counter
import hashlib
import json
import math


def _object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('Duplicate JSON field: ' + key)
        result[key] = value
    return result


def _invalid_number(value):
    raise ValueError('Non-finite JSON number: ' + value)


def _number(value):
    number = float(value)
    if not math.isfinite(number):
        _invalid_number(value)
    return number


def _frame(value, name):
    if (not isinstance(value, dict) or any(
            type(value.get(key)) not in (int, float)
            or (type(value[key]) is float and not math.isfinite(value[key]))
            for key in ('x', 'y', 'width', 'height'))
            or value['width'] < 0 or value['height'] < 0):
        raise ValueError('Invalid accessibility coordinates: ' + name)


def read_observation(path):
    """Parse and hash the same bytes; support sim-use envelopes and Run.ui data."""
    path = path.resolve()
    raw = path.read_bytes()
    document = json.loads(raw, object_pairs_hook=_object, parse_constant=_invalid_number, parse_float=_number)
    if not isinstance(document, dict):
        raise ValueError('Expected a sim-use UI object')
    if 'ok' in document:
        if document['ok'] is not True:
            raise ValueError('sim-use observation failed')
        document = document.get('data')
    if not isinstance(document, dict) or not isinstance(document.get('entries'), list):
        raise ValueError('Expected sim-use entries')
    for entry in document['entries']:
        if not isinstance(entry, dict):
            raise ValueError('Expected an accessibility element object')
        for key in ('uniqueId', 'role', 'label'):
            if key in entry and not isinstance(entry[key], str):
                raise ValueError('Expected text for element ' + key)
        if 'value' in entry and not isinstance(entry['value'], (str, int, float, bool, type(None))):
            raise ValueError('Expected a scalar accessibility value')
        if 'states' in entry and (not isinstance(entry['states'], list)
                                  or any(not isinstance(item, str) for item in entry['states'])):
            raise ValueError('Expected accessibility states as a list of strings')
        if 'frame' in entry:
            _frame(entry['frame'], 'frame')
    if 'screen' in document:
        _frame(document['screen'], 'screen')
    for key in ('appLabel', 'appPackage', 'orientation'):
        if key in document and not isinstance(document[key], str):
            raise ValueError('Expected text for observation ' + key)
    context = {target: document[source] for source, target in (
        ('appLabel', 'app_label'), ('appPackage', 'app_package'),
        ('orientation', 'orientation'), ('screen', 'screen_points')) if source in document}
    return {'source': {'path': str(path), 'sha256': hashlib.sha256(raw).hexdigest()},
            'context': context, 'entries': document['entries']}


def _select(entries, identifiers, frames):
    fields = [('uniqueId', 'id'), ('role', 'role'), ('label', 'label'),
              ('value', 'value'), ('states', 'states')]
    if frames:
        fields.append(('frame', 'frame_points'))
    return [{target: entry[source] for source, target in fields if source in entry}
            for entry in entries if not identifiers or entry.get('uniqueId') in identifiers]


def _difference(rows, previous):
    """Compare complete projected values and multiplicity; ignore element order."""
    def key(row):
        return json.dumps(row, ensure_ascii=False, sort_keys=True, allow_nan=False)
    remaining = Counter(key(row) for row in previous)
    result = []
    for row in rows:
        encoded = key(row)
        if remaining[encoded]:
            remaining[encoded] -= 1
        else:
            result.append(row)
    return result


def _bounded(rows, limit, text_limit):
    items = []
    for row in rows[:limit]:
        item, lengths = dict(row), {}
        for key in ('label', 'value'):
            value = item.get(key)
            if isinstance(value, str) and text_limit and len(value) > text_limit:
                item[key] = value[:text_limit]
                lengths[key] = len(value)
        if lengths:
            item['text_lengths'] = lengths
        items.append(item)
    return {'items': items, 'total': len(rows), 'omitted': max(0, len(rows) - limit)}


def summarize(source, *, before=None, identifiers=(), frames=False, limit=30, text_limit=160):
    """Summarize an observation or its semantic difference without asserting UI correctness."""
    if type(limit) is not int or limit <= 0 or type(text_limit) is not int or text_limit < 0:
        raise ValueError('limit must be positive and text-limit nonnegative')
    current = read_observation(source)
    identifiers = list(dict.fromkeys(identifiers))
    rows = _select(current['entries'], identifiers, frames)
    available = {entry.get('uniqueId') for entry in current['entries']}
    result = {'schema_version': 1, 'kind': 'accessibility',
              'source': current['source'], 'context': current['context'],
              'selection': {'ids': identifiers, 'frames': frames, 'limit': limit, 'text_limit': text_limit},
              'observed_count': len(current['entries']),
              'missing_ids': [identifier for identifier in identifiers if identifier not in available]}
    if before is None:
        result.update(mode='snapshot', elements=_bounded(rows, limit, text_limit))
    else:
        previous = read_observation(before)
        old_rows = _select(previous['entries'], identifiers, frames)
        result.update(mode='difference', before=previous['source'], before_context=previous['context'],
                      context_changed=current['context'] != previous['context'],
                      added=_bounded(_difference(rows, old_rows), limit, text_limit),
                      removed=_bounded(_difference(old_rows, rows), limit, text_limit))
    return result
