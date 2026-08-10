# frozen_string_literal: true

require "time"

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
    #
    # === Trust / fail-closed rules
    # * A record with no +patient_id+ raises (ids feed PHI worklists; a nil id
    #   must never reach outreach).
    # * Clinical predicates honour FHIR +status+: only accepted, final resources
    #   count. Cancelled/draft/entered-in-error/aborted/preliminary data is
    #   ignored rather than trusted.
    # * Coding matches require BOTH system and code — an identical code in an
    #   unrelated terminology never satisfies a LOINC/RxNorm/ICD-10/SNOMED set.
    class PatientRecord
      class MissingIdentifierError < Rook::Error; end

      # FHIR ObservationInterpretation codes that denote a positive result.
      POSITIVE_INTERPRETATIONS = %w[POS DET REACTIVE].freeze
      # ...and a negative / resolved result.
      NEGATIVE_INTERPRETATIONS = %w[NEG ND NR].freeze

      # SNOMED CT qualifier values sometimes carried in valueCodeableConcept.
      POSITIVE_VALUE_CODES = %w[10828004 260373001 11214006].freeze # Positive, Detected, Reactive
      NEGATIVE_VALUE_CODES = %w[260385009 260415000 131194007].freeze # Negative, Not detected, Non-reactive

      # Accepted FHIR +status+ values per resource type. Anything else (including
      # a missing status) is treated as untrusted and ignored.
      ACCEPTED_OBSERVATION_STATUSES = %w[final amended corrected].freeze
      ACCEPTED_MEDICATION_REQUEST_STATUSES = %w[active completed on-hold stopped].freeze
      ACCEPTED_MEDICATION_STATEMENT_STATUSES = %w[active completed on-hold stopped].freeze
      ACCEPTED_PROCEDURE_STATUSES = %w[in-progress completed].freeze

      # Condition statuses that exclude a diagnosis from "active infection".
      RESOLVED_CLINICAL_STATUSES = %w[resolved inactive remission].freeze
      REFUTED_VERIFICATION_STATUSES = %w[entered-in-error refuted].freeze

      attr_reader :patient_id, :site, :ai_an, :resources

      def self.wrap(record)
        record.is_a?(PatientRecord) ? record : new(record)
      end

      # +ai_an+ is tri-state: true (AI/AN), false (explicitly not), or nil
      # (missing/unknown — preserved as its own disaggregation category).
      def initialize(record)
        @patient_id = presence(record[:patient_id] || record["patient_id"])
        raise MissingIdentifierError, "patient record is missing a patient_id" if @patient_id.nil?

        @site       = record[:site] || record["site"]
        @ai_an      = normalize_ai_an(record.key?(:ai_an) ? record[:ai_an] : record["ai_an"])
        @resources  = Array(record[:resources] || record["resources"])
      end

      def demographics
        { patient_id: patient_id, site: site, ai_an: ai_an }
      end

      # Combine another record for the same patient (deduplication merges the
      # resource lists so a patient split across rows is classified once).
      def merge(other)
        self.class.new(
          patient_id: patient_id,
          site: site || other.site,
          ai_an: ai_an.nil? ? other.ai_an : ai_an,
          resources: resources + other.resources
        )
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

      # An accepted, negative Observation for +codes+ whose effective time is at
      # or after +not_before+ exists. Used for post-treatment cure (SVR12): a
      # negative result that cannot be shown to post-date treatment does not
      # count. A negative result with no usable date fails closed (not credited).
      def negative_observation_after?(codes, not_before)
        observations(codes).any? do |obs|
          negative_result?(obs) && time_at_or_after?(observation_time(obs), not_before)
        end
      end

      # A Condition with one of +codes+ is recorded and neither resolved/inactive
      # nor refuted/entered-in-error.
      def condition_present?(codes)
        resources_of_type("Condition").any? do |cond|
          coding_matches?(cond[:code] || cond["code"], codes) &&
            !condition_resolved?(cond) && !condition_refuted?(cond)
        end
      end

      # An accepted MedicationRequest or MedicationStatement for one of +codes+
      # exists.
      def medication_present?(codes)
        accepted_medications.any? do |med|
          concept = med[:medicationCodeableConcept] || med["medicationCodeableConcept"]
          coding_matches?(concept, codes)
        end
      end

      # An accepted Procedure with one of +codes+ is recorded.
      def procedure_present?(codes)
        accepted_procedures.any? do |proc_res|
          coding_matches?(proc_res[:code] || proc_res["code"], codes)
        end
      end

      # Latest known treatment time (MedicationRequest.authoredOn, medication or
      # procedure effective/performed) for +codes+, or nil when undated/absent.
      def latest_treatment_time(codes)
        treatment_times(codes).max
      end

      private

      def observations(codes)
        resources_of_type("Observation").select do |obs|
          accepted_status?(obs, ACCEPTED_OBSERVATION_STATUSES) &&
            coding_matches?(obs[:code] || obs["code"], codes)
        end
      end

      def accepted_medications
        resources_of_type("MedicationRequest").select { |m| accepted_status?(m, ACCEPTED_MEDICATION_REQUEST_STATUSES) } +
          resources_of_type("MedicationStatement").select { |m| accepted_status?(m, ACCEPTED_MEDICATION_STATEMENT_STATUSES) }
      end

      def accepted_procedures
        resources_of_type("Procedure").select { |p| accepted_status?(p, ACCEPTED_PROCEDURE_STATUSES) }
      end

      def treatment_times(codes)
        med_times = accepted_medications.filter_map do |med|
          concept = med[:medicationCodeableConcept] || med["medicationCodeableConcept"]
          medication_time(med) if coding_matches?(concept, codes)
        end
        proc_times = accepted_procedures.filter_map do |proc_res|
          procedure_time(proc_res) if coding_matches?(proc_res[:code] || proc_res["code"], codes)
        end
        med_times + proc_times
      end

      def resources_of_type(type)
        @resources.select { |r| (r[:resourceType] || r["resourceType"]) == type }
      end

      def accepted_status?(resource, allowed)
        allowed.include?(resource[:status] || resource["status"])
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
        (coding_codes(status) & RESOLVED_CLINICAL_STATUSES).any?
      end

      def condition_refuted?(cond)
        status = cond[:verificationStatus] || cond["verificationStatus"]
        (coding_codes(status) & REFUTED_VERIFICATION_STATUSES).any?
      end

      # ---- Temporal helpers ------------------------------------------------

      def medication_time(med)
        parse_time(med[:authoredOn] || med["authoredOn"]) || effective_time(med)
      end

      def procedure_time(proc_res)
        parse_time(proc_res[:performedDateTime] || proc_res["performedDateTime"]) ||
          period_time(proc_res[:performedPeriod] || proc_res["performedPeriod"])
      end

      def observation_time(obs)
        effective_time(obs) || parse_time(obs[:issued] || obs["issued"])
      end

      def effective_time(resource)
        parse_time(resource[:effectiveDateTime] || resource["effectiveDateTime"]) ||
          period_time(resource[:effectivePeriod] || resource["effectivePeriod"])
      end

      def period_time(period)
        return nil unless period

        parse_time(period[:end] || period["end"]) || parse_time(period[:start] || period["start"])
      end

      def parse_time(value)
        return nil if value.nil? || value.to_s.strip.empty?

        Time.parse(value.to_s)
      rescue ArgumentError
        nil
      end

      def time_at_or_after?(time, not_before)
        return true if not_before.nil?

        !time.nil? && time >= not_before
      end

      # ---- Coding + demographic helpers ------------------------------------

      # Does a CodeableConcept carry any coding matching an entry in +code_set+?
      # Hash entries {system:, code:} require both to match; bare string entries
      # match on code only (for host-supplied legacy sets).
      def coding_matches?(codeable_concept, code_set)
        codings(codeable_concept).any? do |coding|
          system = coding[:system] || coding["system"]
          code   = coding[:code] || coding["code"]
          code_set.any? { |entry| code_set_entry_matches?(entry, system, code) }
        end
      end

      def code_set_entry_matches?(entry, system, code)
        if entry.is_a?(Hash)
          (entry[:system] || entry["system"]) == system && (entry[:code] || entry["code"]) == code
        else
          entry == code
        end
      end

      def any_coding_code?(codeable_concept, code_set)
        coding_codes(codeable_concept).any? { |c| code_set.include?(c) }
      end

      def coding_codes(codeable_concept)
        codings(codeable_concept).map { |coding| coding[:code] || coding["code"] }.compact
      end

      def codings(codeable_concept)
        return [] unless codeable_concept

        codeable_concept[:coding] || codeable_concept["coding"] || []
      end

      def presence(value)
        return nil if value.nil?

        value.to_s.strip.empty? ? nil : value
      end

      def normalize_ai_an(value)
        case value
        when true, false then value
        when nil then nil
        else normalize_ai_an_token(value)
        end
      end

      def normalize_ai_an_token(value)
        token = value.to_s.strip.downcase
        return true if %w[true t yes y 1].include?(token)
        return false if %w[false f no n 0].include?(token)

        nil # unknown / malformed preserved as its own category
      end
    end
  end
end
