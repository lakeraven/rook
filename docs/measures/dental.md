# Dental Group: Access, Sealants, Topical Fluoride (CRS v25, §2.2)

- Spec: `evidence/crs-v25/spec/dental.txt` (§2.2.1–2.2.3)
- Populations: `evidence/crs-v25/spec/populations.txt` (User Population)
- M: `BGPXD21.m` (I9, Access), `BGPXD211.m` (DENTSRVD, DVADA), `BGPXD3.m`
  (I10 Sealants, I11 Topical Fluoride), `BGPXD3A.m` (SEAL, SEALR, SEALDEV, TF),
  `BGPXD1.m` (age variables); BGP v25.1 Build 98
- Taxonomies: `[BGP DENTAL VISIT CPT CODES]`, `[BGP DENTAL VISIT DXS]`,
  `[BGP TOPICAL FLUORIDE ADA CODES]`, `[BGP CPT TOPICAL FLUORIDE]`,
  `[BGP TOPICAL FLUORIDE DXS]` (→ #83–#85)

## Age (M-verified, applies to all three)

CRS ages these measures **as of the first day of the Report Period**, not the
last: `BGPXD1.m` sets `BGPAGEB=$$AGE^AUPNPAT(DFN,BGPBDATE)`, and `I9^BGPXD21`
computes `A=$$AGE^AUPNPAT(DFN,BGPBDATE)`. The spec's "ages 2 through 15" is
therefore age 2–15 at period start (`BGPAGEB>1,BGPAGEB<16`).

## 2.2.1 Access to Dental Services

**Denominator (GPRA):** User Population, all ages (`I9^BGPXD21`: `BGPACTUP`
gate). The age-group breakdowns are not encoded.

**Numerator (GPRA):** a documented dental visit during the Report Period
(`DENTSRVD^BGPXD211`), any of, tried in this order:

1. RPMS Dental/ADA code **0000** or **0190** (IHS Dental Tracking codes).
2. A CPT in `[BGP DENTAL VISIT CPT CODES]`: D0110–D0390, D0415–D9952,
   D9970–D9974, D9995, D9996, D9999.
3. Exam code **30**.
4. A POV in `[BGP DENTAL VISIT DXS]`: Z01.20, Z01.21, Z13.84, Z29.3.
5. Any other RPMS Dental/ADA code that `DVADA^BGPXD211` accepts, **on a visit
   that is not a chart review (service category C) or telephone call (T)**.

`DVADA` ranges (M wins over the prose list, which matches it): numeric codes
110–390, 415–471, 601–603, 999–9974, 9995, 9996, 9999; D-codes D0120–D0389,
D0415–D0470, D0701–D0804, D0999–D9974, D9995, D9996, D9999.

## 2.2.2 Dental Sealants

**Denominator (GPRA):** User Population ages 2–15 at period start
(`I10^BGPXD3`: `BGPD7`).

**Numerator (GPRA, `BGPN7`):** an intact sealant, either

- a sealant during the Report Period (`SEAL`/`SEALR^BGPXD3A`): RPMS Dental/ADA
  1351, 1352, 1353, D1351, D1352, D1353, or CPT D1351, D1352, D1353; or
- when there is none, RPMS Dental/ADA **0007** during the three years ending
  at period end (`SEALDEV^BGPXD3A` over `$$FMADD^XLFDT(BGPEDATE,-1096)` to
  `BGPEDATE`: 1,096 days).

M refinement the prose omits: on a visit that carries an RPMS Dental/ADA
sealant code, the CPT sealant codes on the same visit are skipped (`Q:G`).
That only changes the count numerator; for the rate, either code qualifies.

## 2.2.3 Topical Fluoride

**Denominator (GPRA):** User Population ages 1–15 at period start
(`I11^BGPXD3`: `BGPACTUP` gate, `BGPAGEB>0,BGPAGEB<16`).

**Numerator (GPRA, `BGPN3`):** one or more topical fluoride applications during
the Report Period (`TF^BGPXD3A`), any of:

- RPMS Dental/ADA code in `[BGP TOPICAL FLUORIDE ADA CODES]` (spec: 1201, 1203,
  1204, 1205, 1206, 1208, 5986, D1206, D1208, D1354, D5986), or one of the
  values `TF` hard-codes beside the taxonomy: D1201, D1203, D1204, D1205,
  D1206, D1208, **1354**, D5986. The engine accepts the union.
- CPT in `[BGP CPT TOPICAL FLUORIDE]` (V CPT or V TRANSACTION): D1201, D1203,
  D1204, D1205, D1206, D1208, D5986, 99188, 0792T.
- POV in `[BGP TOPICAL FLUORIDE DXS]`: Z29.3.

Refusals are not counted: CRS reads them from the refusal file, which the
engine never treats as evidence of service.

## Divergence flags

- **Count numerators, age-group breakdowns and sub-numerators are not encoded**
  (sealant count with two-per-tooth and one-repair-per-tooth limits by
  operative site, fluoride application count capped at four, the Access
  dental-exam / treatment-completed / pregnancy sub-numerators). GPRA rates
  only.
- The rook-side FHIR shape of V DENTAL and PCC V EXAM is our design
  (`fhir-mapping.md`), not CRS behavior.

## Engine gaps (loud)

- **The chart-review / telephone exclusion needs the visit.** Arm 5 of Access
  counts a dental code only when its `encounter` reference resolves to a visit
  whose service category is known and is not C or T. A dental code with no
  visit link does not count through arm 5 (fail closed); it can still count
  through arms 1–4.
- **Taxonomies are hand-seeded** from the spec text until #83–#85 supply them.

## Open questions (differential probing, #99)

1. `I10^BGPXD3` (Sealants) sets its denominator from age alone and does not
   test `BGPACTUP` itself, while I9 and I11 do. The spec says User Population.
   **INTERIM ENGINE CHOICE (loud):** User Population, per the spec, until the
   oracle shows whether the report driver applies the gate for I10.
2. Whether `LAST EXAM 30` returns refused exams (PCC records refusals
   elsewhere, so the engine counts any exam 30 record).
3. Whether `CPT^BGPXDU` applies a service-category filter to the dental CPT arm.
