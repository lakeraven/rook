# frozen_string_literal: true

require "rook/care_cascade/patient_record"
require "rook/care_cascade/condition_definition"
require "rook/care_cascade/report"

module Rook
  module CareCascade
    # Computes the screening-to-treatment care cascade for one condition over a
    # cohort of patients, with drop-off worklists and disaggregation by site and
    # AI/AN status.
    #
    # EHR-agnostic: patients are supplied as FHIR-shaped record hashes (see
    # PatientRecord) either directly or via a zero-arg adapter callable.
    #
    #   service = Rook::CareCascade::CascadeService.new(
    #     definition: Rook::CareCascade::ConditionDefinition.builtin(:syphilis),
    #     patients:   ->() { fhir_adapter.street_medicine_cohort }
    #   )
    #   report = service.report
    #   report.worklists            # re-engagement queues for outreach
    #   report.to_grant_report(...) # funder-shaped outcomes output
    #
    # === CQL engine seam (rook#1)
    # If the definition declares +source: :cql+, this service raises
    # CqlEngineNotAvailableError. Rook's CQL execution engine has not been
    # selected yet (rook#1); rather than fabricate results we fail loudly so the
    # caller uses a :ruby_matchers definition until the engine lands.
    class CascadeService
      class CqlEngineNotAvailableError < Rook::Error; end

      def initialize(definition:, patients:)
        @definition = definition
        @patients = patients
      end

      def report
        unless @definition.ruby_matchers?
          raise CqlEngineNotAvailableError,
            "condition #{@definition.key.inspect} uses source #{@definition.source.inspect}; " \
            "Rook's CQL execution engine is not yet selected (rook#1). " \
            "Use a :ruby_matchers definition until it lands."
        end

        Report.compute(definition: @definition, patient_records: patient_records)
      end

      private

      def patient_records
        raw = @patients.respond_to?(:call) ? @patients.call : @patients
        Array(raw).map { |r| PatientRecord.wrap(r) }
      end
    end
  end
end
