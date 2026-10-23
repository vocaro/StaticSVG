#!/usr/bin/env python3
"""StaticSVG's release gate: every check doc/testing.md requires for a release, on one tree.

Run it as the heavy `gate` lane, `python3 scripts/eng run gate`, beside other sessions' work.
Admission counts it as one job, so every build it starts takes JOBS jobs and each suite runs its
tests in one process. It passes only when every step passed: the gate's own tests; the
documentation and spelling checks; and the full Swift suite in macOS debug and optimized builds
and on a disposable iOS simulator, each with at least SWIFT_TESTS tests, none failed and none
skipped but the opt-in probes in OPT_IN. A step that gives no result within its hang bound is
unmeasured, as is one whose prerequisite is missing, such as the simulator runtime, a simulator
that does not finish booting, or an `eng` check that cannot run (exit 2); the gate then exits 3,
never 0.
"""
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import threading

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from _engineering import toolkit_location  # noqa: E402

TOOLKIT = toolkit_location(ROOT)
sys.path.insert(0, str(TOOLKIT / "src/python"))
try:
    from vocaro_engineering.simulators import lifecycle  # noqa: E402
except ImportError:
    print(f"gate: no shared toolkit at {TOOLKIT}. Clone vocaro/apple-engineering beside this project's main "
          "checkout or set VOCARO_ENGINEERING_ROOT.", file=sys.stderr)
    raise SystemExit(2)

# Floors: a suite that runs fewer tests fails. Lower one only in the commit that removes tests.
SWIFT_TESTS = 155
GATE_TESTS = 18
# Tests that skip unless a probe's inputs are given (doc/testing.md, Probes); any other skip fails.
OPT_IN = {("SVGFontSizeCostTests", "testGeneratedProbeFixturesMatchScreen")}
# Admission counts the gate as one job, so every build it starts takes this many jobs.
JOBS = "2"
DEVICE = "iPhone 17 Pro"
# The runtime is named, not the newest found, so a gate records what it ran on. Move it in a commit
# of its own when the host's Xcode moves on.
RUNTIME = "com.apple.CoreSimulator.SimRuntime.iOS-27-2"
BUILD = ROOT / ".build/gate"


class Failed(Exception):
    """The step ran and did not meet its expectations."""


class Unmeasured(Exception):
    """The step produced no valid result; the message gives the cause."""


class Stopped(BaseException):
    """The lane was told to stop."""


def run(command, *, timeout, env=None, cwd=ROOT):
    """Run a command, streaming its output, and return its status and output.

    A stop or a timeout ends the command's whole process group: TERM, then KILL."""
    print("$ " + " ".join(str(part) for part in command), flush=True)
    process = subprocess.Popen([str(part) for part in command], cwd=cwd, env={**os.environ, **(env or {})},
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors="replace",
                               start_new_session=True)
    lines = []
    def read():
        for line in process.stdout:
            sys.stdout.write(line)
            lines.append(line)
        sys.stdout.flush()
    reader = threading.Thread(target=read, daemon=True)
    reader.start()
    try:
        status = process.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        stop(process)
        raise Unmeasured(f"`{command[0]}` gave no result within {timeout} s")
    except BaseException:
        stop(process)
        raise
    reader.join()
    return status, "".join(lines)


def stop(process):
    for sent in (signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(process.pid, sent)
            process.wait(timeout=10)
            return
        except ProcessLookupError:
            return
        except subprocess.TimeoutExpired:
            continue


XCTEST = re.compile(r"^Test Suite '(?:All tests|Selected tests)' (passed|failed) at [^\n]*\n\s*Executed (\d+) "
                    r"tests?, with (?:(\d+) tests? skipped and )?(\d+) failures?", re.M)
# swift test and xcodebuild print a skipped XCTest case as -[Module.Class method]; newer
# xcodebuild output names it Class.method().
SKIPPED = re.compile(r"^Test [Cc]ase '(?:-\[(?:\w+\.)?(\w+) (\w+)\]|(?:\w+\.)?(\w+)\.(\w+)\(\))' skipped", re.M)
UNITTEST = re.compile(r"^Ran (\d+) tests? in [^\n]*\n+(OK|FAILED)(?: \(([^)]*)\))?", re.M)


def xctest(status, output, minimum=SWIFT_TESTS):
    """Judge an XCTest run by its top-level totals and the cases it skipped."""
    totals = XCTEST.findall(output)
    executed = sum(int(total[1]) for total in totals)
    skipped = sum(int(total[2] or 0) for total in totals)
    failures = sum(int(total[3]) for total in totals)
    if failures or any(total[0] == "failed" for total in totals):
        raise Failed(f"{failures} of {executed} tests failed")
    if status:
        raise Failed(f"exited {status}" + ("" if totals else " before reporting any test totals"))
    if not totals:
        raise Unmeasured("reported no test totals")
    cases = sorted({(match[0] or match[2], match[1] or match[3]) for match in SKIPPED.findall(output)})
    required = sorted(f"{suite}.{test}" for suite, test in cases if (suite, test) not in OPT_IN)
    if required:
        raise Failed(f"{len(required)} required tests skipped: {', '.join(required)}")
    if skipped != len(cases):
        raise Failed(f"{skipped} tests skipped, but the log names {len(cases)}")
    if executed < minimum:
        raise Failed(f"ran {executed} tests, fewer than {minimum}")
    if not skipped:
        return f"{executed} tests passed, none skipped"
    return f"{executed - skipped} of {executed} tests passed; skipped only the opt-in {', '.join(t for _, t in cases)}"


def unittest_result(status, output, minimum):
    """Judge a unittest run by its summary."""
    summary = UNITTEST.findall(output)
    if not summary:
        raise Failed(f"exited {status} with no test summary") if status else Unmeasured("reported no test summary")
    executed = int(summary[-1][0])
    details = dict(item.split("=") for item in summary[-1][2].split(", ") if "=" in item)
    if summary[-1][1] == "FAILED" or status:
        raise Failed(f"{summary[-1][2] or f'exited {status}'} in {executed} tests")
    if int(details.get("skipped", 0)):
        raise Failed(f"{details['skipped']} of {executed} tests skipped")
    if executed < minimum:
        raise Failed(f"ran {executed} tests, fewer than {minimum}")
    return f"{executed} tests passed, none skipped"


def own_tests():
    return unittest_result(*run([sys.executable, "-m", "unittest", "discover", "-s", "scripts/tests", "-v"],
                                timeout=300), minimum=GATE_TESTS)


def eng_check(*arguments):
    """An `eng` check, against the toolkit this gate found. Exit 2 means it could not run."""
    status, output = run([sys.executable, "scripts/eng", *arguments], timeout=600,
                         env={"VOCARO_ENGINEERING_ROOT": str(TOOLKIT)})
    if status == 2:
        cause = output.strip().splitlines()[-1] if output.strip() else "no output"
        raise Unmeasured(f"`eng {' '.join(arguments)}` could not run: {cause}")
    if status:
        raise Failed(f"exited {status}")
    return "passed"


def swift_suite(name, *configuration):
    return xctest(*run(["swift", "test", "--jobs", JOBS, "--scratch-path", BUILD / name, *configuration],
                       timeout=5400))


def runtime_identity():
    """The named runtime's version and build, when it is available and offers DEVICE."""
    listed = json.loads(lifecycle.command("list", "runtimes", "--json"))
    for runtime in listed["runtimes"]:
        if runtime.get("identifier") == RUNTIME and runtime.get("isAvailable"):
            for device_type in runtime.get("supportedDeviceTypes", []):
                if device_type["name"] == DEVICE:
                    return runtime, device_type
            raise Unmeasured(f"{RUNTIME} offers no {DEVICE} simulator")
    raise Unmeasured(f"{RUNTIME} is not an available simulator runtime on this host")


def ios_suite():
    runtime, device_type = runtime_identity()
    print(f"iOS {runtime['version']} ({runtime['buildversion']}), {DEVICE}", flush=True)
    results = BUILD / "ios.xcresult"
    shutil.rmtree(results, ignore_errors=True)
    with lifecycle.disposable(device_type["identifier"], runtime["identifier"], prefix="StaticSVG-gate") as device:
        print(f"Simulator {device.udid}", flush=True)
        try:
            device.boot()
        except subprocess.TimeoutExpired:
            raise Unmeasured(f"simulator {device.udid} did not finish booting within 600 s")
        except subprocess.CalledProcessError as error:
            raise Unmeasured(f"simulator {device.udid} did not boot: {error}")
        return xctest(*run(["xcodebuild", "test", "-scheme", "StaticSVG",
                            "-destination", f"platform=iOS Simulator,id={device.udid}", "-destination-timeout", "600",
                            "-jobs", JOBS, "-parallel-testing-enabled", "NO", "-collect-test-diagnostics", "never",
                            "-derivedDataPath", BUILD / "ios-derived-data", "-resultBundlePath", results],
                           timeout=7200))


def tree():
    """The checkout's tracked and untracked state, which no step may change."""
    return subprocess.run(["git", "status", "--porcelain=v1", "-z", "--untracked-files=all"], cwd=ROOT,
                          capture_output=True, check=True, timeout=60).stdout + \
        subprocess.run(["git", "diff", "HEAD", "--binary"], cwd=ROOT, capture_output=True, check=True, timeout=60).stdout


STEPS = [
    ("gate tests", own_tests),
    ("documentation", lambda: eng_check("docs", "check")),
    ("spelling", lambda: eng_check("spelling")),
    ("macOS debug", lambda: swift_suite("debug")),
    ("macOS optimized", lambda: swift_suite("release", "-c", "release", "-Xswiftc", "-enable-testing")),
    ("iOS simulator", ios_suite),
]


def gate(steps=STEPS):
    """Run every step and return the exit status: 1 if any failed, else 3 if any is unmeasured."""
    commit = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True,
                            check=True, timeout=60).stdout.strip()
    before = tree()
    results = []
    for name, step in steps:
        print(f"\n=== {name}", flush=True)
        try:
            results.append((name, "passed", step()))
        except Failed as error:
            results.append((name, "failed", str(error)))
        except Unmeasured as error:
            results.append((name, "unmeasured", str(error)))
        except subprocess.TimeoutExpired as error:
            # A hang bound expired, which a busy host can also do: no result, not a failure.
            command = error.cmd[0] if isinstance(error.cmd, (list, tuple)) else error.cmd
            results.append((name, "unmeasured", f"`{command}` gave no result within {error.timeout:g} s"))
        except subprocess.CalledProcessError as error:
            # simctl could not list, shut down or delete: the step's own result is lost.
            results.append((name, "unmeasured", str(error)))
    if tree() != before:
        results.append(("checkout", "failed", "a step changed the checkout"))
    renderer = ("the local Resvg/Resvg.xcframework (STATICSVG_LOCAL_RESVG=1)"
                if os.environ.get("STATICSVG_LOCAL_RESVG") == "1" else "the release asset Package.swift names")
    print(f"\n=== Gate for {commit}" + ("" if before == b"" else ", with local changes") + f", renderer {renderer}")
    for name, outcome, detail in results:
        print(f"{outcome:>10}  {name}: {detail}")
    outcomes = {outcome for _, outcome, _ in results}
    return 1 if "failed" in outcomes else 3 if "unmeasured" in outcomes else 0


def main(arguments):
    if arguments:
        # The gate is whole: a filter passed through `eng run gate -- …` would select part of it.
        print("gate.py takes no arguments; filter the tests lane instead (doc/testing.md)", file=sys.stderr)
        return 2
    def stopped(*_):
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        raise Stopped()
    signal.signal(signal.SIGTERM, stopped)
    signal.signal(signal.SIGINT, stopped)
    try:
        return gate()
    except Stopped:
        print("\nThe gate was stopped: what it started has ended, and its result is unmeasured.", flush=True)
        return 3


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
