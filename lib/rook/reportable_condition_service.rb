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
  class ReportableConditionService
    # Detection outcome for one diagnosis.
    Result = Data.define(:reportable, :condition_name, :jurisdiction, :urgency) do
      def reportable?
        reportable
      end
    end

    # @param conditions [Array<Hash>] entries with :codes (Array<String>),
    #   :name, :urgency
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
      codings(condition).each do |coding|
        code = coding.code.to_s.strip
        next if code.empty?

        entry = @code_index[code]
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

    def build_code_index
      index = {}
      @conditions.each do |condition|
        condition[:codes].each { |code| index[code] = condition }
      end
      index
    end

    def not_reportable_result
      Result.new(reportable: false, condition_name: nil, jurisdiction: @jurisdiction, urgency: nil)
    end
  end
end
