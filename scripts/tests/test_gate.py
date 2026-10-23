"""The release gate's judgments, without running a suite."""
import contextlib
import io
from pathlib import Path
import subprocess
import sys
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import gate  # noqa: E402

PROBE_SKIPPED = ("Test Case '-[StaticSVGTests.SVGFontSizeCostTests testGeneratedProbeFixturesMatchScreen]' "
                 "skipped (0.001 seconds).\n")


def xctest_log(executed, failures=0, skipped=0, outcome="passed", cases=""):
    skips = f"with {skipped} test{'s' if skipped != 1 else ''} skipped and " if skipped else "with "
    return (cases + f"Test Suite 'StaticSVGPackageTests.xctest' {outcome} at 2026-10-23 12:00:00.000.\n"
            f"\t Executed {executed} tests, {skips}{failures} failures (0 unexpected) in 1.0 (1.0) seconds\n"
            f"Test Suite 'All tests' {outcome} at 2026-10-23 12:00:00.001.\n"
            f"\t Executed {executed} tests, {skips}{failures} failures (0 unexpected) in 1.0 (1.0) seconds\n")


class SuiteJudgmentTests(unittest.TestCase):
    def test_a_full_suite_with_nothing_skipped_passes(self):
        self.assertEqual(gate.xctest(0, xctest_log(155)), "155 tests passed, none skipped")

    def test_the_opt_in_probe_may_skip(self):
        self.assertEqual(gate.xctest(0, xctest_log(155, skipped=1, cases=PROBE_SKIPPED)),
                         "154 of 155 tests passed; skipped only the opt-in testGeneratedProbeFixturesMatchScreen")
        named = "Test case 'SVGFontSizeCostTests.testGeneratedProbeFixturesMatchScreen()' skipped on 'iPhone' (0.000 seconds)\n"
        self.assertIn("skipped only the opt-in", gate.xctest(0, xctest_log(155, skipped=1, cases=named)))

    def test_any_other_skipped_test_fails_the_suite(self):
        other = "Test Case '-[StaticSVGTests.SVGRenderingTests testDrawsAPath]' skipped (0.001 seconds).\n"
        with self.assertRaisesRegex(gate.Failed, "1 required tests skipped: SVGRenderingTests.testDrawsAPath"):
            gate.xctest(0, xctest_log(155, skipped=2, cases=PROBE_SKIPPED + other))

    def test_a_skip_the_log_does_not_name_fails_the_suite(self):
        with self.assertRaisesRegex(gate.Failed, "2 tests skipped, but the log names 1"):
            gate.xctest(0, xctest_log(155, skipped=2, cases=PROBE_SKIPPED))

    def test_a_failed_test_fails_the_suite(self):
        with self.assertRaisesRegex(gate.Failed, "1 of 155 tests failed"):
            gate.xctest(1, xctest_log(155, failures=1, outcome="failed"))

    def test_fewer_tests_than_the_floor_fail_the_suite(self):
        with self.assertRaisesRegex(gate.Failed, "ran 154 tests, fewer than 155"):
            gate.xctest(0, xctest_log(154))

    def test_a_build_failure_fails_and_a_silent_success_is_unmeasured(self):
        with self.assertRaisesRegex(gate.Failed, "exited 1 before reporting any test totals"):
            gate.xctest(1, "error: compile command failed\n")
        with self.assertRaises(gate.Unmeasured):
            gate.xctest(0, "Build complete!\n")

    def test_unittest_summaries(self):
        self.assertEqual(gate.unittest_result(0, "Ran 12 tests in 3.1s\n\nOK\n", 12), "12 tests passed, none skipped")
        with self.assertRaisesRegex(gate.Failed, "2 of 12 tests skipped"):
            gate.unittest_result(0, "Ran 12 tests in 3.1s\n\nOK (skipped=2)\n", 12)
        with self.assertRaisesRegex(gate.Failed, "failures=1"):
            gate.unittest_result(1, "Ran 12 tests in 3.1s\n\nFAILED (failures=1)\n", 12)
        with self.assertRaisesRegex(gate.Failed, "fewer than 12"):
            gate.unittest_result(0, "Ran 11 tests in 3.1s\n\nOK\n", 12)


class EngCheckTests(unittest.TestCase):
    def test_a_check_that_cannot_run_is_unmeasured_and_one_that_finds_problems_fails(self):
        missing = "eng: Shared toolkit missing at /private/tmp/apple-engineering.\n"
        with mock.patch.object(gate, "run", return_value=(2, missing)):
            with self.assertRaisesRegex(gate.Unmeasured, "`eng docs check` could not run: eng: Shared toolkit missing"):
                gate.eng_check("docs", "check")
        with mock.patch.object(gate, "run", return_value=(1, "README.md: British spelling\n")):
            with self.assertRaisesRegex(gate.Failed, "exited 1"):
                gate.eng_check("spelling")

    def test_a_check_uses_the_toolkit_the_gate_found(self):
        with mock.patch.object(gate, "run", return_value=(0, "Documentation checks passed\n")) as run:
            self.assertEqual(gate.eng_check("docs", "check"), "passed")
        self.assertEqual(run.call_args.kwargs["env"], {"VOCARO_ENGINEERING_ROOT": str(gate.TOOLKIT)})


class SimulatorTests(unittest.TestCase):
    runtimes = ('{"runtimes": [{"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-2", "isAvailable": true, '
                '"version": "27.2", "buildversion": "24B5110a", "supportedDeviceTypes": '
                '[{"name": "iPhone 17 Pro", "identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"}]}]}')

    def commands(self, device):
        commands = []
        def run(command, **_):
            commands.append([str(part) for part in command])
            return 0, xctest_log(155)
        with mock.patch.object(gate, "run", side_effect=run), \
                mock.patch.object(gate, "BUILD", Path("/nonexistent/gate")), \
                mock.patch.object(gate.lifecycle, "command", return_value=self.runtimes), \
                mock.patch.object(gate.lifecycle, "disposable", return_value=contextlib.nullcontext(device)) as disposable, \
                contextlib.redirect_stdout(io.StringIO()):
            result = gate.ios_suite()
        return result, commands, disposable

    def test_the_suite_runs_on_an_owned_device_of_the_named_runtime(self):
        result, commands, disposable = self.commands(mock.Mock(udid="UDID"))
        self.assertEqual(result, "155 tests passed, none skipped")
        self.assertEqual(disposable.call_args.args, ("com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro",
                                                     "com.apple.CoreSimulator.SimRuntime.iOS-27-2"))
        self.assertEqual(commands[0][commands[0].index("-destination") + 1], "platform=iOS Simulator,id=UDID")

    def test_a_boot_timeout_is_unmeasured(self):
        device = mock.Mock(udid="UDID")
        device.boot.side_effect = subprocess.TimeoutExpired(["xcrun", "simctl", "bootstatus"], 600)
        with self.assertRaisesRegex(gate.Unmeasured, "did not finish booting within 600 s"):
            self.commands(device)

    def test_a_missing_runtime_is_unmeasured(self):
        with mock.patch.object(gate.lifecycle, "command", return_value='{"runtimes": []}'):
            with self.assertRaisesRegex(gate.Unmeasured, "iOS-27-2 is not an available simulator runtime"):
                gate.runtime_identity()


class ParallelismTests(unittest.TestCase):
    """Admission counts the gate as one job, so it bounds what it starts."""

    def test_every_build_takes_two_jobs_and_tests_run_in_one_process(self):
        commands = []
        def run(command, **_):
            commands.append([str(part) for part in command])
            return 0, xctest_log(155)
        steps = dict(gate.STEPS)
        with mock.patch.object(gate, "run", side_effect=run), \
                mock.patch.object(gate, "BUILD", Path("/nonexistent/gate")), \
                mock.patch.object(gate, "runtime_identity", return_value=({"version": "27.2", "buildversion": "1",
                                  "identifier": "runtime"}, {"identifier": "type"})), \
                mock.patch.object(gate.lifecycle, "disposable", return_value=contextlib.nullcontext(mock.Mock(udid="UDID"))), \
                contextlib.redirect_stdout(io.StringIO()):
            for name in ("macOS debug", "macOS optimized", "iOS simulator"):
                steps[name]()
        self.assertEqual([command[:2] for command in commands],
                         [["swift", "test"], ["swift", "test"], ["xcodebuild", "test"]])
        for command in commands:
            flag = "-jobs" if command[0] == "xcodebuild" else "--jobs"
            self.assertEqual(command[command.index(flag) + 1], "2", command)
        self.assertNotIn("--parallel", commands[0] + commands[1])
        self.assertEqual(commands[1][-3:], ["release", "-Xswiftc", "-enable-testing"])
        self.assertEqual(commands[2][commands[2].index("-parallel-testing-enabled") + 1], "NO")


class OutcomeTests(unittest.TestCase):
    def outcome(self, *results):
        def step(result):
            def run():
                if isinstance(result, Exception): raise result
                return result
            return run
        with mock.patch.object(gate, "tree", return_value=b""), contextlib.redirect_stdout(io.StringIO()):
            return gate.gate([(f"step {index}", step(result)) for index, result in enumerate(results)])

    def test_only_a_run_of_passed_steps_exits_0(self):
        self.assertEqual(self.outcome("passed", "passed"), 0)
        self.assertEqual(self.outcome("passed", gate.Unmeasured("no runtime")), 3)
        self.assertEqual(self.outcome(gate.Unmeasured("no runtime"), gate.Failed("1 failed")), 1)

    def test_a_step_that_outlasts_its_hang_bound_or_loses_its_device_is_unmeasured(self):
        hung = subprocess.TimeoutExpired(["xcrun", "simctl", "list"], 120)
        self.assertEqual(self.outcome("passed", hung), 3)
        self.assertEqual(self.outcome(hung, gate.Failed("1 failed")), 1)
        self.assertEqual(self.outcome(subprocess.CalledProcessError(1, ["xcrun", "simctl", "delete"])), 3)

    def test_a_step_that_changes_the_checkout_fails_the_gate(self):
        states = iter([b"", b" M Sources/StaticSVG/SVGDocument.swift\0"])
        with mock.patch.object(gate, "tree", side_effect=lambda: next(states)), \
                contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(gate.gate([("step", lambda: "passed")]), 1)

    def test_arguments_are_refused(self):
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(gate.main(["--filter", "SVGDocumentTests"]), 2)


if __name__ == "__main__":
    unittest.main()
