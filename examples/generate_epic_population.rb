# frozen_string_literal: true

# DEMO / REFERENCE ASSET — NOT the production measure engine.
#
# Deterministic generator for the SECOND synthetic population: a FHIR R4
# Bulk Data export shaped the way an Epic tenant emits one (rook#101). Run
# once to (re)produce the committed NDJSON fixtures:
#
#   lib/rook/demo/fixtures/epic/primary_fhir/{Patient,Condition,Observation}.ndjson
#   lib/rook/demo/fixtures/epic/supplemental/{Observation,Coverage}.ndjson
#
# Usage:
#   ruby examples/generate_epic_population.rb
#
# Same US Core R4 content as the first fixture set, different PLATFORM
# IDIOMS — the point of the fixture is that the ingest seam and the measures
# don't care which EHR exported the data:
#
#   - Epic-style opaque resource ids ("e...=" tokens, dot-suffixed)
#   - Patient.identifier carries an MRN under a (synthetic) OID system
#   - race/ethnicity/birthsex US Core extensions; NO tribal-affiliation
#     extension (a stock Epic tenant doesn't populate it)
#   - Condition codings SNOMED-first with ICD-10-CM second, category
#     problem-list-item, recordedDate present
#   - Observation effectiveDateTime as full instants, meta.profile stamped
#     per US Core profile, meta.lastUpdated present (bulk-export habit)
#
# The population contains NO real PHI and no real facility/partner names:
# family names are constellation placeholders, demographics are synthetic,
# identifiers use the 2.999 example-OID arc. "Epic" names only the EHR
# platform flavor being simulated; no vendor API is involved.
#
# Counts are hand-authored so the measures compute known, testable rates
# (see test/demo/epic_population_ingest_test.rb), deliberately DIFFERENT
# from the first population so the two-platform demo shows two clinics,
# not one dataset twice:
#
#   Diabetes: HbA1c Poor Control (>9%)  -> denom 10, numerator 3, rate 0.30
#   Controlling High Blood Pressure     -> denom  8, numerator 5, rate 0.625
#   Depression Screening (age 12+)      -> denom 18, numerator 12, rate ~0.667

require "json"
require "date"

PERIOD_END = Date.new(2025, 12, 31)

DM_SNOMED = { system: "http://snomed.info/sct", code: "44054006",
             display: "Type 2 diabetes mellitus" }.freeze
DM_ICD10 = { system: "http://hl7.org/fhir/sid/icd-10-cm", code: "E11.9",
            display: "Type 2 diabetes mellitus without complications" }.freeze
HTN_SNOMED = { system: "http://snomed.info/sct", code: "38341003",
              display: "Hypertensive disorder" }.freeze
HTN_ICD10 = { system: "http://hl7.org/fhir/sid/icd-10-cm", code: "I10",
             display: "Essential (primary) hypertension" }.freeze

HBA1C_LOINC = { system: "http://loinc.org", code: "4548-4",
               display: "Hemoglobin A1c/Hemoglobin.total in Blood" }.freeze
BP_LOINC = { system: "http://loinc.org", code: "85354-9",
            display: "Blood pressure panel with all children optional" }.freeze
SYS_LOINC = { system: "http://loinc.org", code: "8480-6", display: "Systolic blood pressure" }.freeze
DIA_LOINC = { system: "http://loinc.org", code: "8462-4", display: "Diastolic blood pressure" }.freeze
PHQ9_LOINC = { system: "http://loinc.org", code: "44261-6",
              display: "Patient Health Questionnaire 9 item (PHQ-9) total score" }.freeze

# Synthetic MRN system: 2.999 is the reserved example-OID arc — deliberately
# NOT a real Epic tenant OID.
MRN_SYSTEM = "urn:oid:2.999.737384.0"

# Bulk-export habit: resources carry meta.lastUpdated. One fixed instant —
# the fixture is deterministic.
LAST_UPDATED = "2026-01-15T08:00:00Z"

# Placeholder family names (constellations) — obviously synthetic, no ethnic
# connotation, no real-person or partner names. Distinct from the first
# population's NATO-phonetic set so cross-population resources are never
# confused in a demo.
FAMILY = %w[
  Andromeda Auriga Carina Cassiopeia Cepheus Cygnus Draco Gemini Hydra
  Lyra Orion Pegasus Perseus Phoenix Pyxis Scutum Taurus Vela
].freeze

# Epic-style opaque resource id: "e" + mixed-case token ending in a dotted
# suffix. Deterministic per (kind, seq); clearly synthetic.
def epic_id(kind, seq)
  format("eSynDemo%s%03dxKq7Vb.Zz%03d", kind, seq, seq)
end

def birthdate_for_age(age)
  Date.new(PERIOD_END.year - age, 7, 1).to_s
end

# OMB race categories: majority AI/AN (it's a tribal-serving clinic on Epic),
# a couple of other categories so the flavor isn't a single-value column.
OMB_RACE = {
  "1002-5" => "American Indian or Alaska Native",
  "2106-3" => "White",
  "2028-9" => "Asian"
}.freeze

def patient_resource(seq:, gender:, age:, race: "1002-5")
  {
    resourceType: "Patient",
    id: epic_id("Pt", seq),
    meta: { profile: [ "http://hl7.org/fhir/us/core/StructureDefinition/us-core-patient" ],
           lastUpdated: LAST_UPDATED },
    identifier: [ {
      use: "usual",
      type: { coding: [ { system: "http://terminology.hl7.org/CodeSystem/v2-0203", code: "MR" } ],
             text: "MRN" },
      system: MRN_SYSTEM,
      value: format("E%06d", seq)
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
                        code: "2186-5", display: "Not Hispanic or Latino" } },
         { url: "text", valueString: "Not Hispanic or Latino" }
       ] },
      { url: "http://hl7.org/fhir/us/core/StructureDefinition/us-core-birthsex",
       valueCode: gender == "female" ? "F" : "M" }
      # NOTE: no us-core-tribal-affiliation extension — stock Epic tenants
      # don't populate it; the demo shows the reports degrade gracefully.
    ],
    name: [ { use: "official", family: FAMILY[seq - 1], given: [ "Riley", "Q" ] } ],
    gender: gender,
    birthDate: birthdate_for_age(age)
  }
end

def condition_resource(patient_id:, seq:, snomed:, icd:, onset:)
  {
    resourceType: "Condition",
    id: epic_id("Cond", seq),
    meta: { profile: [ "http://hl7.org/fhir/us/core/StructureDefinition/us-core-condition" ],
           lastUpdated: LAST_UPDATED },
    clinicalStatus: { coding: [ { system: "http://terminology.hl7.org/CodeSystem/condition-clinical",
                               code: "active", display: "Active" } ] },
    verificationStatus: { coding: [ { system: "http://terminology.hl7.org/CodeSystem/condition-ver-status",
                                   code: "confirmed", display: "Confirmed" } ] },
    # Epic problem-list export: category problem-list-item, SNOMED coding
    # first with ICD-10-CM second, recordedDate alongside onset.
    category: [ { coding: [ { system: "http://terminology.hl7.org/CodeSystem/condition-category",
                          code: "problem-list-item", display: "Problem List Item" } ] } ],
    code: { coding: [ snomed, icd ], text: snomed[:display] },
    subject: { reference: "Patient/#{patient_id}" },
    onsetDateTime: onset,
    recordedDate: onset
  }
end

def hba1c_resource(patient_id:, seq:, value:, effective:)
  {
    resourceType: "Observation",
    id: epic_id("ObsA1c", seq),
    meta: { profile: [ "http://hl7.org/fhir/us/core/StructureDefinition/us-core-observation-lab" ],
           lastUpdated: LAST_UPDATED },
    status: "final",
    category: [ { coding: [ { system: "http://terminology.hl7.org/CodeSystem/observation-category",
                          code: "laboratory", display: "Laboratory" } ] } ],
    code: { coding: [ HBA1C_LOINC ], text: "HbA1c" },
    subject: { reference: "Patient/#{patient_id}" },
    effectiveDateTime: "#{effective}T09:30:00Z",
    issued: "#{effective}T11:02:00Z",
    valueQuantity: { value: value, unit: "%", system: "http://unitsofmeasure.org", code: "%" }
  }
end

def bp_resource(patient_id:, seq:, systolic:, diastolic:, effective:)
  {
    resourceType: "Observation",
    id: epic_id("ObsBp", seq),
    meta: { profile: [ "http://hl7.org/fhir/StructureDefinition/bp",
                     "http://hl7.org/fhir/us/core/StructureDefinition/us-core-blood-pressure" ],
           lastUpdated: LAST_UPDATED },
    status: "final",
    category: [ { coding: [ { system: "http://terminology.hl7.org/CodeSystem/observation-category",
                          code: "vital-signs", display: "Vital Signs" } ] } ],
    code: { coding: [ BP_LOINC ], text: "Blood pressure" },
    subject: { reference: "Patient/#{patient_id}" },
    effectiveDateTime: "#{effective}T14:05:00Z",
    component: [
      { code: { coding: [ SYS_LOINC ], text: SYS_LOINC[:display] },
       valueQuantity: { value: systolic, unit: "mmHg", system: "http://unitsofmeasure.org", code: "mm[Hg]" } },
      { code: { coding: [ DIA_LOINC ], text: DIA_LOINC[:display] },
       valueQuantity: { value: diastolic, unit: "mmHg", system: "http://unitsofmeasure.org", code: "mm[Hg]" } }
    ]
  }
end

def phq9_resource(patient_id:, seq:, score:, effective:)
  {
    resourceType: "Observation",
    id: epic_id("ObsPhq", seq),
    meta: { profile: [ "http://hl7.org/fhir/us/core/StructureDefinition/us-core-observation-survey" ],
           lastUpdated: LAST_UPDATED },
    status: "final",
    category: [ { coding: [ { system: "http://terminology.hl7.org/CodeSystem/observation-category",
                          code: "survey", display: "Survey" } ] } ],
    code: { coding: [ PHQ9_LOINC ], text: "PHQ-9 total score" },
    subject: { reference: "Patient/#{patient_id}" },
    effectiveDateTime: "#{effective}T10:15:00Z",
    valueQuantity: { value: score, unit: "{score}", system: "http://unitsofmeasure.org", code: "{score}" }
  }
end

# ---------------------------------------------------------------------------
# Population definition (hand-authored so measure counts are known/testable).
#
# 18 patients, E01..E18 — every patient is age >= 12, so the depression-
# screening denominator is all 18.
# ---------------------------------------------------------------------------
def population_spec
  spec = []

  # --- Diabetes denominator (age 18-75): 10 patients (E01..E10) -------------
  # 3 in numerator (poor control >9% OR no HbA1c in period).
  spec << { age: 58, gender: "female", diabetes: true, hypertension: true,
            hba1c: [ [ 10.8, "2025-05-14" ] ], bp: [ [ 132, 84, "2025-05-14" ] ] }        # E01 poor; BP controlled
  spec << { age: 47, gender: "male", diabetes: true,
            hba1c: [ [ 8.2, "2024-11-20" ] ], bp: [] }                                # E02 pre-period only -> poor
  spec << { age: 63, gender: "female", diabetes: true, race: "2106-3",
            hba1c: [ [ 9.4, "2025-09-03" ] ], bp: [] }                                # E03 poor (9.4 > 9)
  spec << { age: 51, gender: "male", diabetes: true,
            hba1c: [ [ 6.9, "2025-04-18" ] ], bp: [] }                                # E04 controlled
  spec << { age: 66, gender: "female", diabetes: true, hypertension: true,
            hba1c: [ [ 7.4, "2025-07-22" ] ], bp: [ [ 128, 78, "2025-07-22" ] ] }         # E05 controlled; BP controlled
  spec << { age: 39, gender: "male", diabetes: true,
            hba1c: [ [ 9.0, "2025-03-09" ] ], bp: [] }                                # E06 exactly 9.0 -> not >9
  spec << { age: 72, gender: "female", diabetes: true,
            hba1c: [ [ 8.6, "2025-10-30" ] ], bp: [] }                                # E07 controlled
  spec << { age: 44, gender: "male", diabetes: true,
            hba1c: [ [ 11.2, "2025-01-12" ], [ 7.8, "2025-12-05" ] ], bp: [] }            # E08 most-recent controls
  spec << { age: 57, gender: "female", diabetes: true,
            hba1c: [ [ 6.4, "2025-08-15" ] ], bp: [] }                                # E09 controlled
  spec << { age: 29, gender: "male", diabetes: true, race: "2028-9",
            hba1c: [ [ 8.9, "2025-06-27" ] ], bp: [] }                                # E10 controlled

  # --- Diabetic OUTSIDE the 18-75 band (excluded from that denominator) -----
  spec << { age: 79, gender: "female", diabetes: true,
            hba1c: [ [ 10.1, "2025-04-02" ] ], bp: [] }                               # E11

  # --- Hypertension-only patients (denominator age 18-85) -------------------
  # With dual-diagnosis E01 + E05 above, the CBP denominator is 8; 5 control.
  spec << { age: 62, gender: "male", hypertension: true,
            hba1c: [], bp: [ [ 150, 96, "2025-02-08" ] ] }                            # E12 uncontrolled
  spec << { age: 54, gender: "female", hypertension: true,
            hba1c: [], bp: [ [ 148, 94, "2025-03-11" ], [ 124, 80, "2025-11-19" ] ] }     # E13 most-recent controls
  spec << { age: 71, gender: "male", hypertension: true,
            hba1c: [], bp: [ [ 139, 89, "2025-08-26" ] ] }                            # E14 controlled (just under)
  spec << { age: 48, gender: "female", hypertension: true,
            hba1c: [], bp: [ [ 140, 90, "2025-06-14" ] ] }                            # E15 exactly 140/90 -> not
  spec << { age: 83, gender: "male", hypertension: true,
            hba1c: [], bp: [ [ 152, 98, "2024-10-05" ] ] }                            # E16 pre-period only -> not
  spec << { age: 36, gender: "female", hypertension: true,
            hba1c: [], bp: [ [ 118, 74, "2025-09-05" ] ] }                            # E17 controlled

  # --- Healthy control ------------------------------------------------------
  spec << { age: 25, gender: "male", hba1c: [], bp: [ [ 112, 70, "2025-05-20" ] ] }     # E18

  spec
end

def build_primary
  resources = []
  cond_seq = 0
  a1c_seq = 0
  bp_seq = 0
  phq9_seq = 0

  # Depression screening (PHQ-9): E01..E12 screened in-period, E13..E18 not.
  # Deterministic 12/18 (66.7%) screening rate.
  screened_count = 12

  population_spec.each_with_index do |p, idx|
    seq = idx + 1
    pid = epic_id("Pt", seq)
    resources << patient_resource(seq: seq, gender: p[:gender], age: p[:age],
      race: p[:race] || "1002-5")

    if p[:diabetes]
      cond_seq += 1
      resources << condition_resource(patient_id: pid, seq: cond_seq,
        snomed: DM_SNOMED, icd: DM_ICD10, onset: "2018-06-15")
    end
    if p[:hypertension]
      cond_seq += 1
      resources << condition_resource(patient_id: pid, seq: cond_seq,
        snomed: HTN_SNOMED, icd: HTN_ICD10, onset: "2021-01-20")
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
        score: idx % 5, effective: "2025-07-10")
    end
  end

  resources
end

# Supplemental channel: identical NORMALIZED shape to the first population's
# supplemental feed — that invariance across platforms is the whole point of
# the supplemental contract. Only the source descriptor differs (:epic).
# Kept tiny; its job is exercising the two-channel seam, not driving a measure.
ATTRIBUTE_CS = "https://terminology.lakeraven.com/CodeSystem/uds-supplemental-attribute"
VALUE_CS = "https://terminology.lakeraven.com/CodeSystem/uds-supplemental-value"
PAYER_CS = "https://terminology.lakeraven.com/CodeSystem/uds-payer-category"

SUPPLEMENTAL_PROFILES = [
  # [patient_seq, sliding-fee class, housing status, agricultural worker, veteran, payer categories]
  [ 1, "class-b", "housed", "none", "non-veteran", %w[medicaid] ],
  [ 2, "class-e", "homeless-shelter", "none", "non-veteran", %w[uninsured] ],
  # E05 is dual-eligible: Medicare AND Medicaid coverages simultaneously.
  [ 5, "class-a", "housed", "none", "non-veteran", %w[medicare medicaid] ],
  [ 7, "class-c", "housed", "none", "veteran", %w[medicare] ],
  [ 9, "class-d", "housed", "seasonal", "non-veteran", %w[private] ]
].freeze

def supplemental_observation(patient_seq:, seq:, attribute:, value:)
  {
    resourceType: "Observation",
    id: format("demo-epic-suppl-obs-%03d", seq),
    status: "final",
    category: [ { coding: [ { system: "http://terminology.hl7.org/CodeSystem/observation-category",
                          code: "social-history" } ] } ],
    code: { coding: [ { system: ATTRIBUTE_CS, code: attribute } ], text: attribute },
    subject: { reference: "Patient/#{epic_id('Pt', patient_seq)}" },
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
        id: format("demo-epic-suppl-cov-%03d", cov_seq),
        status: "active",
        type: { coding: [ { system: PAYER_CS, code: payer } ], text: payer },
        beneficiary: { reference: "Patient/#{epic_id('Pt', patient_seq)}" },
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
  fixtures = File.expand_path("../lib/rook/demo/fixtures/epic", __dir__)
  write_ndjson_feed(File.join(fixtures, "primary_fhir"), build_primary)
  write_ndjson_feed(File.join(fixtures, "supplemental"), build_supplemental)
end
