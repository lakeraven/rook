# PCC-fact → FHIR mapping (CRS engine input contract)

How the CRS-faithful engine (`Rook::Crs`) sees RPMS/PCC-level facts as FHIR
resources. This is the contract the RPMS platform adapter must emit and the
contract the parity driver seeds — **one mapping, shared by tests and engine**,
so the two cannot drift into separate imaginations.

**DIVERGENCE FLAG — this mapping is OUR design, not CRS behavior.** CRS reads
FileMan files directly; representing those facts in FHIR is rook's adapter
contract. Faithfulness is enforced downstream: the #99 CRS driver seeds real
FileMan records from the same scenario facts, so a mapping that loses
CRS-relevant information shows up as a parity break. Entries marked
*provisional* await the RPMS adapter design and taxonomy extraction (#83–#85).

| PCC fact | FHIR representation |
|---|---|
| Registration: patient | `Patient` — `birthDate`, `gender`; alive = no `deceasedDateTime`/`deceasedBoolean` |
| Beneficiary classification | `Patient.extension` url `https://terminology.lakeraven.com/StructureDefinition/ihs-beneficiary-class`, `valueCode` (e.g. `01` = AI/AN) *(provisional)* |
| GPRA community residency | `Patient.extension` url `https://terminology.lakeraven.com/StructureDefinition/gpra-community`, `valueBoolean` — adapter resolves the community taxonomy; engine trusts the flag *(provisional: becomes a community code + engine-side taxonomy once #83 lands)* |
| Visit (V File encounter) | `Encounter` — `class` from v3-ActCode (`AMB` ambulatory, `SS` day surgery, `OBSENC` observation, `IMP` hospitalization, `VR` telemedicine — kept DISTINCT so day surgery/observation stay recoverable; all five qualify for User Population), `type.coding` system `https://terminology.lakeraven.com/CodeSystem/ihs-clinic-code` (RPMS clinic code), `period.start` |
| POV (V POV) | `Condition` — category `encounter-diagnosis`, ICD-10-CM coding, `encounter` reference, `recordedDate` = visit date |
| Problem List entry | `Condition` — category `problem-list-item`, `clinicalStatus` active/inactive, `recordedDate` = date entered, optional `onsetDateTime`. A DELETED entry is **not exported** (absence = deleted); CRS status rules ("not Deleted" vs "not Inactive or Deleted") are then per-measure `clinicalStatus` checks |
| Lab test (V LAB) | `Observation` — category `laboratory`, LOINC coding, `effectiveDateTime` = visit/specimen date-time, **`issued` = result date-time** (CRS orders by result date-time, falling back to visit date-time — mapped as `issued || effectiveDateTime`), `valueQuantity`. Test without result: no `value[x]`, `dataAbsentReason` `unknown`, no `issued` |
| CPT evidence (V CPT / transactions) | `Procedure` — CPT coding, `performedDateTime` |
| BP (V MEASUREMENT) | `Observation` — vital-signs, LOINC `85354-9` with `8480-6`/`8462-4` components, `effectiveDateTime`, `encounter` reference (class/clinic determine ER exclusion) |
| PHQ-9 / PHQ-T / EPDS (V MEASUREMENT) | `Observation` — survey; LOINC `44261-6` (PHQ-9 total) or system `https://terminology.lakeraven.com/CodeSystem/rpms-measurement-type` code `PHQ9`/`PHQT`/`EPDS` *(provisional)*, `valueQuantity`, `effectiveDateTime` |
| Exam (V EXAM / BH exam 36) | `Observation` — system `https://terminology.lakeraven.com/CodeSystem/bh-exam` code `36`, `valueCodeableConcept` from `…/CodeSystem/bh-exam-result` (`P`/`N`/`R`), `effectiveDateTime` *(provisional)* |
| BHS problem code (e.g. 14.1) | `Observation` — system `https://terminology.lakeraven.com/CodeSystem/bhs-problem-code` code `14.1`, `effectiveDateTime` *(provisional)* |
| Currently-pregnant (Reproductive Factors) | `Observation` — LOINC `82810-3` (pregnancy status), `valueCodeableConcept` SNOMED `77386006` (pregnant), `effectiveDateTime` in period |

Engine-side code sets live in `Rook::Crs::Terminology` with their BGP taxonomy
names cited; they are interim hand-seeded sets until the taxonomy extraction
pipeline (#83–#85) supplies them as ValueSets.
