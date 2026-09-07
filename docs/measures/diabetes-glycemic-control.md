# Diabetes: Glycemic Control (CRS v25, §2.1.2)

- Spec: `evidence/crs-v25/spec/diabetes-glycemic-control.txt`
- M: `BGPXD2.m` (labels `DMGC`, `HGBA1C`), helpers `BGPXDU.m`; BGP v25.1 Build 98
- Taxonomies: `[SURVEILLANCE DIABETES]`, `PXRM DIABETES` (SNOMED, Problem List
  only), `[BGP HGBA1C CPTS]`, `[BGP HGBA1C LOINC CODES]`, site-populated
  `DM AUDIT HGB A1C TAX` (→ #83–#85)

## Denominator (GPRA)

**User Pop Diabetic**: User Population patients with

1. diabetes diagnosed **prior to** the Report Period — first DM POV in V POV or a
   Problem List entry (status not Deleted) with date of onset / date entered before
   the period start; ICD-9 250.00–250.93, ICD-10 E10.\*–E13.\*, or SNOMED set
   PXRM DIABETES (Problem List only);
2. **at least two visits during** the Report Period;
3. **two DM-related visits ever** OR a DM Problem List entry.

**No age band.** (The UDS/eCQM analog restricts to 18–75; CRS GPRA does not.)

Naming note: this **User Pop Diabetic** cohort applies the diabetes qualifier to
the User Population base. The spec separately defines **Active Diabetic** (same
qualifier on the Active Clinical base) for other measures — see `populations.md`.

## Numerators

1. A1c documented during the Report Period.
2. **GPRA: Poor control — A1c > 9.**
3. A1c ≥ 7 and < 8.
4. Good control — A1c < 8.

## Selection rules (M-verified, `HGBA1C^BGPXD2`)

- Candidate tests: V LAB entries matching the site `DM AUDIT HGB A1C TAX` taxonomy
  or the `BGP HGBA1C LOINC CODES` LOINC taxonomy, ordered by **result date/time,
  falling back to visit date/time** when the result date is blank; plus CPT
  evidence 3044F/3046F/3051F/3052F (V CPT and transaction files).
- Most recent candidate wins; a result literal of `COMMENT` is skipped; `<`/`>`
  prefixed result strings are handled; CPT band codes map directly (3046F → the
  >9 numerator, 3044F → <8, 3051F → ≥7<8 and <8).
- **A patient with no documented A1c is NOT in the poor-control numerator** — the
  function returns "not done" and no band flag is set; "no documented A1c" is a
  separate patient list. This is the opposite of the UDS/eCQM convention
  (missing = poor). M-verified.
- Same-day pair where one test has a result and one does not → the test with the
  result; both with results → the last test on the visit (spec text; confirm exact
  ordering in differential probing — reverse-time subscripting makes the tie-break
  subtle). **INTERIM ENGINE CHOICE (loud):** among same-day resulted candidates
  the engine currently keeps ingest order (dates are day-granular; result times
  and visit linkage are not yet carried) — settle by probe, then carry times.
- **Problem List date rule (M-verified, `PLTAXNDR^BGPXDU`):** a Date of Onset
  ALONE governs when present; Date Entered applies only when onset is absent.
- **CPT candidates are the four band codes only** (M-verified: the `HGBA1C`
  CPT loop queries 3044F/3046F/3051F/3052F). Non-band [BGP HGBA1C CPTS] codes
  (83036/83037/3047F) reach a fallback (`HCPT`) the M pass has not read —
  their "documented" effect is open, not implemented.
- **Probe question:** `PLTAXNDR^BGPXDU` takes a skip-Inactive flag and at least
  one diabetes call site passes it as 1 — possibly contradicting the prose
  "status is not Deleted" (which would let Inactive count). Settle which call
  computes the §2.1.2 denominator before trusting either reading.

## Divergence flags

- Demo measure `DiabetesHbA1cPoorControl` (UDS-shaped): 18–75 age band, missing
  A1c counted as poor, condition matched by bare code ever, no visit requirements.
  **Not CRS behavior on four counts.** The demo stays fenced; the CRS-faithful
  implementation is a separate measure class.

## Open questions (differential probing, #99)

1. Exact same-day tie-break ordering among multiple resulted tests.
2. Whether CPT evidence can supersede a later lab result (ordering between the two
   candidate sources).
3. Boundary: A1c exactly 9.0 (spec and M both say >9 excludes it — probe confirms).
