# frozen_string_literal: true

require "test_helper"

module Rook
  module Ports
    module SupplementalData
      class ConfigurationTest < Minitest::Test
        def teardown
          Rook::Ports.reset_configuration!
        end

        def supplemental_mock(id, platform: :rpms, channel: :supplemental)
          Mock.new(source_descriptor: Rook::SourceDescriptor.new(id: id, platform: platform, channel: channel))
        end

        def test_defaults_to_empty_array
          assert_equal [], Rook::Ports.supplemental_data_readers
        end

        def test_configure_registers_multiple_readers
          site_a = supplemental_mock("site-a")
          site_b = supplemental_mock("site-b", platform: :epic)

          Rook::Ports.configure do |config|
            config.supplemental_data_readers = [ site_a, site_b ]
          end

          assert_equal [ site_a, site_b ], Rook::Ports.supplemental_data_readers
          assert Rook::Ports.supplemental_data_readers.all? { |r| r.source_descriptor.supplemental? }
        end

        def test_rejects_primary_fhir_descriptor_in_supplemental_slot
          # A primary_fhir reader registered here would stamp supplemental
          # records with primary-feed lineage.
          primary = supplemental_mock("site-a", channel: :primary_fhir)

          error = assert_raises(ArgumentError) do
            Rook::Ports.configure { |c| c.supplemental_data_readers = [ primary ] }
          end
          assert_match(/supplemental-channel/, error.message)
          assert_match(/site-a \(primary_fhir\)/, error.message)
        end

        def test_rejects_duplicate_source_ids_at_registration
          error = assert_raises(ArgumentError) do
            Rook::Ports.configure do |config|
              config.supplemental_data_readers = [ supplemental_mock("site-a"), supplemental_mock("site-a") ]
            end
          end
          assert_match(/duplicate supplemental source ids: site-a/, error.message)
        end

        def test_registered_readers_cannot_be_mutated_outside_configure
          Rook::Ports.configure { |c| c.supplemental_data_readers = [ Mock.new ] }

          readers = Rook::Ports.supplemental_data_readers
          assert readers.frozen?
          assert_raises(FrozenError) { readers << Mock.new }
          assert_equal 1, Rook::Ports.supplemental_data_readers.length
        end

        def test_reset_configuration_clears_readers
          Rook::Ports.configure { |c| c.supplemental_data_readers = [ Mock.new ] }
          Rook::Ports.reset_configuration!

          assert_equal [], Rook::Ports.supplemental_data_readers
        end
      end
    end
  end
end
