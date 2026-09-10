# G0 groundwork evidence — 2026-09-10

**STATUS:** PASS for static groundwork only. All F0–F4 runtime tests NOT RUN.

**DONE:** Foundation documents, original report archive, starter JSON, Python tools/tests, pinned CI configuration and handoff.

**EXPECT:** A coding agent can reproduce the static checks and begin the Windows integration spike without recovering the old chat or repeating broad research.

**TEST:**

| Check | Actual result | Scope |
|---|---|---|
| `python tools/validate_foundation.py` | PASS | Fixture references/defaults/reachability, bounds/placement cases, archive manifest shape, original-report hash and local Markdown targets |
| `python -m unittest discover -s tests -v` | 16 tests PASS | Positive fixture; rejection of malformed data, deadlock, conflicting keys, overlap; synthetic archive corruption/missing/size cases |
| Original report | 45,440 bytes; SHA-256 `f238c37f3f9509b2a152e632503b7a4e16ab8fd4377dcc32122717e30c13cebd` | Byte-preserved source |
| Official release/API inspection | Candidate editor/template assets and digests verified | Metadata only |
| Windows T01–T30 | NOT RUN | No engine/runtime in this delivery |

**LIMITATIONS/FAILURES:** No game runtime is implemented or tested. Crafting reachability assumes renewable/sufficient quantities and ignores spatial access. Placement oracle checks cells, not Godot collision or rotations. External links/anchors are not automatically validated. Archive verification tests use synthetic bytes, not real engine downloads. Remote CI status must be inspected separately.

**NEXT:** F0 Windows integration; resolve the real safe terrain/database checkpoint barrier before relying on persistence.

**GIT/REPRODUCIBILITY:** Python 3.12.14, Linux; run from repo root, no third-party Python packages. Data versions are `schema_version=1`, `content_version=foundation-1`, `generator_version=flat_fixture_1`. Candidate runtime metadata is in `tools/versions.json`. Exact branch/commit is available from the Git checkout containing this evidence.
