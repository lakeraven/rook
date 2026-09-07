# frozen_string_literal: true

require "fhir_models"

module Rook
  # Detects whether a diagnosis is a reportable condition per public health
  # surveillance requirements. Supports configurable condition lists by
  # jurisdiction (federal, state, tribal).
  #
  # Used by electronic case reporting (eCR) workflows to trigger eICR
  # generation when a reportable condition is diagnosed.
  #
  # Input is FHIR-native: #check takes a FHIR::Condition (every coding on
  # Condition.code is checked — ICD-10-CM, SNOMED CT, etc.), a bare
  # FHIR::CodeableConcept (the shape Condition.code holds), or a bare
  # FHIR::Coding. Condition lists remain injected configuration.
  #
  # A FHIR::Condition whose verificationStatus is entered-in-error or
  # refuted is never reportable, regardless of its codes. Bare
  # Coding/CodeableConcept inputs carry no verificationStatus and are
  # checked on codes alone.
  #
  # Configured :codes entries are either bare code strings ("A15.0"),
  # which match a coding by code alone in any system, or
  # { system:, code: } hashes, which additionally require the coding's
  # system to match.
  class ReportableConditionService
    VERIFICATION_STATUS_SYSTEM = "http://terminology.hl7.org/CodeSystem/condition-ver-status"
    NEGATING_VERIFICATION_CODES = %w[entered-in-error refuted].freeze

    # Detection outcome for one diagnosis.
    Result = Data.define(:reportable, :condition_name, :jurisdiction, :urgency) do
      def reportable?
        reportable
      end
    end

    # @param conditions [Array<Hash>] entries with :codes
    #   (Array<String, Hash> — bare code strings or { system:, code: }
    #   hashes), :name, :urgency
    # @param jurisdiction [String]
    def initialize(conditions:, jurisdiction: "US")
      @conditions = conditions
      @jurisdiction = jurisdiction
      @code_index = build_code_index
    end

    # Check whether a diagnosis is reportable.
    # @param condition [FHIR::Condition, FHIR::CodeableConcept, FHIR::Coding]
    # @return [Result]
    def check(condition:)
      return not_reportable_result if negated_verification_status?(condition)

      codings(condition).each do |coding|
        code = coding.code.to_s.strip
        next if code.empty?

        entry = matching_entry(code, coding.system)
        next unless entry

        return Result.new(
          reportable: true,
          condition_name: entry[:name],
          jurisdiction: @jurisdiction,
          urgency: entry[:urgency]
        )
      end

      not_reportable_result
    end

    private

    # A Condition marked entered-in-error or refuted is not a diagnosis;
    # only FHIR::Condition carries verificationStatus.
    def negated_verification_status?(input)
      return false unless input.is_a?(FHIR::Condition)

      Array(input.verificationStatus&.coding).any? do |coding|
        NEGATING_VERIFICATION_CODES.include?(coding.code) &&
          (coding.system.nil? || coding.system == VERIFICATION_STATUS_SYSTEM)
      end
    end

    def codings(input)
      case input
      when FHIR::Condition
        Array(input.code&.coding)
      when FHIR::CodeableConcept
        Array(input.coding)
      when FHIR::Coding
        [ input ]
      when nil
        []
      else
        raise ArgumentError,
          "condition must be a FHIR::Condition, FHIR::CodeableConcept, or FHIR::Coding"
      end
    end

    # Index: code string => [ { system: (nil for bare-string config),
    # condition: entry }, ... ]. A nil system means legacy code-only
    # matching; a present system must equal the coding's system.
    def build_code_index
      index = {}
      @conditions.each do |condition|
        condition[:codes].each do |code|
          system, bare_code = code.is_a?(Hash) ? [ code[:system], code[:code] ] : [ nil, code ]
          (index[bare_code] ||= []) << { system: system, condition: condition }
        end
      end
      index
    end

    def matching_entry(code, coding_system)
      candidates = @code_index[code]
      return nil unless candidates

      candidates.find { |c| c[:system].nil? || c[:system] == coding_system }&.fetch(:condition)
    end

    def not_reportable_result
      Result.new(reportable: false, condition_name: nil, jurisdiction: @jurisdiction, urgency: nil)
    end
  end
end
