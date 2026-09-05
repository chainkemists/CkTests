#!/usr/bin/env python3
"""Folds the [SHADOW-CMP] lines a shadow run leaves in a log into an offline shadow table.

The shadow comparison writes one [SHADOW-CMP] line per query while a world is alive. The in-world
report is assembled from a diagnostics fragment that dies with that world, so this tool re-derives
the same table offline from the log instead - in whatever order the tests happened to run, and
across as many logs as a single sweep was split over.

Usage:
    shadow_report.py <log> [<log> ...]
        Fold every named log into one table and write it to stdout.

    shadow_report.py --check <log> <expected.txt>
        Re-derive the table from <log> and compare it byte for byte against <expected.txt>.
        Exit 0 when they are identical, 1 when they are not (the first differing line is named).

The table is written with LF terminators whatever the host platform uses, for the same reason the
in-world report is: a table captured on one machine is compared against one captured on another.
"""

import collections
import math
import re
import sys

COMPARISON_PATTERN = re.compile(r"\[SHADOW-CMP\]\s*(.*)$")

SUCCESS_STATUSES = ("Ready", "Partial")

HEADER = ("fixture|comparisons|both_succeeded|recast_only|groundnav_only|both_failed|"
          "failreason_agree|failreason_disagree|len_delta_uu_mean|len_delta_uu_p95|"
          "len_delta_uu_max|endpoint_uu_mean|endpoint_uu_p95|endpoint_uu_max|"
          "wp_delta_mean|wp_delta_max|recast_ms_mean|groundnav_ms_mean|status_pairs")

ROW_FORMAT = ("[SHADOW-REPORT] row=%s|%d|%d|%d|%d|%d|%d|%d|%.3f|%.3f|%.3f|%.3f|%.3f|%.3f|"
              "%.4f|%d|%.4f|%.4f|%s")


def is_success(status):
    return status in SUCCESS_STATUSES


def read_rows(log_paths):
    """Every [SHADOW-CMP] payload in the named logs, split into its fields, in log order."""
    rows = []
    for log_path in log_paths:
        with open(log_path, encoding="utf-8", errors="replace") as log:
            for line in log:
                match = COMPARISON_PATTERN.search(line)
                if match is None:
                    continue
                fields = match.group(1).strip().split("|")
                # Older runs wrote the fixture key and the query revision as two fields.
                if len(fields) == 14:
                    fields = [fields[0], fields[1] + "#" + fields[2]] + fields[3:]
                rows.append(fields)
    return rows


def get_stats(values):
    """(mean, nearest-rank p95, max) over a sample; all zero when the sample is empty."""
    if not values:
        return (0.0, 0.0, 0.0)
    ordered = sorted(values)
    p95 = ordered[min(len(ordered) - 1, int(math.ceil(0.95 * len(ordered)) - 1))]
    return (sum(values) / len(values), p95, max(values))


def format_report(rows):
    """The whole table as one LF-terminated string."""
    by_fixture = collections.defaultdict(list)
    for row in rows:
        if len(row) >= 13:
            by_fixture[row[0]].append(row)

    lines = ["[SHADOW-REPORT] offline-aggregate=1 (not the in-world schema=1 table: no "
             "partial_disagree, containment_escapes or len_delta_rel columns)",
             "[SHADOW-REPORT] header=" + HEADER]

    for fixture in sorted(by_fixture):
        fixture_rows = by_fixture[fixture]
        count = len(fixture_rows)

        both_ok = sum(1 for r in fixture_rows if is_success(r[2]) and is_success(r[4]))
        recast_only = sum(1 for r in fixture_rows if is_success(r[2]) and not is_success(r[4]))
        groundnav_only = sum(1 for r in fixture_rows if not is_success(r[2]) and is_success(r[4]))
        both_failed = count - both_ok - recast_only - groundnav_only

        reason_agree = sum(1 for r in fixture_rows
                           if not is_success(r[2]) and not is_success(r[4]) and r[3] == r[5])
        reason_disagree = sum(1 for r in fixture_rows
                              if not is_success(r[2]) and not is_success(r[4]) and r[3] != r[5])

        length_deltas = [abs(float(r[9]) - float(r[8])) for r in fixture_rows
                         if is_success(r[2]) and is_success(r[4])]
        endpoint_deltas = [float(r[10]) for r in fixture_rows
                           if is_success(r[2]) and is_success(r[4])]
        waypoint_deltas = [int(r[7]) - int(r[6]) for r in fixture_rows
                           if is_success(r[2]) and is_success(r[4])]

        recast_ms = [float(r[11]) for r in fixture_rows]
        groundnav_ms = [float(r[12]) for r in fixture_rows]

        status_pairs = collections.Counter("%s/%s" % (r[2], r[4]) for r in fixture_rows)

        length_stats = get_stats(length_deltas)
        endpoint_stats = get_stats(endpoint_deltas)

        lines.append(ROW_FORMAT % (
            fixture, count, both_ok, recast_only, groundnav_only, both_failed,
            reason_agree, reason_disagree,
            length_stats[0], length_stats[1], length_stats[2],
            endpoint_stats[0], endpoint_stats[1], endpoint_stats[2],
            (sum(waypoint_deltas) / len(waypoint_deltas) if waypoint_deltas else 0.0),
            (max(waypoint_deltas, key=abs) if waypoint_deltas else 0),
            (sum(recast_ms) / count if count else 0.0),
            (sum(groundnav_ms) / count if count else 0.0),
            ";".join("%s=%s" % (pair, seen) for pair, seen in sorted(status_pairs.items()))))

    diverging = sorted(set(
        row[1] for row in rows
        if len(row) >= 13 and (is_success(row[2]) != is_success(row[4])
                               or (not is_success(row[2]) and row[3] != row[5]))))

    lines.append("[SHADOW-REPORT] diverging=" + (",".join(diverging) if diverging else "-"))
    lines.append("[SHADOW-REPORT] comparisons=%d" % len(rows))

    return "".join(line + "\n" for line in lines)


def report_first_difference(derived, expected):
    derived_lines = derived.split(b"\n")
    expected_lines = expected.split(b"\n")

    for index in range(max(len(derived_lines), len(expected_lines))):
        got = derived_lines[index] if index < len(derived_lines) else None
        want = expected_lines[index] if index < len(expected_lines) else None
        if got == want:
            continue
        sys.stderr.write("[SHADOW-CHECK] differs at line %d\n" % (index + 1))
        sys.stderr.write("  expected: %r\n" % (want,))
        sys.stderr.write("  derived:  %r\n" % (got,))
        break

    if derived.replace(b"\r\n", b"\n") == expected.replace(b"\r\n", b"\n"):
        sys.stderr.write("[SHADOW-CHECK] the two differ only in their line terminators\n")


def main(argv):
    if argv and argv[0] == "--check":
        if len(argv) != 3:
            sys.stderr.write("usage: shadow_report.py --check <log> <expected.txt>\n")
            return 2

        derived = format_report(read_rows([argv[1]])).encode("utf-8")
        with open(argv[2], "rb") as expected_file:
            expected = expected_file.read()

        if derived == expected:
            sys.stdout.write("[SHADOW-CHECK] match %s\n" % argv[2])
            return 0

        report_first_difference(derived, expected)
        return 1

    if not argv:
        sys.stderr.write(__doc__)
        return 2

    sys.stdout.buffer.write(format_report(read_rows(argv)).encode("utf-8"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
