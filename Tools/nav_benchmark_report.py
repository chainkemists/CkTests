#!/usr/bin/env python3
"""Validate raw NAV-BENCHMARK records, without making a performance comparison.

Usage: python nav_benchmark_report.py [--require-eligible] LOG [LOG ...]
Output is JSON containing the original records and source-log SHA256 identities.
Local correctness observations are never promoted to build-machine performance evidence.
"""

import argparse
import hashlib
import json
import math
import re
from pathlib import Path
import sys


MARKER = "[NAV-BENCHMARK] "
FIXTURE = "/CkTests/GroundNavBenchmark/Maps/GroundNavMatchedBenchmark"
SCHEDULER_KEYS = {
    "Recast.MaxPathQueriesPerFrame", "ck.Nav.MaxDeferralSeconds",
    "ck.GroundNav.MaxSearchesPerFrame", "ck.GroundNav.SliceBudgetMs",
    "ck.GroundNav.MaxIterationsPerSlice", "ck.GroundNav.MaxDeferralSeconds",
}
DEBUG_KEYS = {
    "ck.GroundNav.Debug.RetainedDraw", "ck.GroundNav.Debug.DrawMarkup",
    "ck.GroundNav.PathDiagnostics", "ck.GroundNav.Debug.CellSearchTiming",
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def number(value, name, positive=False):
    require(type(value) in (int, float), f"{name}: expected number")
    require(math.isfinite(value), f"{name}: non-finite number")
    require(value > 0 if positive else value >= 0, f"{name}: out of range")
    return value


def count(value, name):
    require(type(value) is int and value >= 0, f"{name}: expected nonnegative integer")
    return value


def reject_constant(value):
    raise ValueError(f"non-finite JSON constant: {value}")


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, f"duplicate JSON key: {key}")
        result[key] = value
    return result


def decode(payload):
    return json.loads(payload, parse_constant=reject_constant, object_pairs_hook=unique_object)


def validate_record(record, require_eligible=False):
    """Reject missing, malformed or internally inconsistent records atomically."""
    require(isinstance(record, dict), "record must be an object")
    required = {
        "schema", "mode", "provider", "purpose", "fixture", "fixtureVersion", "fixtureHash",
        "agentRadius", "agentHeight", "machine", "config", "environment", "eligible",
        "failureReason", "providerRestored", "fixtureValidated", "endpointProof", "timingScope",
        "querySamples", "completionHistogram", "frameMs", "ready", "partial", "failed",
        "completions", "goalFailures", "offSurface", "avgFrameMs", "p95FrameMs", "maxFrameMs", "fps",
        "schedulerSettings", "debugSettings", "debugEffectiveSettings", "debugRestored",
    }
    require(required <= record.keys(), f"missing fields: {sorted(required - record.keys())}")
    require(type(record["schema"]) is int and record["schema"] == 1, "unsupported schema")
    require(record["mode"] in ("QueryBurst128", "CrowdConvergence240"), "unsupported mode")
    require(record["provider"] in ("GroundNav", "Recast"), "unsupported provider")
    require(record["purpose"] == "local-correctness", "this validator only certifies local correctness")
    require(record["fixture"] == FIXTURE and type(record["fixtureVersion"]) is int
            and record["fixtureVersion"] == 1, "wrong fixture identity")
    for key in ("fixtureHash", "machine", "config", "environment", "timingScope"):
        require(isinstance(record[key], str) and bool(record[key].strip()), f"{key}: identity missing")
    require(record["environment"] in ("PIE", "Game"), "unsupported environment")
    settings = record["schedulerSettings"]
    require(isinstance(settings, dict) and SCHEDULER_KEYS <= settings.keys(),
            "schedulerSettings: incomplete provider budgets")
    for key in SCHEDULER_KEYS:
        require(isinstance(settings[key], str), f"{key}: expected recorded setting string")
        number(float(settings[key]), key)
    for field in ("debugSettings", "debugEffectiveSettings"):
        require(isinstance(record[field], dict) and DEBUG_KEYS <= record[field].keys(),
                f"{field}: incomplete debug settings")
        for key in DEBUG_KEYS:
            require(isinstance(record[field][key], str), f"{key}: expected setting string")
            number(float(record[field][key]), key)
    debug_off = all(float(record["debugEffectiveSettings"][key]) == 0 for key in DEBUG_KEYS)
    require(re.fullmatch(r"md5:[0-9a-fA-F]{32}", record["fixtureHash"]) is not None,
            "fixtureHash: expected saved-map MD5 identity")
    require(number(record["agentRadius"], "agentRadius") == 42, "wrong agent radius")
    require(number(record["agentHeight"], "agentHeight") == 192, "wrong agent height")
    for key in ("eligible", "providerRestored", "fixtureValidated", "endpointProof", "debugRestored"):
        require(type(record[key]) is bool, f"{key}: expected boolean")
    require(isinstance(record["failureReason"], str), "failureReason must be a string")
    for key in ("ready", "partial", "failed", "completions", "goalFailures", "offSurface"):
        count(record[key], key)
    has_crowd_replans = "crowdReplannedAgents" in record
    has_crowd_states = "crowdTerminalStates" in record
    require(has_crowd_replans == has_crowd_states,
            "crowdReplannedAgents and crowdTerminalStates must be present together")
    has_crowd_outcomes = has_crowd_replans
    crowd_replanned_agents = 0
    crowd_terminal_states = {}
    if has_crowd_outcomes:
        crowd_replanned_agents = count(record["crowdReplannedAgents"], "crowdReplannedAgents")
        require(crowd_replanned_agents <= 240, "crowdReplannedAgents exceeds population")
        crowd_terminal_states = record["crowdTerminalStates"]
        require(isinstance(crowd_terminal_states, dict), "crowdTerminalStates: expected object")
    for key in ("querySamples", "completionHistogram", "frameMs"):
        require(isinstance(record[key], list), f"{key}: expected array")
    for key in ("avgFrameMs", "p95FrameMs", "maxFrameMs", "fps"):
        number(record[key], key)

    samples = record["querySamples"]
    indices = set()
    statuses = {"Ready": 0, "Partial": 0, "Failed": 0}
    all_timed = True
    for sample in samples:
        require(isinstance(sample, dict), "query sample must be an object")
        fields = {"index", "start", "end", "latencyFrames", "latencyMs", "searchMs",
                  "hasSearchTiming", "length", "status"}
        require(fields <= sample.keys(), "query sample is missing fields")
        index = count(sample["index"], "index")
        require(index < 128 and index not in indices, "duplicate or out-of-range query index")
        indices.add(index)
        for key in ("start", "end"):
            point = sample[key]
            require(isinstance(point, list) and len(point) == 3, f"{key}: expected three coordinates")
            require(all(type(v) in (int, float) and math.isfinite(v) for v in point),
                    f"{key}: invalid coordinates")
        angle = 2 * math.pi * index / 128
        expected_start = [1400 * math.cos(angle), 900 * math.sin(angle), 0]
        expected_end = [-expected_start[0], -expected_start[1], 0]
        for key, expected_point in (("start", expected_start), ("end", expected_end)):
            require(all(math.isclose(a, b, abs_tol=1e-4, rel_tol=1e-8)
                        for a, b in zip(sample[key], expected_point)),
                    f"{key}: query endpoints differ from fixture workload")
        count(sample["latencyFrames"], "latencyFrames")
        for key in ("latencyMs", "searchMs", "length"):
            number(sample[key], key)
        require(type(sample["hasSearchTiming"]) is bool, "hasSearchTiming must be boolean")
        all_timed = all_timed and sample["hasSearchTiming"]
        require(sample["status"] in statuses, "unknown terminal query status")
        statuses[sample["status"]] += 1
    histogram = record["completionHistogram"]
    for value in histogram:
        count(value, "completionHistogram")
    require(sum(histogram) == len(samples), "histogram does not account for every terminal query")
    for sample in samples:
        require(sample["latencyFrames"] < len(histogram), "latency outside histogram")
    observed = [0] * len(histogram)
    for sample in samples:
        observed[sample["latencyFrames"]] += 1
    require(observed == histogram, "histogram does not match per-query latency frames")

    frames = record["frameMs"]
    for value in frames:
        number(value, "frameMs", positive=True)
    expected = (0, 0, 0, 0)
    if frames:
        total = math.fsum(frames)
        require(math.isfinite(total), "frame duration sum overflow")
        average = total / len(frames)
        expected = (average, sorted(frames)[math.ceil(0.95 * len(frames)) - 1],
                    max(frames), 1000 / average)
    for key, value in zip(("avgFrameMs", "p95FrameMs", "maxFrameMs", "fps"), expected):
        require(math.isclose(record[key], value, rel_tol=1e-5, abs_tol=1e-4),
                f"{key}: differs from raw frame samples")

    if record["mode"] == "QueryBurst128":
        if has_crowd_outcomes:
            require(crowd_replanned_agents == 0 and not crowd_terminal_states,
                    "query burst must report empty crowd outcomes")
        require(not frames, "query burst must not contain a crowd sample")
        require(record["completions"] == len(samples), "query completion count disagrees with raw queries")
        require(record["goalFailures"] == 0 and record["offSurface"] == 0,
                "query burst must not contain crowd outcome counts")
        require((record["ready"], record["partial"], record["failed"]) ==
                (statuses["Ready"], statuses["Partial"], statuses["Failed"]),
                "terminal counts disagree with raw queries")
        body_eligible = len(samples) == 128 and statuses["Ready"] == 128 and all_timed
    else:
        if has_crowd_outcomes and crowd_terminal_states:
            expected_state_keys = {"Walking", "PathPending", "Idle", "None"}
            require(set(crowd_terminal_states) == expected_state_keys,
                    "crowdTerminalStates: expected Walking, PathPending, Idle, None")
            for key in expected_state_keys:
                count(crowd_terminal_states[key], f"crowdTerminalStates.{key}")
            require(sum(crowd_terminal_states.values()) == 240,
                    "crowdTerminalStates does not account for population")
        require(not samples and not histogram, "crowd sample must not contain a query burst")
        require(record["completions"] <= 240 and record["goalFailures"] <= 240
                and record["offSurface"] <= 240, "crowd count exceeds population")
        body_eligible = bool(frames) and record["ready"] == 240 and record["goalFailures"] == 0 \
            and record["offSurface"] == 0 and record["partial"] == 0 and record["failed"] == 0
        if has_crowd_outcomes:
            body_eligible = body_eligible and bool(crowd_terminal_states) \
                and crowd_terminal_states["None"] == 0
    eligible = body_eligible and record["providerRestored"] and record["fixtureValidated"] \
        and record["endpointProof"] and record["debugRestored"] and debug_off and not record["failureReason"]
    require(record["eligible"] == eligible, "eligibility contradicts raw evidence")
    require(eligible or bool(record["failureReason"]), "ineligible record must explain why")
    if require_eligible:
        require(eligible, f"ineligible workload: {record['failureReason']}")
    return record


def read_reports(paths, require_eligible=False):
    records, sources = [], []
    for path in paths:
        raw = Path(path).read_bytes()
        sources.append({"path": str(path), "sha256": hashlib.sha256(raw).hexdigest()})
        for line_number, line in enumerate(raw.decode("utf-8-sig", errors="strict").splitlines(), 1):
            if MARKER not in line:
                continue
            try:
                record = validate_record(decode(line.split(MARKER, 1)[1]), require_eligible)
            except (ValueError, TypeError, OverflowError) as error:
                raise ValueError(f"{path}:{line_number}: {error}") from error
            records.append(record)
    require(bool(records), "no NAV-BENCHMARK records found")
    return {"schema": 1, "evidenceClass": "local-correctness-only", "sources": sources, "records": records}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--require-eligible", action="store_true")
    parser.add_argument("logs", nargs="+")
    args = parser.parse_args()
    try:
        result = read_reports(args.logs, args.require_eligible)
    except (OSError, UnicodeError, ValueError) as error:
        print(f"NAV-BENCHMARK rejected: {error}", file=sys.stderr)
        return 1
    print(json.dumps(result, indent=2, allow_nan=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
