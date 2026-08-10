# frozen_string_literal: true

require "rook/care_cascade/stage"

module Rook
  module CareCascade
    # Defines the cascade stages for one condition and how a patient's FHIR
    # data is classified into them.
    #
    # === CQL seam (rook#1)
    #
    # +source+ declares HOW stage membership is decided:
    #
    #   :ruby_matchers  -- deterministic Ruby predicates over FHIR resources
    #                      (implemented here; honest computation, no CQL).
    #   :cql            -- membership decided by a CQL library evaluated against
    #                      the FHIR bundle. Rook's CQL execution engine is still
    #                      being selected (rook#1), so this path is declared but
    #                      NOT executable yet. CascadeService raises rather than
    #                      silently falling back — no faked results.
    #
    # When rook#1 lands, a condition's stages can be backed by published
    # Measure/Library resources without changing CascadeService or Report.
    class ConditionDefinition
      class UnknownConditionError < Rook::Error; end

      SOURCES = %i[ruby_matchers cql].freeze

      attr_reader :key, :name, :source, :stages, :matchers, :code_sets

      # @param stages [Array<Stage>] ordered from entry to terminal
      # @param matchers [Hash{Symbol=>#call}] stage key => predicate(PatientRecord)->bool.
      #   Required when source is :ruby_matchers; ignored for :cql.
      def initialize(key:, name:, stages:, matchers: {}, code_sets: {}, source: :ruby_matchers)
        unless SOURCES.include?(source)
          raise ArgumentError, "unknown source #{source.inspect}; expected one of #{SOURCES.inspect}"
        end

        @key = key
        @name = name
        @stages = stages
        @matchers = matchers
        @code_sets = code_sets
        @source = source
        validate!
      end

      def ruby_matchers?
        source == :ruby_matchers
      end

      def stage_keys
        stages.map(&:key)
      end

      def stage(key)
        stages.find { |s| s.key == key }
      end

      # Evaluate every stage matcher independently against a patient.
      # Returns { stage_key => bool }. Only valid for :ruby_matchers.
      def satisfied_stages(patient_record)
        unless ruby_matchers?
          raise ArgumentError, "satisfied_stages is only available for :ruby_matchers definitions"
        end

        stage_keys.each_with_object({}) do |key, acc|
          acc[key] = matchers.fetch(key).call(patient_record)
        end
      end

      # ---- Built-in definitions --------------------------------------------

      def self.builtins
        { syphilis: syphilis, hcv: hcv }
      end

      def self.builtin(key)
        builtins.fetch(key.to_sym) do
          raise UnknownConditionError, "no built-in cascade definition for #{key.inspect}"
        end
      end

      # Syphilis: RPR/treponemal screen -> treponemal confirmation ->
      # active infection -> benzathine penicillin G treatment.
      #
      # Codes are a documented starter set (LOINC / ICD-10-CM / SNOMED /
      # RxNorm). Hosts can override by constructing their own definition.
      def self.syphilis
        code_sets = {
          screening: %w[20507-0 11084-1 5292-8 22587-0], # RPR / reagin / treponemal Ab (LOINC)
          confirmation: %w[8041-9 24312-8 47237-7],      # TP-PA / FTA-ABS (LOINC)
          active_condition: %w[A51 A51.0 A52 A53 A53.9 76272004], # ICD-10-CM / SNOMED
          treatment: %w[7982 1596450 1659149]            # penicillin G benzathine (RxNorm)
        }
        from_code_sets(key: :syphilis, name: "Syphilis", code_sets: code_sets)
      end

      # Hepatitis C: HCV Ab screen -> HCV RNA confirmation -> active
      # (detectable RNA / chronic HCV) -> direct-acting antiviral treatment ->
      # cure (SVR12: undetectable RNA after treatment).
      def self.hcv
        code_sets = {
          screening: %w[13955-0 16128-1 5199-5],          # HCV antibody (LOINC)
          confirmation: %w[11259-9 20416-4 38180-6],      # HCV RNA (LOINC)
          active_condition: %w[B18.2 B17.10 B17.11 50711007], # chronic/acute HCV (ICD-10-CM / SNOMED)
          treatment: %w[1734340 1926906 2003754],         # DAA regimens (RxNorm)
          completion: %w[11259-9 20416-4 38180-6]         # SVR12 = undetectable RNA (same RNA assays)
        }
        from_code_sets(key: :hcv, name: "Hepatitis C", code_sets: code_sets)
      end

      # Build the standard six-stage screening-to-treatment cascade from code
      # sets. Stage membership predicates:
      #
      #   screened               screening assay performed (any result)
      #   reactive               screening assay positive/reactive
      #   confirmation_completed confirmatory assay performed (any result)
      #   active_infection       confirmatory positive OR active Condition
      #   treatment_initiated    treatment medication (or procedure) recorded
      #   treatment_completed    cure marker (negative confirmatory assay
      #                          post-treatment) — omitted if no code set given
      def self.from_code_sets(key:, name:, code_sets:)
        screening    = code_sets.fetch(:screening)
        confirmation = code_sets.fetch(:confirmation)
        active       = code_sets.fetch(:active_condition)
        treatment    = code_sets.fetch(:treatment)
        completion   = code_sets[:completion]

        stages = [
          Stage.new(key: :screened, label: "Screened", ordinal: 0, actionable: false),
          Stage.new(key: :reactive, label: "Reactive", ordinal: 1, actionable: true),
          Stage.new(key: :confirmation_completed, label: "Confirmation completed", ordinal: 2, actionable: false),
          Stage.new(key: :active_infection, label: "Active infection", ordinal: 3, actionable: true),
          Stage.new(key: :treatment_initiated, label: "Treatment initiated", ordinal: 4, actionable: true),
          Stage.new(key: :treatment_completed, label: "Treatment completed", ordinal: 5, actionable: false)
        ]

        matchers = {
          screened: ->(pr) { pr.observation_present?(screening) },
          reactive: ->(pr) { pr.positive_observation?(screening) },
          confirmation_completed: ->(pr) { pr.observation_present?(confirmation) },
          active_infection: ->(pr) { pr.positive_observation?(confirmation) || pr.condition_present?(active) },
          treatment_initiated: ->(pr) { pr.medication_present?(treatment) || pr.procedure_present?(treatment) },
          treatment_completed: completion_matcher(treatment, completion)
        }

        new(key: key, name: name, stages: stages, matchers: matchers, code_sets: code_sets)
      end

      # Cure is only credited to patients who were actually treated, evidenced
      # by a subsequent negative confirmatory assay (e.g. HCV SVR12). Without a
      # completion code set the terminal stage is never reached.
      def self.completion_matcher(treatment, completion)
        return ->(_pr) { false } if completion.nil? || completion.empty?

        lambda do |pr|
          treated = pr.medication_present?(treatment) || pr.procedure_present?(treatment)
          treated && pr.negative_observation?(completion)
        end
      end

      private

      def validate!
        raise ArgumentError, "stages cannot be empty" if stages.empty?
        return unless ruby_matchers?

        missing = stage_keys - matchers.keys
        raise ArgumentError, "missing matchers for stages: #{missing.inspect}" if missing.any?
      end
    end
  end
end
