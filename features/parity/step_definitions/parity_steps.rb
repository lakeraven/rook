# frozen_string_literal: true

# CRS parity step definitions — the ROOK DRIVER (rook#99): seed steps build
# FHIR resources exactly per the canonical expansions in
# features/parity/VOCABULARY.md and docs/measures/fhir-mapping.md, load them
# through the real ingest seam, and assert per-patient membership against
# Rook::Crs::NationalGpraReport. The CRS driver (rook#99 P2) translates the
# SAME steps into FileMan seeds and runs real BGP — one spec, two systems.
#
# The vocabulary is TYPED: one step per PCC/BHS-level fact. A new fact gets a
# new step there — never a looser parse here.

require "date"
require "rook/crs"
require "rook/ingest/resource_feed"

DATE = /\d{4}-\d{2}-\d{2}/
T = Rook::Crs::Terminology

DRIVER_SOURCE = Rook::SourceDescriptor.new(
  id: "parity-rook-driver", platform: :rpms, channel: :primary_fhir)

module ParityDriver
  def parity_assert(condition, message)
    raise "parity assertion failed: #{message}" unless condition
  end

  def resources = (@resources ||= [])
  def next_id = (@sequence = (@sequence || 0) + 1).to_s

  def period_start = @period.first
  def period_end = @period.last

  # -- Canonical builders (VOCABULARY.md / fhir-mapping.md) -------------------

  def build_patient(name, age, sex, beneficiary: "01", community: true)
    resources << {
      "resourceType" => "Patient", "id" => name,
      "gender" => sex,
      "birthDate" => ((period_end << (12 * age)) - 183).iso8601,
      "extension" => [
        { "url" => T::IHS_BENEFICIARY_EXT, "valueCode" => beneficiary },
        { "url" => T::GPRA_COMMUNITY_EXT, "valueBoolean" => community }
      ]
    }
    add_visit(name, period_start << 6)
  end

  def add_visit(patient, date, encounter_id: "enc-#{next_id}")
    resources << {
      "resourceType" => "Encounter", "id" => encounter_id, "status" => "finished",
      "class" => { "system" => "http://terminology.hl7.org/CodeSystem/v3-ActCode", "code" => "AMB" },
      "type" => [ { "coding" => [ { "system" => T::CLINIC_CODE_SYSTEM, "code" => "01" } ] } ],
      "subject" => { "reference" => "Patient/#{patient}" },
      "period" => { "start" => date.iso8601 }
    }
    encounter_id
  end

  def add_pov(patient, system, code, date)
    encounter_id = add_visit(patient, date)
    resources << {
      "resourceType" => "Condition", "id" => "cond-#{next_id}",
      "category" => [ { "coding" => [ { "code" => "encounter-diagnosis" } ] } ],
      "code" => { "coding" => [ { "system" => system, "code" => code } ] },
      "subject" => { "reference" => "Patient/#{patient}" },
      "encounter" => { "reference" => "Encounter/#{encounter_id}" },
      "recordedDate" => date.iso8601
    }
  end

  def add_problem_list(patient, system, code, status, entered, onset: nil)
    entry = {
      "resourceType" => "Condition", "id" => "cond-#{next_id}",
      "category" => [ { "coding" => [ { "code" => "problem-list-item" } ] } ],
      "clinicalStatus" => { "coding" => [ { "code" => status.downcase } ] },
      "code" => { "coding" => [ { "system" => system, "code" => code } ] },
      "subject" => { "reference" => "Patient/#{patient}" },
      "recordedDate" => entered.iso8601
    }
    entry["onsetDateTime"] = onset.iso8601 if onset
    resources << entry
  end

  def add_observation(patient, extra)
    resources << {
      "resourceType" => "Observation", "id" => "obs-#{next_id}", "status" => "final",
      "subject" => { "reference" => "Patient/#{patient}" }
    }.merge(extra)
  end

  def add_diabetic_macro(patient)
    build_patient(patient, 50, "female")
    add_pov(patient, T::ICD10, "E11.9", Date.new(2018, 6, 15))
    add_problem_list(patient, T::ICD10, "E11.9", "active", Date.new(2018, 6, 15))
    add_period_visits(patient, 2)
  end

  def add_hypertensive_macro(patient)
    build_patient(patient, 62, "female")
    add_pov(patient, T::ICD10, "I10", period_start + 30)
  end

  def add_period_visits(patient, count)
    count.times { |i| add_visit(patient, period_start + 60 + (i * 180)) }
  end

  def report
    @report ||= begin
      feed = Rook::Ingest::ResourceFeed.new(resources: resources, source: DRIVER_SOURCE)
      Rook::Crs::NationalGpraReport.new(resources: Rook::Ingest.load(feed), period: @period)
    end
  end
end

World(ParityDriver)

# -- Period and patient macros ------------------------------------------------

Given(/^the report period is (#{DATE}) to (#{DATE})$/) do |start_date, end_date|
  @period = Date.parse(start_date)..Date.parse(end_date)
end

Given(/^a (?:(female|male) )?User Population patient "([^"]*)" aged (\d+) at period end$/) do |sex, patient, age|
  build_patient(patient, age.to_i, sex || "female")
end

Given(/^a qualifying GPRA (diabetic|hypertensive) patient "([^"]*)"$/) do |kind, patient|
  kind == "diabetic" ? add_diabetic_macro(patient) : add_hypertensive_macro(patient)
end

Given(/^an otherwise-qualifying patient "([^"]*)" aged (\d+) with beneficiary class "([^"]*)"$/) do |patient, age, beneficiary|
  build_patient(patient, age.to_i, "female", beneficiary: beneficiary)
end

Given(/^an otherwise-qualifying patient "([^"]*)" aged (\d+) outside the GPRA community taxonomy$/) do |patient, age|
  build_patient(patient, age.to_i, "female", community: false)
end

# -- Visits -------------------------------------------------------------------

Given(/^"([^"]*)" has (\d+) ambulatory visits? during the report period$/) do |patient, count|
  add_period_visits(patient, count.to_i)
end

# -- Diagnoses and Problem List -----------------------------------------------

Given(/^"([^"]*)" has a diabetes POV first recorded (#{DATE})$/) do |patient, date|
  add_pov(patient, T::ICD10, "E11.9", Date.parse(date))
end

Given(/^"([^"]*)" has a diabetes Problem List entry with status "([^"]*)" entered (#{DATE})$/) do |patient, status, date|
  add_problem_list(patient, T::ICD10, "E11.9", status, Date.parse(date))
end

Given(/^"([^"]*)" has a diabetes Problem List entry with status "([^"]*)" onset (#{DATE}) entered (#{DATE})$/) do |patient, status, onset, entered|
  add_problem_list(patient, T::ICD10, "E11.9", status, Date.parse(entered), onset: Date.parse(onset))
end

Given(/^"([^"]*)" has a hypertension Problem List entry with status "([^"]*)" entered (#{DATE})$/) do |patient, status, date|
  add_problem_list(patient, T::ICD10, "I10", status, Date.parse(date))
end

Given(/^"([^"]*)" has a hypertension POV recorded (#{DATE})$/) do |patient, date|
  add_pov(patient, T::ICD10, "I10", Date.parse(date))
end

Given(/^"([^"]*)" has no hypertension Problem List entry$/) do |_patient|
  # Absence — seed nothing.
end

Given(/^"([^"]*)" has an ESRD diagnosis recorded (#{DATE})$/) do |patient, date|
  add_pov(patient, T::ICD10, "N18.6", Date.parse(date))
end

Given(/^"([^"]*)" is documented currently pregnant during the report period$/) do |patient|
  add_observation(patient,
    "code" => { "coding" => [ { "system" => T::LOINC, "code" => T::PREGNANCY_STATUS_LOINC } ] },
    "valueCodeableConcept" => { "coding" => [ { "system" => T::SNOMED, "code" => T::PREGNANT_SNOMED } ] },
    "effectiveDateTime" => (period_start + 30).iso8601)
end

Given(/^"([^"]*)" has a mood disorder POV recorded (#{DATE})$/) do |patient, date|
  add_pov(patient, T::ICD10, "F32.9", Date.parse(date))
end

Given(/^"([^"]*)" has a depression screening POV recorded (#{DATE})$/) do |patient, date|
  add_pov(patient, T::ICD10, "Z13.31", Date.parse(date))
end

# -- Labs, CPT evidence, measurements -----------------------------------------

Given(/^"([^"]*)" has an A1c lab result of ([\d.]+) resulted (#{DATE})$/) do |patient, value, date|
  add_observation(patient,
    "category" => [ { "coding" => [ { "code" => "laboratory" } ] } ],
    "code" => { "coding" => [ { "system" => T::LOINC, "code" => "4548-4" } ] },
    "effectiveDateTime" => date,
    "issued" => "#{date}T09:00:00Z",
    "valueQuantity" => { "value" => Float(value), "unit" => "%" })
end

Given(/^"([^"]*)" has an A1c lab test with no result on (#{DATE})$/) do |patient, date|
  add_observation(patient,
    "category" => [ { "coding" => [ { "code" => "laboratory" } ] } ],
    "code" => { "coding" => [ { "system" => T::LOINC, "code" => "4548-4" } ] },
    "effectiveDateTime" => "#{date}T08:00:00Z",
    "dataAbsentReason" => { "coding" => [ { "code" => "unknown" } ] })
end

Given(/^"([^"]*)" has no A1c documented during the report period$/) do |_patient|
  # Absence — seed nothing.
end

Given(/^"([^"]*)" has CPT "([^"]*)" recorded (#{DATE})$/) do |patient, code, date|
  resources << {
    "resourceType" => "Procedure", "id" => "proc-#{next_id}", "status" => "completed",
    "code" => { "coding" => [ { "system" => T::CPT, "code" => code } ] },
    "subject" => { "reference" => "Patient/#{patient}" },
    "performedDateTime" => date
  }
end

Given(/^"([^"]*)" has a BP reading of (\d+)\/(\d+) on (#{DATE}) at an ambulatory visit$/) do |patient, sys, dia, date|
  encounter_id = add_visit(patient, Date.parse(date))
  add_observation(patient,
    "category" => [ { "coding" => [ { "code" => "vital-signs" } ] } ],
    "code" => { "coding" => [ { "system" => T::LOINC, "code" => "85354-9" } ] },
    "encounter" => { "reference" => "Encounter/#{encounter_id}" },
    "effectiveDateTime" => date,
    "component" => [
      { "code" => { "coding" => [ { "system" => T::LOINC, "code" => "8480-6" } ] },
        "valueQuantity" => { "value" => sys.to_i } },
      { "code" => { "coding" => [ { "system" => T::LOINC, "code" => "8462-4" } ] },
        "valueQuantity" => { "value" => dia.to_i } }
    ])
end

Given(/^"([^"]*)" has no BP reading during the report period$/) do |_patient|
  # Absence — seed nothing.
end

Given(/^"([^"]*)" has an EPDS measurement recorded (#{DATE})$/) do |patient, date|
  add_observation(patient,
    "category" => [ { "coding" => [ { "code" => "survey" } ] } ],
    "code" => { "coding" => [ { "system" => T::MEASUREMENT_TYPE_SYSTEM, "code" => "EPDS" } ] },
    "effectiveDateTime" => date,
    "valueQuantity" => { "value" => 6 })
end

Given(/^"([^"]*)" has a PHQ-9 measurement recorded (#{DATE})$/) do |patient, date|
  add_observation(patient,
    "category" => [ { "coding" => [ { "code" => "survey" } ] } ],
    "code" => { "coding" => [ { "system" => T::LOINC, "code" => T::PHQ9_LOINC } ] },
    "effectiveDateTime" => date,
    "valueQuantity" => { "value" => 4 })
end

# -- BHS-side facts -----------------------------------------------------------

Given(/^"([^"]*)" has a BHS depression screening \(problem code 14\.1\) recorded (#{DATE})$/) do |patient, date|
  add_observation(patient,
    "code" => { "coding" => [ { "system" => T::BHS_PROBLEM_SYSTEM, "code" => "14.1" } ] },
    "effectiveDateTime" => date)
end

Given(/^"([^"]*)" has a BH depression screening exam recorded (#{DATE}) with result "([^"]*)"$/) do |patient, date, result|
  add_observation(patient,
    "code" => { "coding" => [ { "system" => T::BH_EXAM_SYSTEM, "code" => "36" } ] },
    "valueCodeableConcept" => { "coding" => [ { "system" => T::BH_EXAM_RESULT_SYSTEM, "code" => result } ] },
    "effectiveDateTime" => date)
end

Given(/^"([^"]*)" has no depression screening during the report period$/) do |_patient|
  # Absence — seed nothing.
end

# -- Execution and membership assertions --------------------------------------

When("the National GPRA report is run") do
  report
end

Then(/^"([^"]*)" is (not )?in the "([^"]*)" (?:GPRA )?(numerator|denominator)$/) do |patient, negated, label, population|
  member = population == "denominator" ? report.in_denominator?(patient, label) : report.in_numerator?(patient, label)
  expected = negated.nil?
  parity_assert(member == expected,
    "expected #{patient} #{expected ? 'in' : 'NOT in'} the #{label.inspect} #{population}")
end

Then(/^"([^"]*)" is (not )?on the "([^"]*)" patient list$/) do |patient, negated, list|
  member = report.on_patient_list?(patient, list)
  expected = negated.nil?
  parity_assert(member == expected,
    "expected #{patient} #{expected ? 'on' : 'NOT on'} the #{list.inspect} patient list")
end
