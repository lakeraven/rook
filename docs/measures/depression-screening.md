# Depression Screening (CRS v25, §2.5.4)

- Spec: `evidence/crs-v25/spec/depression-screening.txt`
- M: `BGPXD25.m`, `BGPXD27.m`, `BGPXPC11.m`; BGP v25.1 Build 98
- Taxonomies: `[BGP DEPRESSION SCRN DXS]`, `[BGP DEPRESSION SCREEN CPTS]`,
  `[BGP MOOD DISORDERS]` (→ #83–#85)

## Denominators

1. Active Clinical patients **12–17**.
2. Active Clinical patients **18+**.
3. **GPRA**: User Population **12–17**, broken down by sex.
4. **GPRA**: User Population **18+**, broken down by sex.
5. **Active Diabetic** patients, by sex — the diabetes qualifier applied to the
   **Active Clinical** base (NOT the User Pop Diabetic cohort of §2.1.2); see
   `populations.md` for the two-cohort distinction.

## Numerator (GPRA)

Screened for depression **OR diagnosed with a mood disorder** at any time during
the Report Period (refusals excluded). Sub-numerators: screened; mood-disorder
diagnosed; screened in a Behavioral Health clinic (codes C4, C9, 14, 43, 48).

- **Screening** is any of: exam code 36; POV ICD-10 Z13.3\*; CPT 1220F / 3725F /
  G0444; BHS problem code 14.1; **measurement of PHQ-9, PHQ-T, or EPDS**.
- **Mood disorder**: at least **two visits** during the period with a POV from
  `[BGP MOOD DISORDERS]` (or BHS POV 14/15).
- Visit data can come from **PCC or BHS**.

## Selection rules (M-glimpsed, verify in full pass)

- BH exam-36 records count only with a result of **P or N** (`^AMHREC` result
  check in `BGPXD25`/`BGPXPC11`) — refusals (result R) excluded, matching the
  spec's "does not include refusals" note. Confirm the result-code set.

## Divergence flags

- Demo measure `Gpra::DepressionScreening`: single 12+ denominator, PHQ-9-only
  numerator, no mood-disorder arm, no refusal handling, no BH data source. Not CRS
  behavior. Fenced as demo.
- CRS splits 12–17 / 18+ and reports GPRA on **User Population** (not Active
  Clinical) — the Active Clinical variants are the non-GPRA denominators here.

## Open questions (differential probing, #99)

1. Full BH exam result-code semantics (P/N/R and anything else).
2. Whether the two-visit mood-disorder rule requires distinct days.
3. EPDS/PHQ-T measurement capture paths in PCC (V Measurement type codes).
