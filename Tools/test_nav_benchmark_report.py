"""Offline schema tests; synthetic records are not runtime or performance evidence."""

import copy
import json
import math
import tempfile
import unittest
from pathlib import Path

import nav_benchmark_report as report


def valid_query():
    samples = []
    for index in range(128):
        angle = 2 * math.pi * index / 128
        start = [1400 * math.cos(angle), 900 * math.sin(angle), 0]
        samples.append({"index": index, "start": start, "end": [-start[0], -start[1], 0],
                        "latencyFrames": index // 8, "latencyMs": index // 8 * 10,
                        "searchMs": 0, "hasSearchTiming": True, "length": 3000,
                        "status": "Ready"})
    return {"schema": 1, "mode": "QueryBurst128", "provider": "GroundNav",
            "purpose": "local-correctness", "fixture": report.FIXTURE, "fixtureVersion": 1,
            "fixtureHash": "md5:" + "a" * 32, "agentRadius": 42, "agentHeight": 192,
            "machine": "synthetic-unit-test", "config": "Development", "environment": "PIE",
            "eligible": True, "failureReason": "", "providerRestored": True,
            "fixtureValidated": True, "endpointProof": True, "timingScope": "provider-work",
            "schedulerSettings": {key: "8" for key in report.SCHEDULER_KEYS},
            "debugSettings": {key: "1" for key in report.DEBUG_KEYS},
            "debugEffectiveSettings": {key: "0" for key in report.DEBUG_KEYS}, "debugRestored": True,
            "querySamples": samples, "completionHistogram": [8] * 16, "frameMs": [],
            "ready": 128, "partial": 0, "failed": 0, "completions": 128,
            "goalFailures": 0, "offSurface": 0, "avgFrameMs": 0,
            "p95FrameMs": 0, "maxFrameMs": 0, "fps": 0,
            "crowdReplannedAgents": 0, "crowdTerminalStates": {}}


def valid_crowd():
    record = valid_query()
    record.update(mode="CrowdConvergence240", querySamples=[], completionHistogram=[],
                  frameMs=[10] * 19 + [20], ready=240, completions=35,
                  avgFrameMs=10.5, p95FrameMs=10, maxFrameMs=20, fps=1000 / 10.5,
                  crowdReplannedAgents=0,
                  crowdTerminalStates={"Walking": 35, "PathPending": 205, "Idle": 0, "None": 0})
    return record


class BenchmarkReportTests(unittest.TestCase):
    def test_both_modes_and_providers_accept_measured_zero(self):
        for make in (valid_query, valid_crowd):
            for provider in ("GroundNav", "Recast"):
                record = make()
                record["provider"] = provider
                self.assertIs(report.validate_record(record, True), record)

    def test_missing_each_required_field_rejects(self):
        record = valid_query()
        for key in record:
            malformed = copy.deepcopy(record)
            del malformed[key]
            with self.subTest(key=key), self.assertRaises(ValueError):
                report.validate_record(malformed)

    def test_nonfinite_negative_and_bool_numbers_reject(self):
        for value in (math.nan, math.inf, -math.inf, -1, True, "0", None):
            record = valid_query()
            record["querySamples"][0]["searchMs"] = value
            with self.subTest(value=value), self.assertRaises(ValueError):
                report.validate_record(record)

    def test_mislabeled_provider_and_capsule_reject(self):
        for key, value in (("provider", "Unknown"), ("agentRadius", 34), ("agentHeight", 96),
                           ("fixture", "/OtherMap"), ("schema", True), ("purpose", "performance")):
            record = valid_query()
            record[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                report.validate_record(record)

    def test_missing_timing_cannot_be_eligible(self):
        record = valid_query()
        record["querySamples"][0]["hasSearchTiming"] = False
        with self.assertRaisesRegex(ValueError, "eligibility"):
            report.validate_record(record)
        record.update(eligible=False, failureReason="query timing unavailable")
        report.validate_record(record)
        with self.assertRaisesRegex(ValueError, "ineligible workload"):
            report.validate_record(record, True)

    def test_counts_duplicates_and_histogram_must_reconcile(self):
        for mutation in (lambda r: r.update(ready=127),
                         lambda r: r.update(completions=127),
                         lambda r: r["completionHistogram"].__setitem__(0, 7),
                         lambda r: r["querySamples"][0].update(index=1),
                         lambda r: r["querySamples"][0].update(latencyFrames=1)):
            record = valid_query()
            mutation(record)
            with self.assertRaises(ValueError):
                report.validate_record(record)

    def test_unavailable_fixture_hash_rejects(self):
        for value in ("md5:unavailable", "unhashed", "md5:" + "g" * 32):
            record = valid_query()
            record["fixtureHash"] = value
            with self.subTest(value=value), self.assertRaisesRegex(ValueError, "fixtureHash"):
                report.validate_record(record)

    def test_missing_or_nonfinite_scheduler_budget_rejects(self):
        for value in ("unavailable", "NaN", "-1"):
            record = valid_query()
            record["schedulerSettings"]["Recast.MaxPathQueriesPerFrame"] = value
            with self.subTest(value=value), self.assertRaises(ValueError):
                report.validate_record(record)
        record = valid_query()
        del record["schedulerSettings"]["Recast.MaxPathQueriesPerFrame"]
        with self.assertRaises(ValueError):
            report.validate_record(record)

    def test_provider_specific_endpoint_snap_is_not_same_workload(self):
        record = valid_query()
        record["querySamples"][12]["start"][0] += 1
        with self.assertRaisesRegex(ValueError, "endpoints differ"):
            report.validate_record(record)

    def test_provider_restore_and_endpoint_proof_required(self):
        for key in ("providerRestored", "endpointProof", "fixtureValidated", "debugRestored"):
            record = valid_query()
            record[key] = False
            with self.subTest(key=key), self.assertRaises(ValueError):
                report.validate_record(record)

    def test_debug_drawing_cannot_be_eligible(self):
        record = valid_query()
        record["debugEffectiveSettings"]["ck.GroundNav.Debug.RetainedDraw"] = "1"
        with self.assertRaisesRegex(ValueError, "eligibility"):
            report.validate_record(record)

    def test_percentiles_fps_and_raw_frames_reconcile(self):
        for key in ("avgFrameMs", "p95FrameMs", "maxFrameMs", "fps"):
            record = valid_crowd()
            record[key] += 1
            with self.subTest(key=key), self.assertRaises(ValueError):
                report.validate_record(record)
        for value in (0, -1, math.inf):
            record = valid_crowd()
            record["frameMs"][0] = value
            with self.assertRaises(ValueError):
                report.validate_record(record)

    def test_crowd_failures_and_offsurface_reject_eligibility(self):
        for key in ("goalFailures", "offSurface", "failed", "partial"):
            record = valid_crowd()
            record[key] = 1
            with self.subTest(key=key), self.assertRaises(ValueError):
                report.validate_record(record)

    def test_modes_cannot_mix(self):
        record = valid_crowd()
        record["querySamples"] = valid_query()["querySamples"]
        record["completionHistogram"] = [8] * 16
        with self.assertRaisesRegex(ValueError, "must not contain"):
            report.validate_record(record)

    def test_historical_records_without_crowd_outcomes_remain_valid(self):
        for make in (valid_query, valid_crowd):
            record = make()
            del record["crowdReplannedAgents"]
            del record["crowdTerminalStates"]
            self.assertIs(report.validate_record(record, True), record)

    def test_crowd_outcome_fields_are_paired_and_mode_correct(self):
        for key in ("crowdReplannedAgents", "crowdTerminalStates"):
            record = valid_query()
            del record[key]
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, "present together"):
                report.validate_record(record)
        record = valid_query()
        record["crowdReplannedAgents"] = 1
        with self.assertRaisesRegex(ValueError, "empty crowd outcomes"):
            report.validate_record(record)

    def test_crowd_terminal_pathpending_is_eligible_and_invalid_sums_reject(self):
        record = valid_crowd()
        record["crowdReplannedAgents"] = 240
        record["crowdTerminalStates"] = {"Walking": 0, "PathPending": 240, "Idle": 0, "None": 0}
        self.assertIs(report.validate_record(record, True), record)
        record = valid_crowd()
        record["crowdTerminalStates"]["PathPending"] -= 1
        with self.assertRaisesRegex(ValueError, "does not account"):
            report.validate_record(record)

    def test_new_format_eligible_crowd_requires_full_terminal_states(self):
        record = valid_crowd()
        record["crowdTerminalStates"] = {}
        with self.assertRaisesRegex(ValueError, "eligibility"):
            report.validate_record(record)
        record = valid_crowd()
        record["crowdTerminalStates"]["None"] = 1
        record["crowdTerminalStates"]["Walking"] -= 1
        with self.assertRaisesRegex(ValueError, "eligibility"):
            report.validate_record(record)

    def test_json_duplicate_keys_and_nonfinite_constants_reject(self):
        for payload in ('{"schema":1,"schema":1}', '{"value":NaN}', '{"value":Infinity}'):
            with self.assertRaises(ValueError):
                report.decode(payload)

    def test_logs_atomic_rejection_and_source_hash(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "synthetic.log"
            path.write_text("preamble\n" + report.MARKER + json.dumps(valid_query()) + "\n", encoding="utf-8")
            result = report.read_reports([path], True)
            self.assertEqual(len(result["records"]), 1)
            self.assertEqual(len(result["sources"][0]["sha256"]), 64)
            with path.open("a", encoding="utf-8") as output:
                output.write(report.MARKER + '{"schema":1}\n')
            with self.assertRaisesRegex(ValueError, "missing fields"):
                report.read_reports([path])

    def test_empty_logs_do_not_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "empty.log"
            path.write_text("No matching record", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "no NAV-BENCHMARK"):
                report.read_reports([path])


if __name__ == "__main__":
    unittest.main()
