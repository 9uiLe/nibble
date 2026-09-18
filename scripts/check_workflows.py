"""Keep all GitHub Actions jobs on an explicit, approved Ubuntu runner."""

from pathlib import Path
import sys

import yaml

from script_ui import ui


ALLOWED_RUNNER = "ubuntu-24.04"


class UniqueKeyLoader(yaml.SafeLoader):
    """Reject duplicate YAML keys instead of silently checking just one value."""

    def construct_mapping(self, node, deep=False):
        self.flatten_mapping(node)
        seen = set()
        for key_node, _ in node.value:
            key = self.construct_object(key_node, deep=deep)
            if not isinstance(key, (str, bool, int, float, type(None))):
                raise ValueError("YAML mapping keys must be scalars")
            if key in seen:
                raise ValueError(f"Duplicate YAML key: {key!r}")
            seen.add(key)
        return super().construct_mapping(node, deep=deep)


def check_workflows(directory: Path) -> list[str]:
    errors = []
    paths = sorted([*directory.glob("*.yml"), *directory.glob("*.yaml")])
    if not paths:
        return [f"{directory}: no workflow files found"]

    for path in paths:
        try:
            workflow = yaml.load(path.read_text(encoding="utf-8"), Loader=UniqueKeyLoader)
        except (OSError, UnicodeError, yaml.YAMLError, ValueError) as error:
            errors.append(f"{path.name}: {error}")
            continue

        jobs = workflow.get("jobs") if isinstance(workflow, dict) else None
        if not isinstance(jobs, dict) or not jobs:
            errors.append(f"{path.name}: expected a non-empty jobs mapping")
            continue

        for job_id, job in jobs.items():
            label = f"{path.name}: jobs.{job_id}"
            if not isinstance(job, dict):
                errors.append(f"{label}: expected a job mapping")
            elif "uses" in job:
                errors.append(f"{label}: reusable workflows are not allowed")
            elif job.get("runs-on") != ALLOWED_RUNNER:
                errors.append(f"{label}: runs-on must be exactly {ALLOWED_RUNNER!r}")

    return errors


def main() -> int:
    directory = Path(__file__).resolve().parents[1] / ".github" / "workflows"
    errors = check_workflows(directory)
    ui.check('Workflow policy', errors, f'every job explicitly uses {ALLOWED_RUNNER}')
    return int(bool(errors))


if __name__ == "__main__":
    sys.exit(main())
