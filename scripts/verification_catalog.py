"""Public verification stages: one definition owns invocation and expected evidence."""
from dataclasses import dataclass


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
    Stage('fixture-test', project='validation/project.json', scheme='VerificationApp', command='test'),
    Stage('product-test', project='app/project.json', scheme='Nibble', command='test'),
    Stage('fixture-smoke', project='validation/project.json', scheme='VerificationApp', command='smoke'),
    Stage('library-ui', 'check_library_ui.py', scheme='Nibble', command='library-ui'),
    Stage('notice-ui', 'check_notice_ui.py', scheme='Nibble', command='notice-ui'),
    Stage('interface-ui', 'check_interface_ui.py', scheme='Nibble', command='fixed-interface'),
    Stage('about-ui', 'check_about_ui.py', scheme='Nibble', command='rive-about'),
    Stage('keyboard-guide-ui', 'check_about_ui.py', scheme='Nibble', command='rive-keyboard',
          arguments=('--story', 'keyboard')),
)
PERFORMANCE = (
    Stage('performance-test', project='app/performance-project.json', scheme='NibblePerformance', command='test'),
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
