# frozen_string_literal: true

module Rook
  module CareCascade
    # Thin, read-only wrapper over a single patient's FHIR R4 resources.
    #
    # Rook is EHR-agnostic: the host supplies FHIR-shaped resource hashes
    # (Observation, Condition, MedicationRequest, Procedure, ...) via an
    # adapter. This wrapper exposes the small set of query predicates the
    # cascade stage matchers need, so matcher logic reads clearly and stays
    # free of FHIR traversal detail.
    #
    # Expected input shape:
    #   {
    #     patient_id: "p1",
    #     site:       "mobile-unit-1",   # program site / team
    #     ai_an:      true,              # AI/AN status (for disaggregation)
    #     resources:  [ <FHIR resource hash>, ... ]
    #   }
    #
    # FHIR interpretation/value codes used to decide "positive"/"negative"
    # are a documented starter set — hosts may pass their own via matchers.
    class PatientRecord
      # FHIR ObservationInterpretation codes that denote a positive result.
      POSITIVE_INTERPRETATIONS = %w[POS DET REACTIVE].freeze
      # ...and a negative / resolved result.
      NEGATIVE_INTERPRETATIONS = %w[NEG ND NR].freeze

      # SNOMED CT qualifier values sometimes carried in valueCodeableConcept.
      POSITIVE_VALUE_CODES = %w[10828004 260373001 11214006].freeze # Positive, Detected, Reactive
      NEGATIVE_VALUE_CODES = %w[260385009 260415000 131194007].freeze # Negative, Not detected, Non-reactive

      attr_reader :patient_id, :site, :ai_an

      def self.wrap(record)
        record.is_a?(PatientRecord) ? record : new(record)
      end

      def initialize(record)
        @patient_id = record[:patient_id] || record["patient_id"]
        @site       = record[:site] || record["site"]
        @ai_an      = record[:ai_an] || record["ai_an"] || false
        @resources  = Array(record[:resources] || record["resources"])
      end

      def demographics
        { patient_id: patient_id, site: site, ai_an: ai_an }
      end

      # An Observation with one of +codes+ exists (any result) — the test was
      # performed.
      def observation_present?(codes)
        observations(codes).any?
      end

      # An Observation with one of +codes+ has a positive/reactive/detected
      # result.
      def positive_observation?(codes)
        observations(codes).any? { |obs| positive_result?(obs) }
      end

      # An Observation with one of +codes+ has an explicitly negative result.
      def negative_observation?(codes)
        observations(codes).any? { |obs| negative_result?(obs) }
      end

      # A Condition with one of +codes+ is recorded (active or unspecified
      # clinical status; resolved conditions are excluded).
      def condition_present?(codes)
        resources_of_type("Condition").any? do |cond|
          coding_matches?(cond[:code] || cond["code"], codes) && !condition_resolved?(cond)
        end
      end

      # A MedicationRequest or MedicationStatement for one of +codes+ exists.
      def medication_present?(codes)
        %w[MedicationRequest MedicationStatement].any? do |type|
          resources_of_type(type).any? do |med|
            concept = med[:medicationCodeableConcept] || med["medicationCodeableConcept"]
            coding_matches?(concept, codes)
          end
        end
      end

      # A Procedure with one of +codes+ is recorded.
      def procedure_present?(codes)
        resources_of_type("Procedure").any? do |proc_res|
          coding_matches?(proc_res[:code] || proc_res["code"], codes)
        end
      end

      private

      def observations(codes)
        resources_of_type("Observation").select do |obs|
          coding_matches?(obs[:code] || obs["code"], codes)
        end
      end

      def resources_of_type(type)
        @resources.select { |r| (r[:resourceType] || r["resourceType"]) == type }
      end

      def positive_result?(obs)
        interpretation_in?(obs, POSITIVE_INTERPRETATIONS) ||
          value_code_in?(obs, POSITIVE_VALUE_CODES)
      end

      def negative_result?(obs)
        interpretation_in?(obs, NEGATIVE_INTERPRETATIONS) ||
          value_code_in?(obs, NEGATIVE_VALUE_CODES)
      end

      def interpretation_in?(obs, code_set)
        interpretations = Array(obs[:interpretation] || obs["interpretation"])
        interpretations.any? { |cc| any_coding_code?(cc, code_set) }
      end

      def value_code_in?(obs, code_set)
        concept = obs[:valueCodeableConcept] || obs["valueCodeableConcept"]
        any_coding_code?(concept, code_set)
      end

      def condition_resolved?(cond)
        status = cond[:clinicalStatus] || cond["clinicalStatus"]
        codes = coding_codes(status)
        codes.include?("resolved") || codes.include?("inactive")
      end

      # Does a CodeableConcept carry any coding whose code is in +codes+?
      def coding_matches?(codeable_concept, codes)
        wanted = Array(codes)
        coding_codes(codeable_concept).any? { |c| wanted.include?(c) }
      end

      def any_coding_code?(codeable_concept, code_set)
        coding_codes(codeable_concept).any? { |c| code_set.include?(c) }
      end

      def coding_codes(codeable_concept)
        return [] unless codeable_concept

        codings = codeable_concept[:coding] || codeable_concept["coding"] || []
        codings.map { |coding| coding[:code] || coding["code"] }.compact
      end
    end
  end
end
