#!/usr/bin/env python3
"""Output-level checks for production/reference identity and unavailable binaries.

Fixtures are executable version stubs, never compilers. Each run retains its
repo-local scratch directory: the fork's no-delete rule includes test fixtures.
"""

import contextlib
import io
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock

import fork_status
from oracle_lib import sha256_file


class ToolchainReportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        scratch = Path(fork_status.REPO) / "build-toolchain-correction"
        scratch.mkdir(exist_ok=True)
        cls.fixtures = Path(tempfile.mkdtemp(prefix="status-", dir=scratch))
        print(f"Retained status fixtures: {cls.fixtures}")

    def setUp(self):
        self.root = self.fixtures / self._testMethodName
        self.root.mkdir()
        self.authority = self.root / "PROMOTED" / "zig"
        self.authority.parent.mkdir()
        self.reference = self.stub("reference", "printf '0.16.0+reference\\n'")

    def stub(self, name, command):
        path = self.root / name / "bin" / "zig"
        path.parent.mkdir(parents=True)
        path.write_text("#!/bin/sh\n" + command + "\n", encoding="utf-8")
        path.chmod(0o755)
        return path

    def report(self):
        out = io.StringIO()
        # STAGE3 isolates the legacy implementation during the PRE run. It is
        # not an authority in the corrected implementation.
        with mock.patch.multiple(fork_status, create=True,
                                 PROMOTED=str(self.authority),
                                 REFERENCE_STAGE3=str(self.reference),
                                 STAGE3=str(self.reference)):
            with contextlib.redirect_stdout(out):
                fork_status.section_toolchain()
        return out.getvalue()

    def production(self, report):
        self.assertIn("reference:", report)
        return report.split("reference:", 1)[0]

    def assert_unknown(self, report, reason):
        production = self.production(report)
        self.assertIn("UNKNOWN", production)
        self.assertIn(reason, production)
        self.assertNotIn("production: PRESENT", production)
        self.assertNotIn("0.16.0+reference", production)
        self.assertIn("reference: PRESENT", report)

    def test_promoted_identity_and_reference_are_distinct(self):
        candidate = self.stub("candidate", "printf '0.16.0+candidate\\n'")
        self.authority.symlink_to(os.path.relpath(candidate, self.authority.parent))
        report = self.report()
        production = self.production(report)
        self.assertIn("production: PRESENT", production)
        self.assertIn(f"authority: {self.authority}", production)
        self.assertIn(f"resolved: {candidate}", production)
        self.assertIn("version: 0.16.0+candidate", production)
        self.assertIn(f"sha256: {sha256_file(candidate)}", production)
        self.assertNotIn("0.16.0+reference", production)
        self.assertIn("reference: PRESENT", report)
        self.assertIn(f"sha256: {sha256_file(self.reference)}", report)

    def test_missing_authority_never_falls_back(self):
        self.assert_unknown(self.report(), "ABSENT")

    def test_broken_pointer_never_falls_back(self):
        self.authority.symlink_to("missing/bin/zig")
        self.assert_unknown(self.report(), "BROKEN POINTER")

    def test_directory_target_is_unknown(self):
        self.authority.symlink_to(self.root)
        self.assert_unknown(self.report(), "not a regular file")

    def test_unexecutable_target_is_unknown(self):
        candidate = self.stub("candidate", "printf '0.16.0+candidate\\n'")
        candidate.chmod(0o644)
        self.authority.symlink_to(candidate)
        self.assert_unknown(self.report(), "PermissionError")

    def test_failed_version_is_unknown_despite_existing_file(self):
        candidate = self.stub("candidate", "printf 'version probe failed\\n' >&2; exit 7")
        self.authority.symlink_to(candidate)
        self.assert_unknown(self.report(), "zig version exited 7")

    def test_empty_version_is_unknown(self):
        candidate = self.stub("candidate", "exit 0")
        self.authority.symlink_to(candidate)
        self.assert_unknown(self.report(), "empty or multiline version")

    def test_multiline_version_is_unknown(self):
        candidate = self.stub("candidate", "printf '0.16.0\\nunexpected second line\\n'")
        self.authority.symlink_to(candidate)
        self.assert_unknown(self.report(), "empty or multiline version")

    def test_self_test_rejects_false_present_output(self):
        before = sha256_file(fork_status.__file__)
        out = io.StringIO()
        # Negative control on the emitter, in memory: the missing-input
        # predicate still holds, but the report lies. The self-test must go red.
        with mock.patch.object(fork_status, "report_binary",
                               side_effect=lambda *args: print("production: PRESENT")):
            with contextlib.redirect_stdout(out):
                result = fork_status.self_test()
        self.assertEqual(result, 1)
        self.assertIn("-> FAIL", out.getvalue())
        self.assertEqual(sha256_file(fork_status.__file__), before)


if __name__ == "__main__":
    unittest.main()
