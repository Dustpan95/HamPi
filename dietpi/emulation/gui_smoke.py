"""Require each non-root GUI process to create a visible X11 window."""
import os
from pathlib import Path
import signal
import subprocess
import time

assert os.getuid() != 0, "GUI checks must run as the station account"
failures = []
for command, window_hint in [
    (["xfce4-panel", "--disable-wm-check"], "xfce4-panel"),
    (["wsjtx"], "wsjt"),
    (["fldigi"], "fldigi"),
    (["flrig"], "flrig"),
    (["gqrx"], "gqrx"),
]:
    name = command[0]
    logfile = Path("/tmp") / (name + "-smoke.log")
    with logfile.open("w") as output:
        proc = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT,
                                start_new_session=True)
        passed = False
        try:
            deadline = time.monotonic() + 90
            while time.monotonic() < deadline and proc.poll() is None:
                tree = subprocess.check_output(
                    ["xwininfo", "-root", "-tree"], text=True, timeout=15)
                if window_hint in tree.lower():
                    time.sleep(3)
                    passed = proc.poll() is None
                    if passed:
                        print(tree, flush=True)
                        break
                time.sleep(2)
        finally:
            if proc.poll() is None:
                os.killpg(proc.pid, signal.SIGTERM)
                try:
                    proc.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(proc.pid, signal.SIGKILL)
                    proc.wait()
    print(logfile.read_text(errors="replace")[-6000:], flush=True)
    print(f"{'PASS' if passed else 'FAIL'}: {name} process and X11 window", flush=True)
    if not passed:
        failures.append(name)
if failures:
    raise SystemExit("GUI smoke failures: " + ", ".join(failures))
print("GUI startup only; first-run dialogs count. No audio, radio or decoding validation.")
