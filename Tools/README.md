# CkTests offline log tools

Host-side scripts that read what a test run left in a log; nothing here builds or runs tests.

- `shadow_report.py` — folds a run's `[SHADOW-CMP]` lines into an offline shadow table. It is NOT
  the in-world `schema=1` table: it carries no `partial_disagree`, `containment_escapes` or
  `len_delta_rel` columns, and its p95 is nearest-rank — so its header token is
  `offline-aggregate=1`. `--check <log> <expected.txt>` re-derives the table and byte-compares it.

`expected/P3-3D-S2-Crowd.shadow.txt` is the tool's output over `Saved/Logs/P3-3D-S2-Crowd.log` (the PHASE_3 3D shadow sweep, 2026-09-02) and is what `--check` compares against; the log itself is not committed, so the check runs only on a machine that has it.
