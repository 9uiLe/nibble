"""Public verification stages: one definition owns invocation and expected evidence."""
from dataclasses import dataclass
from ios_project import FIXTURE_CONFIG, PERFORMANCE_CONFIG, PRODUCT_CONFIG


@dataclass(frozen=True)
class Stage:
    id: str
    script: str | None = None
    project: str | None = None
    scheme: str | None = None
    command: str | None = None
    arguments: tuple[str, ...] = ()


REGRESSION = (
    Stage('static'),
    Stage('preview-native'),
    Stage('fixture-test', project=FIXTURE_CONFIG, scheme='VerificationApp', command='test'),
    Stage('product-test', project=PRODUCT_CONFIG, scheme='Nibble', command='test'),
    Stage('fixture-smoke', project=FIXTURE_CONFIG, scheme='VerificationApp', command='fixture-smoke'),
    Stage('library-ui', 'check_library_ui.py', scheme='Nibble', command='library-ui'),
    Stage('notice-ui', 'check_notice_ui.py', scheme='Nibble', command='notice-ui'),
    Stage('controls-ui', 'check_controls_ui.py', scheme='Nibble', command='controls-ui'),
    Stage('interface-ui', 'check_interface_ui.py', scheme='Nibble', command='fixed-interface'),
    Stage('about-ui', 'check_about_ui.py', scheme='Nibble', command='rive-about'),
    Stage('keyboard-guide-ui', 'check_about_ui.py', scheme='Nibble', command='rive-keyboard',
          arguments=('--story', 'keyboard')),
)
PERFORMANCE = (
    Stage('performance-test', project=PERFORMANCE_CONFIG, scheme='NibblePerformance', command='test'),
)
STAGES = {stage.id: stage for stage in (*REGRESSION, *PERFORMANCE)}
REGRESSION_STEPS = [stage.id for stage in REGRESSION]
PERFORMANCE_STEPS = [stage.id for stage in PERFORMANCE]
PRODUCT_STEPS = {stage.id for stage in REGRESSION if stage.scheme == 'Nibble'}
OFFLINE_STEPS = {stage.id for stage in REGRESSION if stage.scheme is None}
SCOPES = {
    'inspection': {'preview-native'},
    'fixture': {'fixture-test', 'fixture-smoke'},
    'product': PRODUCT_STEPS,
    'regression': set(REGRESSION_STEPS),
    'performance': set(PERFORMANCE_STEPS),
}
