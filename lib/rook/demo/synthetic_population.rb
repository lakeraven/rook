# frozen_string_literal: true

require "json"
require "date"

module Rook
  module Demo
    # DEMO / REFERENCE ONLY — see Rook::Demo.
    #
    # Loads the synthetic FHIR R4 collection Bundle fixture and exposes it as a
    # set of lightweight Patient value objects. Plain-Ruby parsing only; no
    # Pathling/Spark and no external FHIR gem. This is throwaway demo plumbing,
    # not the production data layer.
    class SyntheticPopulation
      DEFAULT_FIXTURE = File.expand_path("fixtures/synthetic_population.json", __dir__)

      # A single synthetic patient with its linked Conditions and Observations.
      Patient = Struct.new(:id, :family_name, :given_name, :gender, :birth_date,
        :tribal_affiliation, :condition_codes, :observations,
        keyword_init: true) do
        def name
          [ given_name, family_name ].compact.join(" ")
        end

        def age_on(date)
          years = date.year - birth_date.year
          years -= 1 if date < birth_date.next_year(years)
          years
        end

        def condition?(codes)
          !(condition_codes & Array(codes)).empty?
        end

        # Most recent Observation for a LOINC code whose effective date falls
        # within the (inclusive) period, or nil if none.
        def latest_observation(loinc_code, period)
          observations
            .select { |o| o.loinc == loinc_code && period.cover?(o.effective_date) }
            .max_by(&:effective_date)
        end
      end

      # A flattened Observation. For blood pressure, +components+ maps a LOINC
      # code to its numeric value (systolic 8480-6, diastolic 8462-4).
      Observation = Struct.new(:loinc, :value, :effective_date, :components, keyword_init: true)

      def self.default
        load_file(DEFAULT_FIXTURE)
      end

      def self.load_file(path)
        new(JSON.parse(File.read(path)))
      end

      def initialize(bundle)
        @bundle = bundle
        @patients = build_patients
      end

      attr_reader :patients

      private

      def resources
        @bundle.fetch("entry").map { |e| e.fetch("resource") }
      end

      def build_patients
        by_type = resources.group_by { |r| r["resourceType"] }
        conditions = (by_type["Condition"] || []).group_by { |c| subject_id(c) }
        observations = (by_type["Observation"] || []).group_by { |o| subject_id(o) }

        (by_type["Patient"] || []).map do |p|
          id = p.fetch("id")
          Patient.new(
            id: id,
            family_name: p.dig("name", 0, "family"),
            given_name: Array(p.dig("name", 0, "given")).first,
            gender: p["gender"],
            birth_date: Date.parse(p.fetch("birthDate")),
            tribal_affiliation: tribal_affiliation(p),
            condition_codes: (conditions[id] || []).flat_map { |c| codings(c["code"]) }.uniq,
            observations: (observations[id] || []).map { |o| build_observation(o) }
          )
        end
      end

      def subject_id(resource)
        resource.dig("subject", "reference").to_s.split("/").last
      end

      def codings(codeable_concept)
        Array(codeable_concept&.dig("coding")).map { |c| c["code"] }
      end

      def build_observation(obs)
        components = {}
        Array(obs["component"]).each do |comp|
          code = codings(comp["code"]).first
          components[code] = comp.dig("valueQuantity", "value")
        end
        Observation.new(
          loinc: codings(obs["code"]).first,
          value: obs.dig("valueQuantity", "value"),
          effective_date: Date.parse(obs.fetch("effectiveDateTime")),
          components: components
        )
      end

      def tribal_affiliation(patient)
        ext = Array(patient["extension"]).find do |e|
          e["url"] == "http://hl7.org/fhir/us/core/StructureDefinition/us-core-tribal-affiliation"
        end
        ext&.dig("extension", 0, "valueCodeableConcept", "text")
      end
    end
  end
end
