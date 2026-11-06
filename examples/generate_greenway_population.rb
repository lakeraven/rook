# frozen_string_literal: true

# DEMO / REFERENCE ASSET — NOT the production measure engine.
#
# Deterministic generator for the THIRD synthetic population: a FHIR R4
# Bulk Data export shaped the way an ambulatory Greenway practice emits one.
# Run once to (re)produce the committed NDJSON fixtures:
#
#   lib/rook/demo/fixtures/greenway/primary_fhir/{Patient,Condition,Observation}.ndjson
#   lib/rook/demo/fixtures/greenway/supplemental/{Observation,Coverage}.ndjson
#
# Usage:
#   ruby examples/generate_greenway_population.rb
#
# Same US Core R4 content as the other fixture sets, different PLATFORM
# IDIOMS (simulated; not a capture of any real tenant's export):
#
#   - GUID-shaped resource ids (lowercase, hyphenated)
#   - Patient.identifier carries a practice chart number under a (synthetic)
#     OID system; Hispanic/Latino ethnicity is common (a community health
#     center mix); NO tribal-affiliation extension
#   - Condition codings ICD-10-CM-first with SNOMED second (billing-heritage
#     ambulatory EHR), category encounter-diagnosis, no recordedDate
#   - Observation effectiveDateTime carries a local UTC offset (-06:00)
#     instead of Z
#   - a pediatric patient under 12, so the depression-screening age floor
#     actually excludes someone
#
# The population contains NO real PHI and no real facility/partner names:
# family names are tree-genus placeholders, demographics are synthetic,
# identifiers use the 2.999 example-OID arc. "Greenway" names only the EHR
# platform flavor being simulated; no vendor API is involved.
#
# Counts are hand-authored so the measures compute known, testable rates
# (see test/demo/greenway_population_test.rb), deliberately DIFFERENT from
# the RPMS and Epic populations:
#
#   Diabetes: HbA1c Poor Control (>9%)  -> denom 12, numerator 5, rate ~0.417
#   Controlling High Blood Pressure     -> denom 10, numerator 7, rate 0.70
#   Depression Screening (age 12+)      -> denom 23, numerator 15, rate ~0.652

require "json"
require "date"

PERIOD_END = Date.new(2025, 12, 31)

DM_ICD10 = { system: "http://hl7.org/fhir/sid/icd-10-cm", code: "E11.9",
            display: "Type 2 diabetes mellitus without complications" }.freeze
DM_SNOMED = { system: "http://snomed.info/sct", code: "44054006",
             display: "Type 2 diabetes mellitus" }.freeze
HTN_ICD10 = { system: "http://hl7.org/fhir/sid/icd-10-cm", code: "I10",
             display: "Essential (primary) hypertension" }.freeze
HTN_SNOMED = { system: "http://snomed.info/sct", code: "38341003",
              display: "Hypertensive disorder" }.freeze

HBA1C_LOINC = { system: "http://loinc.org", code: "4548-4",
               display: "Hemoglobin A1c/Hemoglobin.total in Blood" }.freeze
BP_LOINC = { system: "http://loinc.org", code: "85354-9",
            display: "Blood pressure panel with all children optional" }.freeze
SYS_LOINC = { system: "http://loinc.org", code: "8480-6", display: "Systolic blood pressure" }.freeze
DIA_LOINC = { system: "http://loinc.org", code: "8462-4", display: "Diastolic blood pressure" }.freeze
PHQ9_LOINC = { system: "http://loinc.org", code: "44261-6",
              display: "Patient Health Questionnaire 9 item (PHQ-9) total score" }.freeze

# Synthetic chart-number system: 2.999 is the reserved example-OID arc —
# deliberately NOT a real Greenway practice OID.
CHART_SYSTEM = "urn:oid:2.999.4733.1"

LAST_UPDATED = "2026-01-20T13:00:00Z"

# Local-offset habit: clinical timestamps carry the practice's UTC offset.
TZ = "-06:00"

# Placeholder family names (tree genera) — obviously synthetic, no ethnic
# connotation, no real-person or partner names. Distinct from the NATO-phonetic
# (RPMS) and constellation (Epic) sets.
FAMILY = %w[
  Acacia Alder Aspen Birch Cedar Cypress Elm Fir Hawthorn Hazel Hemlock Holly
  Juniper Larch Linden Magnolia Maple Oak Olive Pine Rowan Spruce Sumac Willow
].freeze

# GUID-shaped id, deterministic per (kind, seq). The leading block spells
# "5d" + kind so every id is visibly synthetic.
KIND_HEX = { "Pt" => "a1", "Cond" => "c0", "ObsA1c" => "a1c0", "ObsBp" => "b0",
            "ObsPhq" => "d9" }.freeze

def greenway_id(kind, seq)
  format("5d%06d-%s-4000-8000-%012d", seq, KIND_HEX.fetch(kind).ljust(4, "0"), seq)
end

def birthdate_for_age(age)
  Date.new(PERIOD_END.year - age, 7, 1).to_s
end

OMB_RACE = {
  "2106-3" => "White",
  "2054-5" => "Black or African American",
  "1002-5" => "American Indian or Alaska Native",
  "2028-9" => "Asian"
}.freeze

OMB_ETHNICITY = {
  "2135-2" => "Hispanic or Latino",
  "2186-5" => "Not Hispanic or Latino"
}.freeze

def patient_resource(seq:, gender:, age:, race:, ethnicity:)
  {
    resourceType: "Patient",
    id: greenway_id("Pt", seq),
    meta: { profile: [ "http://hl7.org/fhir/us/core/StructureDefinition/us-core-patient" ],
           lastUpdated: LAST_UPDATED },
    identifier: [ {
      use: "usual",
      type: { coding: [ { system: "http://terminology.hl7.org/CodeSystem/v2-0203", code: "MR" } ],
             text: "Chart Number" },
      system: CHART_SYSTEM,
      value: format("%07d", 4_100_000 + seq)
    } ],
    extension: [
      { url: "http://hl7.org/fhir/us/core/StructureDefinition/us-core-race",
       extension: [
         { url: "ombCategory",
          valueCoding: { system: "urn:oid:2.16.840.1.113883.6.238",
                        code: race, display: OMB_RACE.fetch(race) } },
         { url: "text", valueString: OMB_RACE.fetch(race) }
       ] },
      { url: "http://hl7.org/fhir/us/core/StructureDefinition/us-core-ethnicity",
       extension: [
         { url: "ombCategory",
          valueCoding: { system: "urn:oid:2.16.840.1.113883.6.238",
                        code: ethnicity, display: OMB_ETHNICITY.fetch(ethnicity) } },
         { url: "text", valueString: OMB_ETHNICITY.fetch(ethnicity) }
       ] },
      { url: "http://hl7.org/fhir/us/core/StructureDefinition/us-core-birthsex",
       valueCode: gender == "female" ? "F" : "M" }
    ],
    name: [ { use: "official", family: FAMILY[seq - 1], given: [ "Jordan" ] } ],
    gender: gender,
    birthDate: birthdate_for_age(age)
  }
end

def condition_resource(patient_id:, seq:, icd:, snomed:, onset:)
  {
    resourceType: "Condition",
    id: greenway_id("Cond", seq),
    meta: { profile: [ "http://hl7.org/fhir/us/core/StructureDefinition/us-core-condition-encounter-diagnosis" ],
           lastUpdated: LAST_UPDATED },
    clinicalStatus: { coding: [ { system: "http://terminology.hl7.org/CodeSystem/condition-clinical",
                               code: "active" } ] },
    verificationStatus: { coding: [ { system: "http://terminology.hl7.org/CodeSystem/condition-ver-status",
                                   code: "confirmed" } ] },
    # Billing-heritage export: encounter-diagnosis, ICD-10-CM first, SNOMED
    # second, onset only (no recordedDate).
    category: [ { coding: [ { system: "http://terminology.hl7.org/CodeSystem/condition-category",
                          code: "encounter-diagnosis", display: "Encounter Diagnosis" } ] } ],
    code: { coding: [ icd, snomed ], text: icd[:display] },
    subject: { reference: "Patient/#{patient_id}" },
    onsetDateTime: onset
  }
end

def hba1c_resource(patient_id:, seq:, value:, effective:)
  {
    resourceType: "Observation",
    id: greenway_id("ObsA1c", seq),
    meta: { profile: [ "http://hl7.org/fhir/us/core/StructureDefinition/us-core-observation-lab" ],
           lastUpdated: LAST_UPDATED },
    status: "final",
    category: [ { coding: [ { system: "http://terminology.hl7.org/CodeSystem/observation-category",
                          code: "laboratory" } ] } ],
    code: { coding: [ HBA1C_LOINC ], text: "Hemoglobin A1c" },
    subject: { reference: "Patient/#{patient_id}" },
    effectiveDateTime: "#{effective}T08:45:00#{TZ}",
    valueQuantity: { value: value, unit: "%", system: "http://unitsofmeasure.org", code: "%" }
  }
end

def bp_resource(patient_id:, seq:, systolic:, diastolic:, effective:)
  {
    resourceType: "Observation",
    id: greenway_id("ObsBp", seq),
    meta: { profile: [ "http://hl7.org/fhir/us/core/StructureDefinition/us-core-blood-pressure" ],
           lastUpdated: LAST_UPDATED },
    status: "final",
    category: [ { coding: [ { system: "http://terminology.hl7.org/CodeSystem/observation-category",
                          code: "vital-signs" } ] } ],
    code: { coding: [ BP_LOINC ], text: "BP" },
    subject: { reference: "Patient/#{patient_id}" },
    effectiveDateTime: "#{effective}T15:20:00#{TZ}",
    component: [
      { code: { coding: [ SYS_LOINC ] },
       valueQuantity: { value: systolic, unit: "mm[Hg]", system: "http://unitsofmeasure.org", code: "mm[Hg]" } },
      { code: { coding: [ DIA_LOINC ] },
       valueQuantity: { value: diastolic, unit: "mm[Hg]", system: "http://unitsofmeasure.org", code: "mm[Hg]" } }
    ]
  }
end

def phq9_resource(patient_id:, seq:, score:, effective:)
  {
    resourceType: "Observation",
    id: greenway_id("ObsPhq", seq),
    meta: { profile: [ "http://hl7.org/fhir/us/core/StructureDefinition/us-core-observation-survey" ],
           lastUpdated: LAST_UPDATED },
    status: "final",
    category: [ { coding: [ { system: "http://terminology.hl7.org/CodeSystem/observation-category",
                          code: "survey" } ] } ],
    code: { coding: [ PHQ9_LOINC ], text: "PHQ-9" },
    subject: { reference: "Patient/#{patient_id}" },
    effectiveDateTime: "#{effective}T11:00:00#{TZ}",
    valueQuantity: { value: score, unit: "{score}", system: "http://unitsofmeasure.org", code: "{score}" }
  }
end

# ---------------------------------------------------------------------------
# Population definition (hand-authored so measure counts are known/testable).
#
# 24 patients, G01..G24. G24 is age 9, so the depression-screening
# denominator is 23.
# ---------------------------------------------------------------------------
def population_spec
  h = "2135-2" # Hispanic or Latino
  n = "2186-5" # Not Hispanic or Latino
  spec = []

  # --- Diabetes denominator (age 18-75): 12 patients (G01..G12) -------------
  # 5 in numerator (poor control >9% OR no HbA1c in period).
  spec << { age: 58, gender: "female", eth: h, diabetes: true, hypertension: true,
            hba1c: [ [ 9.8, "2025-04-22" ] ], bp: [ [ 136, 86, "2025-04-22" ] ] }        # G01 poor; BP controlled
  spec << { age: 45, gender: "male", eth: h, diabetes: true,
            hba1c: [ [ 7.1, "2025-06-03" ] ] }                                         # G02 controlled
  spec << { age: 62, gender: "female", eth: n, race: "2054-5", diabetes: true,
            hba1c: [] }                                                                # G03 no HbA1c -> poor
  spec << { age: 50, gender: "male", eth: h, diabetes: true,
            hba1c: [ [ 10.4, "2025-02-11" ], [ 9.2, "2025-10-14" ] ] }                   # G04 still poor
  spec << { age: 67, gender: "female", eth: n, diabetes: true, hypertension: true,
            hba1c: [ [ 7.9, "2025-08-19" ] ], bp: [ [ 144, 88, "2025-08-19" ] ] }        # G05 ctrl; BP not (systolic)
  spec << { age: 38, gender: "male", eth: h, diabetes: true,
            hba1c: [ [ 9.0, "2025-05-07" ] ] }                                         # G06 exactly 9.0 -> not >9
  spec << { age: 71, gender: "female", eth: n, diabetes: true,
            hba1c: [ [ 6.8, "2025-09-30" ] ] }                                         # G07 controlled
  spec << { age: 43, gender: "male", eth: h, diabetes: true,
            hba1c: [ [ 12.1, "2025-03-18" ] ] }                                        # G08 poor
  spec << { age: 55, gender: "female", eth: h, diabetes: true,
            hba1c: [ [ 8.4, "2025-07-09" ] ] }                                         # G09 controlled
  spec << { age: 33, gender: "male", eth: n, race: "1002-5", diabetes: true,
            hba1c: [ [ 7.5, "2024-12-20" ] ] }                                         # G10 pre-period only -> poor
  spec << { age: 75, gender: "female", eth: n, diabetes: true,
            hba1c: [ [ 8.0, "2025-11-04" ] ] }                                         # G11 upper age edge; ctrl
  spec << { age: 18, gender: "male", eth: h, diabetes: true,
            hba1c: [ [ 6.2, "2025-01-27" ] ] }                                         # G12 lower age edge; ctrl

  # --- Diabetic BELOW the 18-75 band (still 12+, so in depression denom) ----
  spec << { age: 17, gender: "female", eth: h, diabetes: true,
            hba1c: [ [ 9.5, "2025-06-16" ] ] }                                         # G13

  # --- Hypertension-only patients (denominator age 18-85) -------------------
  # With dual-diagnosis G01 + G05 above, the CBP denominator is 10; 7 control.
  spec << { age: 60, gender: "male", eth: n, race: "2054-5", hypertension: true,
            bp: [ [ 138, 88, "2025-03-25" ] ] }                                        # G14 controlled
  spec << { age: 52, gender: "female", eth: h, hypertension: true,
            bp: [ [ 142, 86, "2025-02-14" ], [ 126, 82, "2025-10-02" ] ] }               # G15 most-recent controls
  spec << { age: 70, gender: "male", eth: n, hypertension: true,
            bp: [ [ 130, 92, "2025-07-28" ] ] }                                        # G16 not (diastolic)
  spec << { age: 46, gender: "female", eth: h, hypertension: true,
            bp: [ [ 122, 76, "2025-05-12" ] ] }                                        # G17 controlled
  spec << { age: 85, gender: "male", eth: n, hypertension: true,
            bp: [ [ 134, 80, "2025-09-09" ] ] }                                        # G18 upper age edge; ctrl
  spec << { age: 40, gender: "female", eth: h, hypertension: true,
            bp: [] }                                                                   # G19 no BP -> not
  spec << { age: 64, gender: "male", eth: n, race: "2028-9", hypertension: true,
            bp: [ [ 128, 84, "2025-12-01" ] ] }                                        # G20 controlled
  spec << { age: 57, gender: "female", eth: h, hypertension: true,
            bp: [ [ 118, 72, "2025-04-30" ] ] }                                        # G21 controlled

  # --- Hypertensive ABOVE the 18-85 band ------------------------------------
  spec << { age: 86, gender: "female", eth: n, hypertension: true,
            bp: [ [ 120, 70, "2025-06-24" ] ] }                                        # G22

  # --- Healthy adult and a pediatric patient --------------------------------
  spec << { age: 29, gender: "female", eth: h, bp: [ [ 110, 68, "2025-08-05" ] ] }       # G23
  spec << { age: 9, gender: "male", eth: h }                                           # G24 under 12

  spec
end

def build_primary
  resources = []
  cond_seq = 0
  a1c_seq = 0
  bp_seq = 0
  phq9_seq = 0

  # Depression screening (PHQ-9): G01..G15 screened in-period; G16..G23 not;
  # G24 is under 12 (outside the denominator). Deterministic 15/23.
  screened_count = 15

  population_spec.each_with_index do |p, idx|
    seq = idx + 1
    pid = greenway_id("Pt", seq)
    resources << patient_resource(seq: seq, gender: p[:gender], age: p[:age],
      race: p[:race] || "2106-3", ethnicity: p[:eth])

    if p[:diabetes]
      cond_seq += 1
      resources << condition_resource(patient_id: pid, seq: cond_seq,
        icd: DM_ICD10, snomed: DM_SNOMED, onset: "2019-03-04")
    end
    if p[:hypertension]
      cond_seq += 1
      resources << condition_resource(patient_id: pid, seq: cond_seq,
        icd: HTN_ICD10, snomed: HTN_SNOMED, onset: "2020-09-21")
    end
    (p[:hba1c] || []).each do |value, effective|
      a1c_seq += 1
      resources << hba1c_resource(patient_id: pid, seq: a1c_seq, value: value, effective: effective)
    end
    (p[:bp] || []).each do |systolic, diastolic, effective|
      bp_seq += 1
      resources << bp_resource(patient_id: pid, seq: bp_seq,
        systolic: systolic, diastolic: diastolic, effective: effective)
    end
    if idx < screened_count
      phq9_seq += 1
      resources << phq9_resource(patient_id: pid, seq: phq9_seq,
        score: (idx * 3) % 11, effective: "2025-08-12")
    end
  end

  resources
end

# Supplemental channel: identical NORMALIZED shape to the other populations'
# supplemental feeds — only the source descriptor differs (:greenway). The
# community-health-center mix leans on the UDS-only attributes (sliding fee,
# agricultural worker, housing).
ATTRIBUTE_CS = "https://terminology.lakeraven.com/CodeSystem/uds-supplemental-attribute"
VALUE_CS = "https://terminology.lakeraven.com/CodeSystem/uds-supplemental-value"
PAYER_CS = "https://terminology.lakeraven.com/CodeSystem/uds-payer-category"

SUPPLEMENTAL_PROFILES = [
  # [patient_seq, sliding-fee class, housing status, agricultural worker, veteran, payer categories]
  [ 1, "class-a", "housed", "seasonal", "non-veteran", %w[medicaid] ],
  [ 2, "class-b", "housed", "migratory", "non-veteran", %w[uninsured] ],
  [ 4, "class-a", "doubling-up", "seasonal", "non-veteran", %w[uninsured] ],
  # G07 is dual-eligible: Medicare AND Medicaid coverages simultaneously.
  [ 7, "class-c", "housed", "none", "non-veteran", %w[medicare medicaid] ],
  [ 14, "class-d", "housed", "none", "veteran", %w[private] ],
  [ 19, "class-e", "unsheltered", "none", "non-veteran", %w[uninsured] ]
].freeze

def supplemental_observation(patient_seq:, seq:, attribute:, value:)
  {
    resourceType: "Observation",
    id: format("demo-greenway-suppl-obs-%03d", seq),
    status: "final",
    category: [ { coding: [ { system: "http://terminology.hl7.org/CodeSystem/observation-category",
                          code: "social-history" } ] } ],
    code: { coding: [ { system: ATTRIBUTE_CS, code: attribute } ], text: attribute },
    subject: { reference: "Patient/#{greenway_id('Pt', patient_seq)}" },
    effectiveDateTime: "2025-12-31",
    valueCodeableConcept: { coding: [ { system: VALUE_CS, code: value } ], text: value }
  }
end

def build_supplemental
  obs_seq = 0
  cov_seq = 0
  SUPPLEMENTAL_PROFILES.flat_map do |patient_seq, fee_class, housing, ag_worker, veteran, payers|
    attributes = { "sliding-fee-class" => fee_class, "housing-status" => housing,
                  "agricultural-worker-status" => ag_worker, "veteran-status" => veteran }
    resources = attributes.map do |attribute, value|
      obs_seq += 1
      supplemental_observation(patient_seq: patient_seq, seq: obs_seq, attribute: attribute, value: value)
    end
    payers.each do |payer|
      cov_seq += 1
      resources << {
        resourceType: "Coverage",
        id: format("demo-greenway-suppl-cov-%03d", cov_seq),
        status: "active",
        type: { coding: [ { system: PAYER_CS, code: payer } ], text: payer },
        beneficiary: { reference: "Patient/#{greenway_id('Pt', patient_seq)}" },
        payor: [ { display: "Synthetic Payer Organization (demo)" } ],
        period: { start: "2025-01-01", end: "2025-12-31" }
      }
    end
    resources
  end
end

def write_ndjson_feed(dir, resources)
  require "fileutils"
  FileUtils.mkdir_p(dir)
  FileUtils.rm_f(Dir[File.join(dir, "*.ndjson")])
  resources.group_by { |r| r[:resourceType] }.each do |type, of_type|
    path = File.join(dir, "#{type}.ndjson")
    File.write(path, of_type.map { |r| JSON.generate(r) }.join("\n") + "\n")
    puts "Wrote #{path} (#{of_type.size} resources)"
  end
end

if __FILE__ == $PROGRAM_NAME
  fixtures = File.expand_path("../lib/rook/demo/fixtures/greenway", __dir__)
  write_ndjson_feed(File.join(fixtures, "primary_fhir"), build_primary)
  write_ndjson_feed(File.join(fixtures, "supplemental"), build_supplemental)
end
