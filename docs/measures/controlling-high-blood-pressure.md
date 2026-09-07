# Controlling High Blood Pressure — Million Hearts (CRS v25, §2.6.2)

- Spec: `evidence/crs-v25/spec/controlling-high-blood-pressure.txt`
- M: `BGPXD22.m` (`BPCPT`), `BGPXD21A.m` (`BPCPTD`), mean-BP logic reached from
  `BGPXD2.m` (`DMBP`, `MEANBP`) for the diabetic-BP variant; BGP v25.1 Build 98
- Taxonomies: `[BGP HYPERTENSION DXS]`, `[BGP ESRD CPTS]`, `[BGP ESRD PMS DXS]`,
  `[BGP ESRD PROCS]`, pregnancy ICD-10 set (→ #83–#85)

## Denominator (GPRA — NQF 0018)

**User Population** patients ages **18–85** (age as of period end) with:

- **hypertension**: POV or Problem List entry (status not Inactive/Deleted),
  ICD-9 401.\* / ICD-10 I10, **during the Report Period or the year prior** —
  or SNOMED set PXRM ESSENTIAL HYPERTENSION (Problem List only);
- **no documented history of ESRD — ever** (CPT, diagnosis, or procedure sets);
- **no current diagnosis of pregnancy** (Reproductive Factors "Currently Pregnant"
  = Yes during the period, or a qualifying visit with a pregnancy POV where the
  primary provider is not a CHR [code 53]).

## Numerator (GPRA)

BP **< 140/90** — systolic < 140 AND diastolic < 90.

## Selection rules

- CRS uses the **last blood pressure documented during the Report Period**.
- **Same-day tie-break favors control**: if more than one BP is documented on that
  day, CRS first looks for a reading < 140/90; if none, a reading < 150/90 (spec
  text; encode and probe-confirm).

## Divergence flags

- Demo measure `ControllingHighBloodPressure`: no ESRD/pregnancy exclusions,
  hypertension matched ever (not period-or-year-prior), Active-Clinical-less base,
  most-recent-BP without the same-day controlled-preference tie-break. Not CRS
  behavior. Fenced as demo.
- Hypertension dx **window** (period + prior year) and **status not Inactive** are
  easy to miss — both spec-explicit.

## Open questions (differential probing, #99)

1. Which BP records qualify (V Measurement sources, ER-visit handling) — read the
   `MEANBP` implementation fully; the routine name suggests averaging behavior the
   prose doesn't mention.
2. Multiple same-day BPs across different visits vs one visit.
3. Age boundary at exactly 18 / 85 on period end.
