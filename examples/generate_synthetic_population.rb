# frozen_string_literal: true

# DEMO / REFERENCE ASSET — NOT the production measure engine.
#
# Deterministic generator for the synthetic FHIR R4 population used by the
# demo-scoped UDS quality report (Rook::Demo). Run once to (re)produce the
# committed fixture at:
#
#   lib/rook/demo/fixtures/synthetic_population.json
#
# Usage:
#   ruby examples/generate_synthetic_population.rb
#
# The population contains NO real PHI. Names are NATO-phonetic placeholders,
# demographics are synthetic, and the "tribal clinic" framing uses generic,
# non-identifying values only (no real tribe/partner/customer names).
#
# The counts are hand-authored so the demo measures compute known, testable
# rates over the population (see test/demo/uds_report_test.rb):
#
#   Diabetes: HbA1c Poor Control (>9%)  -> denom 20, numerator 8, rate 0.40
#   Controlling High Blood Pressure     -> denom 15, numerator 9, rate 0.60

require "json"
require "date"

# Measurement period the fixture is authored against.
PERIOD_END = Date.new(2025, 12, 31)

# ICD-10 / SNOMED codings reused across resources.
DM_ICD10 = {system: "http://hl7.org/fhir/sid/icd-10-cm", code: "E11.9",
            display: "Type 2 diabetes mellitus without complications"}.freeze
DM_SNOMED = {system: "http://snomed.info/sct", code: "44054006",
             display: "Type 2 diabetes mellitus"}.freeze
HTN_ICD10 = {system: "http://hl7.org/fhir/sid/icd-10-cm", code: "I10",
             display: "Essential (primary) hypertension"}.freeze
HTN_SNOMED = {system: "http://snomed.info/sct", code: "38341003",
              display: "Hypertensive disorder"}.freeze

HBA1C_LOINC = {system: "http://loinc.org", code: "4548-4",
               display: "Hemoglobin A1c/Hemoglobin.total in Blood"}.freeze
BP_LOINC = {system: "http://loinc.org", code: "85354-9",
            display: "Blood pressure panel with all children optional"}.freeze
SYS_LOINC = {system: "http://loinc.org", code: "8480-6", display: "Systolic blood pressure"}.freeze
DIA_LOINC = {system: "http://loinc.org", code: "8462-4", display: "Diastolic blood pressure"}.freeze

# Placeholder family names (NATO phonetic) — obviously synthetic, no ethnic
# connotation, no real-person or partner names.
FAMILY = %w[
  Alpha Bravo Charlie Delta Echo Foxtrot Golf Hotel India Juliett
  Kilo Lima Mike November Oscar Papa Quebec Romeo Sierra Tango
  Uniform Victor Whiskey Xray Yankee Zulu Anchor Beacon Cedar Drift
  Ember Flint Grove Harbor Ivory
].freeze

def birthdate_for_age(age)
  # Deterministic: birthday July 1 of the birth year, as of PERIOD_END.
  Date.new(PERIOD_END.year - age, 7, 1).to_s
end

def patient_resource(seq:, gender:, age:)
  {
    resourceType: "Patient",
    id: format("demo-pt-%03d", seq),
    meta: {profile: ["http://hl7.org/fhir/us/core/StructureDefinition/us-core-patient"]},
    extension: [
      {
        # US Core Race — all synthetic patients coded AI/AN.
        url: "http://hl7.org/fhir/us/core/StructureDefinition/us-core-race",
        extension: [
          {url: "ombCategory",
           valueCoding: {system: "urn:oid:2.16.840.1.113883.6.238",
                         code: "1002-5", display: "American Indian or Alaska Native"}},
          {url: "text", valueString: "American Indian or Alaska Native"}
        ]
      },
      {
        # US Core Tribal Affiliation — SYNTHETIC placeholder value only.
        # Deliberately NOT a real federally-recognized tribe entry.
        url: "http://hl7.org/fhir/us/core/StructureDefinition/us-core-tribal-affiliation",
        extension: [
          {url: "tribalAffiliation",
           valueCodeableConcept: {
             coding: [{system: "http://terminology.hl7.org/CodeSystem/v3-TribalEntityUS",
                       code: "TE-DEMO", display: "Synthetic tribal affiliation (demo)"}],
             text: "Synthetic tribal affiliation (demo)"
           }}
        ]
      }
    ],
    name: [{use: "official", family: FAMILY[seq - 1], given: %w[Casey]}],
    gender: gender,
    birthDate: birthdate_for_age(age)
  }
end

def condition_resource(patient_id:, seq:, icd:, snomed:, onset:)
  {
    resourceType: "Condition",
    id: format("demo-cond-%03d", seq),
    clinicalStatus: {coding: [{system: "http://terminology.hl7.org/CodeSystem/condition-clinical",
                               code: "active"}]},
    verificationStatus: {coding: [{system: "http://terminology.hl7.org/CodeSystem/condition-ver-status",
                                   code: "confirmed"}]},
    category: [{coding: [{system: "http://terminology.hl7.org/CodeSystem/condition-category",
                          code: "encounter-diagnosis"}]}],
    code: {coding: [icd, snomed], text: icd[:display]},
    subject: {reference: "Patient/#{patient_id}"},
    onsetDateTime: onset
  }
end

def hba1c_resource(patient_id:, seq:, value:, effective:)
  {
    resourceType: "Observation",
    id: format("demo-obs-a1c-%03d", seq),
    status: "final",
    category: [{coding: [{system: "http://terminology.hl7.org/CodeSystem/observation-category",
                          code: "laboratory"}]}],
    code: {coding: [HBA1C_LOINC], text: HBA1C_LOINC[:display]},
    subject: {reference: "Patient/#{patient_id}"},
    effectiveDateTime: effective,
    valueQuantity: {value: value, unit: "%", system: "http://unitsofmeasure.org", code: "%"}
  }
end

def bp_resource(patient_id:, seq:, systolic:, diastolic:, effective:)
  {
    resourceType: "Observation",
    id: format("demo-obs-bp-%03d", seq),
    status: "final",
    category: [{coding: [{system: "http://terminology.hl7.org/CodeSystem/observation-category",
                          code: "vital-signs"}]}],
    code: {coding: [BP_LOINC], text: "Blood pressure"},
    subject: {reference: "Patient/#{patient_id}"},
    effectiveDateTime: effective,
    component: [
      {code: {coding: [SYS_LOINC], text: SYS_LOINC[:display]},
       valueQuantity: {value: systolic, unit: "mmHg", system: "http://unitsofmeasure.org", code: "mm[Hg]"}},
      {code: {coding: [DIA_LOINC], text: DIA_LOINC[:display]},
       valueQuantity: {value: diastolic, unit: "mmHg", system: "http://unitsofmeasure.org", code: "mm[Hg]"}}
    ]
  }
end

# ---------------------------------------------------------------------------
# Population definition (hand-authored so measure counts are known/testable).
#
# hba1c: array of [value, "YYYY-MM-DD"] readings (most recent wins).
# bp:    array of [systolic, diastolic, "YYYY-MM-DD"] readings.
# Readings dated in 2024 are intentionally OUTSIDE the 2025 measurement period.
# ---------------------------------------------------------------------------
def population_spec
  spec = []

  # --- Diabetes denominator (age 18-75) : 20 patients (P01..P20) ------------
  # 8 in numerator (poor control >9% OR no HbA1c in period).
  poor = [
    {age: 54, hba1c: [[10.2, "2025-06-10"]]},              # P01
    {age: 61, hba1c: [[9.5, "2025-08-02"]]},              # P02
    {age: 47, hba1c: [[11.0, "2025-03-15"]]},              # P03
    {age: 39, hba1c: [[9.1, "2025-11-20"]]},              # P04  just over 9
    {age: 66, hba1c: [[12.4, "2025-02-05"]]},              # P05
    {age: 58, hba1c: [[8.3, "2024-12-01"]]},              # P06  last test pre-period -> no test in period
    {age: 44, hba1c: []},                                  # P07  never tested
    {age: 72, hba1c: [[7.9, "2024-09-09"]]}               # P08  pre-period only
  ]
  # 12 controlled (most recent HbA1c <= 9% within period).
  controlled = [
    {age: 50, hba1c: [[6.8, "2025-05-01"]]},               # P09
    {age: 63, hba1c: [[7.2, "2025-07-11"]]},               # P10
    {age: 41, hba1c: [[8.9, "2025-09-19"]]},               # P11
    {age: 55, hba1c: [[9.0, "2025-04-04"]]},               # P12  exactly 9.0 -> not >9
    {age: 68, hba1c: [[5.9, "2025-10-10"]]},               # P13
    {age: 37, hba1c: [[7.7, "2025-06-06"]]},               # P14
    {age: 59, hba1c: [[8.1, "2025-02-22"]]},               # P15
    {age: 45, hba1c: [[6.5, "2025-12-01"]]},               # P16
    {age: 71, hba1c: [[7.0, "2025-01-15"]]},               # P17
    {age: 33, hba1c: [[8.8, "2025-08-30"]]},               # P18
    {age: 52, hba1c: [[6.2, "2025-11-11"]]},               # P19
    {age: 60, hba1c: [[10.5, "2025-02-01"], [8.0, "2025-11-05"]]} # P20 most-recent controls
  ]

  # P01..P05 also carry hypertension with CONTROLLED BP (dual diagnosis).
  htn_controlled_for_diabetics = {
    0 => [128, 82, "2025-06-10"],
    1 => [118, 76, "2025-08-02"],
    2 => [134, 88, "2025-03-15"],
    3 => [139, 89, "2025-11-20"], # just under 140/90
    4 => [120, 80, "2025-02-05"]
  }

  (poor + controlled).each_with_index do |p, i|
    gender = i.even? ? "female" : "male"
    entry = {age: p[:age], gender: gender, diabetes: true, hba1c: p[:hba1c], bp: []}
    if htn_controlled_for_diabetics.key?(i)
      s, d, on = htn_controlled_for_diabetics[i]
      entry[:hypertension] = true
      entry[:bp] = [[s, d, on]]
    end
    spec << entry
  end

  # --- Diabetics OUTSIDE the 18-75 age band (excluded from denominator) -----
  spec << {age: 80, gender: "male", diabetes: true, hba1c: [[12.0, "2025-05-05"]], bp: []} # P21
  spec << {age: 16, gender: "female", diabetes: true, hba1c: [[11.0, "2025-05-05"]], bp: []} # P22

  # --- Hypertension-only denominator (age 18-85) : 10 more patients ---------
  htn_only = [
    {age: 49, bp: [[130, 85, "2025-07-01"]], controlled: true},                    # P23
    {age: 57, bp: [[150, 95, "2025-01-10"], [122, 78, "2025-10-12"]], controlled: true}, # P24 most-recent controls
    {age: 62, bp: [[125, 79, "2025-05-05"]], controlled: true},                    # P25
    {age: 70, bp: [[110, 70, "2025-09-09"]], controlled: true},                    # P26
    {age: 53, bp: [[145, 92, "2025-04-04"]], controlled: false},                   # P27 uncontrolled
    {age: 66, bp: [[160, 100, "2025-06-06"]], controlled: false},                  # P28
    {age: 48, bp: [[140, 90, "2025-03-03"]], controlled: false},                   # P29 exactly 140/90
    {age: 74, bp: [[138, 91, "2025-07-07"]], controlled: false},                   # P30 diastolic 91
    {age: 59, bp: [], controlled: false},                                          # P31 no reading in period
    {age: 81, bp: [[150, 95, "2024-11-01"]], controlled: false}                    # P32 pre-period only
  ]
  htn_only.each_with_index do |h, i|
    spec << {age: h[:age], gender: i.even? ? "female" : "male",
              hypertension: true, hba1c: [], bp: h[:bp]}
  end

  # --- Healthy controls (no qualifying conditions) : 3 patients -------------
  spec << {age: 29, gender: "female", hba1c: [[5.2, "2025-06-01"]], bp: [[110, 70, "2025-06-01"]]} # P33
  spec << {age: 42, gender: "male", hba1c: [], bp: [[118, 74, "2025-06-01"]]}                    # P34
  spec << {age: 35, gender: "female", hba1c: [], bp: []}                                            # P35

  spec
end

def build_bundle
  entries = []
  cond_seq = 0
  a1c_seq = 0
  bp_seq = 0

  population_spec.each_with_index do |p, idx|
    seq = idx + 1
    pid = format("demo-pt-%03d", seq)
    entries << {resource: patient_resource(seq: seq, gender: p[:gender], age: p[:age])}

    if p[:diabetes]
      cond_seq += 1
      entries << {resource: condition_resource(patient_id: pid, seq: cond_seq,
        icd: DM_ICD10, snomed: DM_SNOMED,
        onset: "2019-04-01")}
    end
    if p[:hypertension]
      cond_seq += 1
      entries << {resource: condition_resource(patient_id: pid, seq: cond_seq,
        icd: HTN_ICD10, snomed: HTN_SNOMED,
        onset: "2020-02-01")}
    end
    (p[:hba1c] || []).each do |value, effective|
      a1c_seq += 1
      entries << {resource: hba1c_resource(patient_id: pid, seq: a1c_seq,
        value: value, effective: effective)}
    end
    (p[:bp] || []).each do |systolic, diastolic, effective|
      bp_seq += 1
      entries << {resource: bp_resource(patient_id: pid, seq: bp_seq,
        systolic: systolic, diastolic: diastolic,
        effective: effective)}
    end
  end

  {
    resourceType: "Bundle",
    id: "rook-demo-synthetic-population",
    type: "collection",
    entry: entries
  }
end

if __FILE__ == $PROGRAM_NAME
  out = File.expand_path("../lib/rook/demo/fixtures/synthetic_population.json", __dir__)
  require "fileutils"
  FileUtils.mkdir_p(File.dirname(out))
  File.write(out, "#{JSON.pretty_generate(build_bundle)}\n")
  bundle = JSON.parse(File.read(out))
  patients = bundle["entry"].count { |e| e["resource"]["resourceType"] == "Patient" }
  puts "Wrote #{out}"
  puts "  #{bundle["entry"].size} resources, #{patients} patients"
end
