"""Exercise two simulator processes; this does not emulate an extension sandbox."""
import argparse
import json
import os
import pathlib
import select
import signal
import shutil
import subprocess
import time
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument("--device", required=True)
args = parser.parse_args()
devices = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "--json"]))["devices"]
assert any("iOS-26-5" in runtime and device["udid"] == args.device and device["state"] == "Booted"
           for runtime, group in devices.items() for device in group), "Use a booted iOS 26.5 Simulator"
out = ROOT / "artifacts/research/processes" / str(uuid.uuid4())
out.mkdir(parents=True)
sdk = subprocess.check_output(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"], text=True).strip()
binary = out / "SQLiteWorker"
subprocess.run(["xcrun", "--sdk", "iphonesimulator", "swiftc", "-swift-version", "6", "-O", "-target", "arm64-apple-ios26.0-simulator", "-sdk", sdk,
                str(ROOT / "research/probe/SQLiteWorker.swift"), "-o", str(binary)], check=True, env={**os.environ, "SDKROOT": sdk})
base = ["xcrun", "simctl", "spawn", args.device, str(binary), str(out / "store.sqlite")]
events = []

def run(operation, expected=0):
    p = subprocess.run(base + [operation], capture_output=True, text=True, timeout=20)
    events.append({"operation": operation, "exit": p.returncode, "stdout": p.stdout, "stderr": p.stderr})
    assert (p.returncode == 0) if expected == 0 else (p.returncode != 0), events[-1]
    return p.stdout.strip()

def hold(operation):
    p = subprocess.Popen(base + [operation], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    data = b""
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        if select.select([p.stdout], [], [], 0.1)[0]:
            chunk = os.read(p.stdout.fileno(), 4096)
            if not chunk:
                raise RuntimeError(p.stderr.read().decode())
            data += chunk
            for line in data.decode().splitlines():
                if line.startswith("READY "):
                    return p, int(line.split()[1]), data.decode()
    p.kill()
    raise TimeoutError("SQLite worker did not become ready")

run("setup")
run("environment")
p, pid, initial = hold("hold-write")
try:
    assert run("read") == "original"
    run("write", expected=1)
finally:
    os.kill(pid, signal.SIGKILL)  # Exact PID reported by this task's own disposable process.
    p.communicate(timeout=10)
assert run("read") == "original"
assert run("integrity") == "ok"
events.append({"case": "kill-before-commit", "result": "original survived"})
p, pid, initial = hold("hold-read")
try:
    run("write")
    output, errors = p.communicate(input=b"continue\n", timeout=10)
    assert p.returncode == 0, errors
    assert output.decode().splitlines() == ["original", "committed"], output
finally:
    if p.poll() is None:
        os.kill(pid, signal.SIGKILL)
        p.communicate(timeout=10)
events.append({"case": "reader-across-commit", "initial": initial, "after": output.decode()})
assert run("read") == "committed"
assert run("integrity") == "ok"
run("checkpoint")
readonly = out / "readonly"
readonly.mkdir()
for file in out.glob("store.sqlite*"):
    shutil.copy2(file, readonly / file.name)
for file in readonly.iterdir():
    file.chmod(0o444)
readonly.chmod(0o555)
try:
    result = subprocess.run(base[:-1] + [str(readonly / "store.sqlite"), "readonly"], capture_output=True, text=True, timeout=20)
    events.append({"case": "readonly-directory-no-new-sidecars", "exit": result.returncode, "stdout": result.stdout, "stderr": result.stderr})
    # This is an observation of filesystem permissions, not an App Group sandbox test.
finally:
    readonly.chmod(0o755)
(out / "results.json").write_text(json.dumps({"device": args.device, "events": events}, indent=2))
print(out)
