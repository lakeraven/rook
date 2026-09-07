# frozen_string_literal: true

require "rook/ports/immunization_registry/base"
require "rook/ports/immunization_registry/mock"
require "rook/ports/supplemental_data/base"
require "rook/ports/supplemental_data/mock"
require "rook/ports/supplemental_data/conformance"

module Rook
  # Rook::Ports is the interface-contract layer between Rook services and
  # concrete backend implementations.
  #
  # Services depend only on the port interfaces (FHIR-native: inputs and
  # outputs are fhir_models FHIR R4 resources). Concrete adapters wrap the
  # actual backends and are wired into the slots at boot time via
  # Rook::Ports.configure. The contract shape mirrors the org-wide gateway
  # conventions so these ports are extraction-ready.
  module Ports
    class Configuration
      attr_accessor :immunization_registry
      attr_reader :supplemental_data_readers

      def initialize
        @immunization_registry = nil
        @supplemental_data_readers = [].freeze
      end

      # Register the deployment's supplemental-data readers (one per
      # supplemental source — see Rook::Ports::SupplementalData::Base).
      # Validated at registration so misconfiguration surfaces at boot, not
      # in report output:
      # - every reader's descriptor must be supplemental-channel — a
      #   primary_fhir reader registered here would stamp supplemental
      #   records with primary-feed lineage;
      # - descriptor ids must be unique — the id is the provenance key
      #   persisted in meta.source, so duplicates would be
      #   indistinguishable in audit evidence.
      def supplemental_data_readers=(readers)
        readers = Array(readers)

        non_supplemental = readers.reject { |r| r.source_descriptor.supplemental? }
        unless non_supplemental.empty?
          details = non_supplemental.map { |r| "#{r.source_descriptor.id} (#{r.source_descriptor.channel})" }
          raise ArgumentError,
            "supplemental_data_readers must carry supplemental-channel descriptors; got #{details.join(', ')}"
        end

        duplicate_ids = readers.map { |r| r.source_descriptor.id }.tally.select { |_, count| count > 1 }.keys
        unless duplicate_ids.empty?
          raise ArgumentError, "duplicate supplemental source ids: #{duplicate_ids.join(', ')}"
        end

        @supplemental_data_readers = readers.freeze
      end
    end

    class << self
      def configuration
        @configuration ||= Configuration.new
      end

      def configure
        yield(configuration)
      end

      def reset_configuration!
        @configuration = Configuration.new
      end

      def immunization_registry
        configuration.immunization_registry
      end

      def supplemental_data_readers
        configuration.supplemental_data_readers
      end
    end
  end
end
