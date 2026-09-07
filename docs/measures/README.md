# CRS measure dossiers — evidence-based translation method

Rook recreates IHS CRS; **CRS's actual behavior is ground truth** (rook#2 method,
rook#99 enforcement). Every rule rook encodes must trace to pinned evidence — never
to what seems reasonable. Two evidence sources, one rule for conflicts:

- **The prose spec** — the published CRS measure-definition documents (public IHS
  documents). Extracted per-measure text lives under `evidence/crs-v25/spec/` with
  provenance headers; checksums pinned in `evidence/crs-v25/evidence.lock.json`.
- **The BGP M source** — what CRS actually computes; the parity oracle (#99) runs it.
  Cited by routine + label, pinned by checksum to a named baseline and BGP build in
  the lockfile. **Where prose and M disagree, M wins** and the disagreement is
  recorded in the dossier.

Each measure gets a dossier here: denominators, numerators, selection rules,
taxonomies referenced (join key to #83–#85), M-verified refinements the prose omits,
and **divergences** — both CRS-vs-modern-spec differences and anything rook chooses
to do differently, tagged loudly (never decided silently).

The dossiers drive two artifacts, both red-first:
- Gherkin parity features (`features/parity/`) — the executable spec, run against
  rook and against real CRS (#99 drivers).
- rook's measure implementations (#2, #65) — a measure is "done" only when parity
  holds across fixture populations including edge cohorts.

`test/parity/evidence_lock_test.rb` enforces the in-repo half of the chain:
extract checksums match the lockfile, and every dossier/feature citation resolves.
External pins (source PDF, M routines) are recorded at extraction time and
re-verified by the parity rig, which has the workspace checkout.

Version note: the M territory in-hand is **BGP v25.1 Build 98 (CRS 2025)** — so the
encoding targets **CRS v25**, not v26, even though the v26 documents exist. The
v25→v26 document diff (no measures added/retired; annual targets, code-list updates,
a few wording refinements) is applied as a delta once the oracle can run v26.
