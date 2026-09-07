# frozen_string_literal: true

require "rook/ports/immunization_registry/base"
require "rook/ports/immunization_registry/mock"

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

      def initialize
        @immunization_registry = nil
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
    end
  end
end
