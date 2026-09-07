# Parity step vocabulary — canonical seed facts

Every Given step maps to a **deterministic** bundle of PCC/BHS-level facts, so
the rook driver and the CRS FileMan-seeding driver (#99) materialize the SAME
patient from the same scenario. A driver may not invent or default anything not
listed here; a fact a scenario needs that this vocabulary can't express gets a
new explicit step, never a looser parse.

## Patient macros

**`a User Population patient "X" aged N at period end`**
- Sex female; use `a male User Population patient …` to override.
- Born exactly `period_end − N years − 183 days` (mid-year offset keeps the age
  unambiguous at both period boundaries).
- Beneficiary 01 (AI/AN); resides in a community in the site's GPRA community
  taxonomy; alive at period end.
- One qualifying User-Population visit: **ambulatory** (service category A),
  general clinic (code 01), dated `period_start − 6 months`.
- NOT Active Clinical unless visits added by other steps qualify it (User
  Population requires one visit in 3 years; Active Clinical requires two
  face-to-face medical-clinic visits, one core — seed only what's stated).

**`a qualifying GPRA diabetic patient "X"`** ≡ User Population patient aged 50
(above) + diabetes POV (below) first recorded `2018-06-15` + diabetes Problem
List entry (status Active, entered `2018-06-15`) + 2 ambulatory visits (service
category A, clinic 01) during the period at `period_start + 60d` and
`period_start + 240d`.

**`an otherwise-qualifying patient "X" aged N with beneficiary class "<c>"`** /
**`an otherwise-qualifying patient "X" aged N outside the GPRA community taxonomy`**
— the User Population macro with exactly one attribute changed (beneficiary
class, or community flag false). For population-fence scenarios.

**`a qualifying GPRA hypertensive patient "X"`** ≡ User Population patient aged
62 (above) + hypertension POV (below) recorded `period_start + 30d`; no ESRD
facts; not pregnant.

## Clinical facts (one step, one FileMan-shaped fact)

| Step phrase | Canonical fact |
|---|---|
| `has a diabetes POV first recorded <date>` | V POV ICD-10 **E11.9** on an ambulatory visit (svc cat A, clinic 01) dated `<date>` |
| `has a diabetes Problem List entry with status "<s>" entered <date>` | Problem List **E11.9**, status `<s>`, date entered `<date>`, no onset date |
| `has a diabetes Problem List entry with status "<s>" onset <d1> entered <d2>` | Problem List **E11.9**, status `<s>`, onset `<d1>`, date entered `<d2>` |
| `has a hypertension Problem List entry with status "<s>" entered <date>` | Problem List **I10**, status `<s>`, date entered `<date>`, no onset date |
| `has a depression screening POV recorded <date>` | V POV ICD-10 **Z13.31**, ambulatory visit dated `<date>` |
| `has an EPDS measurement recorded <date>` | V MEASUREMENT type **EPDS** (score 6) on an ambulatory visit dated `<date>` |
| `has a hypertension POV recorded <date>` | V POV ICD-10 **I10**, ambulatory visit (svc cat A, clinic 01) dated `<date>` |
| `has an ESRD diagnosis recorded <date>` | V POV ICD-10 **N18.6**, ambulatory visit dated `<date>` |
| `is documented currently pregnant during the report period` | Reproductive Factors "Currently Pregnant" = Yes, recorded `period_start + 30d` |
| `has an A1c lab result of <v> resulted <date>` | V LAB, test in site taxonomy `DM AUDIT HGB A1C TAX` (LOINC **4548-4**), result `<v>`, result date/time `<date> 09:00` |
| `has an A1c lab test with no result on <date>` | Same test, blank result, visit date `<date> 08:00` |
| `has no A1c documented during the report period` | Absence — seed nothing |
| `has CPT "<code>" recorded <date>` | V CPT `<code>` dated `<date>` (visit linkage deferred — the driver emits a Procedure without an Encounter until the contract carries lab/CPT visit links) |
| `has a BP reading of <s>/<d> on <date> at an ambulatory visit` | V MEASUREMENT type BP `<s>/<d>` on an ambulatory visit (svc cat A, clinic 01 — **never ER/clinic 30**: ER handling of BP readings is an OPEN #99 question, so seeds stay on unambiguous visits; the engine does not yet enforce an ER exclusion) dated `<date>` |
| `has no BP reading during the report period` | Absence — seed nothing |
| `has <n> ambulatory visit(s) during the report period` | `<n>` visits, svc cat A, clinic 01, evenly spaced from `period_start + 60d` |
| `has <n> hospitalization(s) during the report period` | `<n>` visits, class `IMP` (svc cat H), clinic 01, evenly spaced from `period_start + 60d` |
| `has a BP reading of <s>/<d> on <date> at an ER visit` | Same BP fact on a visit with **clinic 30** (excluded setting) |
| `died on <date>` | `Patient.deceasedDateTime` = `<date>` |
| `has a PHQ-9 measurement recorded <date>` | V MEASUREMENT type **PHQ9** (score 4) on an ambulatory visit dated `<date>` |
| `has a mood disorder POV recorded <date>` | V POV ICD-10 **F32.9**, ambulatory visit dated `<date>` (distinct visit per step) |
| `has a BHS depression screening (problem code 14.1) recorded <date>` | BHS visit, problem code 14.1, dated `<date>` |
| `has a BH depression screening exam recorded <date> with result "<r>"` | BHS record, exam code 36, result `<r>` (`^AMHREC` result field), dated `<date>` |
| `has no depression screening during the report period` | Absence — seed nothing |
| `has no hypertension Problem List entry` | Absence — seed nothing |

## Membership labels (Then side)

`"<label>" GPRA denominator/numerator`, `"<label>" numerator`, and
`"<label>" patient list` name CRS report lines:

- `Diabetes: Glycemic Control` — the GPRA denominator (User Pop Diabetic)
- `Poor Glycemic Control` — GPRA numerator (A1c > 9)
- `Good Glycemic Control` — non-GPRA numerator (A1c < 8)
- `Controlling High Blood Pressure` — GPRA denominator 1 / numerator 1 (NQF 0018)
- `Depression Screening 12-17` / `Depression Screening 18+` — the two GPRA
  (denominator, numerator) strata of §2.5.4 (one numerator definition applied
  per denominator; the suffix names the stratum, not a separate spec numerator)
- `diabetic patients without a documented A1c` — patient list (§2.1.2.7)
