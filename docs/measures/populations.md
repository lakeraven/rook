# Denominator populations (CRS v25)

Spec: `evidence/crs-v25/spec/populations.txt` (§1.2.2–1.2.3). These definitions are
shared by every measure dossier — reverse-engineered once, referenced everywhere.

## Active Clinical Population (National GPRA/GPRAMA)

- **Two face-to-face visits to medical clinics** in the three years prior to the end
  of the Report Period — chart reviews and telephone calls do not count; at least
  one visit must be to a **core medical clinic** (clinic list: CRS FY2025 Clinical
  Measures User Manual).
- Alive on the last day of the Report Period.
- AI/AN — Beneficiary 01.
- Resides in a community in the site's **GPRA community taxonomy** (PRC catchment).

Local (non-national) reports relax the AI/AN and community rules to user choices.

## User Population (National GPRA/GPRAMA)

- Seen **at least once** in the three years prior to period end, any clinic type;
  visit must be ambulatory (incl. day surgery/observation), hospitalization, or
  telemedicine — other service categories excluded.
- Alive on the last day of the Report Period; AI/AN (Beneficiary 01); GPRA
  community taxonomy residency.

## Active Diabetic (key denominator for diabetes-related topics)

Defined in the diabetes dossier: population base + diabetes diagnosed **prior to**
the Report Period + **≥2 visits during** the Report Period + (2 DM-related visits
ever OR DM Problem List entry). See `diabetes-glycemic-control.md`.

## Divergence flags

- **None of these exist in the demo measures** (`Rook::Demo`), which use "has
  condition code" over the whole population with eCQM-style age bands. The demo trio
  is UDS/eCQM-shaped, not CRS-shaped — do not treat it as a CRS reference.
- Rook's production denominators must model: qualifying-visit selection (service
  category, clinic codes, face-to-face), Beneficiary 01, community taxonomy
  residency, and alive-at-period-end. These come from PCC visit/registration data —
  ingest (#96) and the warehouse (#59/#64) must carry them.
