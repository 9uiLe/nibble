"""Project descriptions shared by the local CLI and verification catalog."""
import json
from pathlib import Path
import re

PRODUCT_CONFIG = 'app/project.json'
FIXTURE_CONFIG = 'validation/project.json'
PERFORMANCE_CONFIG = 'app/performance-project.json'


def load_project(root, path):
    config = json.loads((root / path).read_text())
    required = {'project', 'scheme', 'bundle_id', 'app_name', 'minimum_ios'}
    allowed = required | {'simulator_signing'}
    if not isinstance(config, dict) or not required <= config.keys() or config.keys() - allowed:
        raise ValueError('Project config requires project, scheme, bundle_id, app_name and minimum_ios')
    if any(not isinstance(value, str) or not value.strip() for value in config.values()):
        raise ValueError('Project config values must be nonempty strings')
    project = Path(config['project'])
    if (project.is_absolute() or '..' in project.parts or project.suffix != '.xcodeproj'
            or project.parts[0] not in {'app', 'validation'}
            or not (root / project / 'project.pbxproj').is_file()):
        raise ValueError('Project must identify an existing Xcode project under app/ or validation/')
    if Path(config['app_name']).name != config['app_name'] or config['app_name'] in {'.', '..'}:
        raise ValueError('app_name must be a bundle basename')
    if not re.fullmatch(r'[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+', config['bundle_id']):
        raise ValueError('bundle_id must be a reverse-domain identifier')
    if not re.fullmatch(r'\d+\.\d+(?:\.\d+)?', config['minimum_ios']):
        raise ValueError('minimum_ios must be a numeric OS version')
    if config.get('simulator_signing', 'disabled') not in {'disabled', 'ad-hoc'}:
        raise ValueError('simulator_signing must be disabled or ad-hoc')
    return config
