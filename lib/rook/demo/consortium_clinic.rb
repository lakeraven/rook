# frozen_string_literal: true

require "date"
require "json"
require "rook/demo/synthetic_population"

module Rook
  module Demo
    # DEMO / REFERENCE ONLY — see Rook::Demo. NOT the production engine.
    #
    # Builds ONE synthetic clinic for the consortium demo: a deterministic,
    # in-memory FHIR R4 collection Bundle generated from a compact profile
    # (patient count + target outcome fractions), wrapped as a
    # SyntheticPopulation. Reuses the exact resource shapes and codes from
    # examples/generate_synthetic_population.rb.
    #
    # Every synthetic patient carries BOTH a diabetes and a hypertension
    # diagnosis and falls in the 40-70 age band, so a clinic's full patient
    # count is the denominator for all three GPRA measures — this keeps the
    # per-clinic math legible for a sales demo. Deterministic and
    # index-driven only: no Random, Time.now, or Date.today.
    class ConsortiumClinic
      # A built clinic ready for reporting: display name, a GENERIC EHR label
      # (never a real vendor name — this is a synthetic demo), and population.
      Clinic = Struct.new(:name, :ehr_label, :population, keyword_init: true)

      # Compact input: patient count + target rates for the three GPRA
      # measures. Fractions are targets only — actual counts are rounded, so
      # the realized rate can differ slightly from the target.
      Profile = Struct.new(:name, :ehr_label, :id_prefix, :patient_count,
        :diabetes_poor_control_fraction, :bp_controlled_fraction,
        :depression_screened_fraction, keyword_init: true)

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

      # Placeholder surnames (NATO phonetic + nature words) — obviously
      # synthetic, no ethnic connotation, no real-person or partner names.
      SURNAMES = %w[
        Alpha Bravo Charlie Delta Echo Foxtrot Golf Hotel India Juliett
        Kilo Lima Mike November Oscar Papa Quebec Romeo Sierra Tango
        Uniform Victor Whiskey Xray Yankee Zulu Anchor Beacon Cedar Drift
        Ember Flint Grove Harbor Ivory Juniper Kestrel Lantern Meadow Nectar
      ].freeze

      def self.build(profile)
        new(profile).call
      end

      def initialize(profile)
        @profile = profile
      end

      def call
        bundle = JSON.parse(JSON.generate(build_bundle))
        Clinic.new(name: @profile.name, ehr_label: @profile.ehr_label,
          population: SyntheticPopulation.new(bundle))
      end

      private

      def build_bundle
        { resourceType: "Bundle", id: "#{@profile.id_prefix}-consortium-clinic",
         type: "collection", entry: entries }
      end

      def entries
        count = @profile.patient_count
        diabetes_poor_flags = spread_flags(count, (count * @profile.diabetes_poor_control_fraction).round)
        bp_controlled_flags = spread_flags(count, (count * @profile.bp_controlled_fraction).round)
        depression_screened_flags = spread_flags(count, (count * @profile.depression_screened_fraction).round)

        (0...count).flat_map do |index|
          seq = index + 1
          pid = patient_id(seq)
          patient_entries(pid, seq, index, diabetes_poor_flags[index], bp_controlled_flags[index],
            depression_screened_flags[index])
        end
      end

      def patient_entries(pid, seq, index, diabetes_poor, bp_controlled, depression_screened)
        entries = [
          { resource: patient_resource(seq: seq, index: index) },
          { resource: condition_resource(patient_id: pid, seq: seq, kind: :dm, icd: DM_ICD10, snomed: DM_SNOMED) },
          { resource: condition_resource(patient_id: pid, seq: seq, kind: :htn, icd: HTN_ICD10, snomed: HTN_SNOMED) },
          { resource: hba1c_resource(patient_id: pid, seq: seq, poor_control: diabetes_poor, index: index) },
          { resource: bp_resource(patient_id: pid, seq: seq, controlled: bp_controlled, index: index) }
        ]
        entries << { resource: phq9_resource(patient_id: pid, seq: seq, index: index) } if depression_screened
        entries
      end

      # Exactly +true_count+ trues spread evenly across +total+ slots
      # (Bresenham-style rasterization) — deterministic, no Random.
      def spread_flags(total, true_count)
        Array.new(total) { |i| ((i + 1) * true_count / total) > (i * true_count / total) }
      end

      def patient_id(seq)
        format("%<prefix>s-pt-%<seq>03d", prefix: @profile.id_prefix, seq: seq)
      end

      def age_for(index)
        40 + ((index * 7) % 31)
      end

      def effective_date(index, offset: 0)
        Date.new(2025, (((index + offset) % 12) + 1), (((index + offset) % 28) + 1)).to_s
      end

      def patient_resource(seq:, index:)
        {
          resourceType: "Patient",
          id: patient_id(seq),
          meta: { profile: [ "http://hl7.org/fhir/us/core/StructureDefinition/us-core-patient" ] },
          extension: [
            {
              # US Core Race — all synthetic patients coded AI/AN.
              url: "http://hl7.org/fhir/us/core/StructureDefinition/us-core-race",
              extension: [
                { url: "ombCategory",
                 valueCoding: { system: "urn:oid:2.16.840.1.113883.6.238",
                               code: "1002-5", display: "American Indian or Alaska Native" } },
                { url: "text", valueString: "American Indian or Alaska Native" }
              ]
            },
            {
              # US Core Tribal Affiliation — SYNTHETIC placeholder value only.
              # Deliberately NOT a real federally-recognized tribe entry.
              url: "http://hl7.org/fhir/us/core/StructureDefinition/us-core-tribal-affiliation",
              extension: [
                { url: "tribalAffiliation",
                 valueCodeableConcept: {
                   coding: [ { system: "http://terminology.hl7.org/CodeSystem/v3-TribalEntityUS",
                             code: "TE-DEMO", display: "Synthetic tribal affiliation (demo)" } ],
                   text: "Synthetic tribal affiliation (demo)"
                 } }
              ]
            }
          ],
          name: [ { use: "official", family: SURNAMES[index % SURNAMES.length], given: %w[Casey] } ],
          gender: index.even? ? "female" : "male",
          birthDate: Date.new(PERIOD_END.year - age_for(index), 7, 1).to_s
        }
      end

      def condition_resource(patient_id:, seq:, kind:, icd:, snomed:)
        {
          resourceType: "Condition",
          id: "#{@profile.id_prefix}-cond-#{kind}-#{format('%03d', seq)}",
          clinicalStatus: { coding: [ { system: "http://terminology.hl7.org/CodeSystem/condition-clinical",
                                     code: "active" } ] },
          verificationStatus: { coding: [ { system: "http://terminology.hl7.org/CodeSystem/condition-ver-status",
                                         code: "confirmed" } ] },
          category: [ { coding: [ { system: "http://terminology.hl7.org/CodeSystem/condition-category",
                                code: "encounter-diagnosis" } ] } ],
          code: { coding: [ icd, snomed ], text: icd[:display] },
          subject: { reference: "Patient/#{patient_id}" },
          onsetDateTime: kind == :dm ? "2019-04-01" : "2020-02-01"
        }
      end

      def hba1c_resource(patient_id:, seq:, poor_control:, index:)
        value = poor_control ? (9.5 + ((index % 6) * 0.4)).round(1) : (5.5 + ((index % 30) * 0.1)).round(1)
        {
          resourceType: "Observation",
          id: "#{@profile.id_prefix}-obs-a1c-#{format('%03d', seq)}",
          status: "final",
          category: [ { coding: [ { system: "http://terminology.hl7.org/CodeSystem/observation-category",
                                code: "laboratory" } ] } ],
          code: { coding: [ HBA1C_LOINC ], text: HBA1C_LOINC[:display] },
          subject: { reference: "Patient/#{patient_id}" },
          effectiveDateTime: effective_date(index),
          valueQuantity: { value: value, unit: "%", system: "http://unitsofmeasure.org", code: "%" }
        }
      end

      def bp_resource(patient_id:, seq:, controlled:, index:)
        systolic = controlled ? 110 + (index % 25) : 145 + (index % 18)
        diastolic = controlled ? 70 + (index % 15) : 92 + (index % 10)
        {
          resourceType: "Observation",
          id: "#{@profile.id_prefix}-obs-bp-#{format('%03d', seq)}",
          status: "final",
          category: [ { coding: [ { system: "http://terminology.hl7.org/CodeSystem/observation-category",
                                code: "vital-signs" } ] } ],
          code: { coding: [ BP_LOINC ], text: "Blood pressure" },
          subject: { reference: "Patient/#{patient_id}" },
          effectiveDateTime: effective_date(index, offset: 3),
          component: [
            { code: { coding: [ SYS_LOINC ], text: SYS_LOINC[:display] },
             valueQuantity: { value: systolic, unit: "mmHg", system: "http://unitsofmeasure.org", code: "mm[Hg]" } },
            { code: { coding: [ DIA_LOINC ], text: DIA_LOINC[:display] },
             valueQuantity: { value: diastolic, unit: "mmHg", system: "http://unitsofmeasure.org", code: "mm[Hg]" } }
          ]
        }
      end

      def phq9_resource(patient_id:, seq:, index:)
        {
          resourceType: "Observation",
          id: "#{@profile.id_prefix}-obs-phq9-#{format('%03d', seq)}",
          status: "final",
          category: [ { coding: [ { system: "http://terminology.hl7.org/CodeSystem/observation-category",
                                code: "survey" } ] } ],
          code: { coding: [ PHQ9_LOINC ], text: PHQ9_LOINC[:display] },
          subject: { reference: "Patient/#{patient_id}" },
          effectiveDateTime: effective_date(index, offset: 6),
          valueQuantity: { value: index % 20, unit: "{score}", system: "http://unitsofmeasure.org", code: "{score}" }
        }
      end
    end
  end
end
