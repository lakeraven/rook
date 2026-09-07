# frozen_string_literal: true

require "test_helper"

module Rook
  module Ports
    module SupplementalData
      class BaseTest < Minitest::Test
        def setup
          @reader = Base.new
        end

        def test_source_descriptor_raises_not_implemented
          assert_raises(NotImplementedError) { @reader.source_descriptor }
        end

        def test_patient_attributes_raises_not_implemented
          assert_raises(NotImplementedError) { @reader.patient_attributes([ "1" ]) }
        end

        def test_visit_attributes_raises_not_implemented
          assert_raises(NotImplementedError) { @reader.visit_attributes([ "1" ]) }
        end

        def test_patient_coverages_raises_not_implemented
          assert_raises(NotImplementedError) { @reader.patient_coverages([ "1" ]) }
        end
      end

      # The Mock proves itself against the port's conformance suite — the
      # same way an integrations-layer reader does: implement build_reader +
      # the arrange hooks, inherit every test_conformance_* method.
      class MockConformanceTest < Minitest::Test
        include Conformance

        def build_reader
          Mock.new(source_descriptor: Rook::SourceDescriptor.new(
            id: "site-a", platform: :rpms, channel: :supplemental))
        end

        def arrange_patient_attribute(reader, patient_id, attribute, value, effective: nil)
          reader.seed_patient_attribute(patient_id, attribute, value, effective: effective)
        end

        def arrange_visit_attribute(reader, patient_id, encounter_id, attribute, value, effective: nil)
          reader.seed_visit_attribute(patient_id, encounter_id, attribute, value, effective: effective)
        end

        def arrange_patient_coverage(reader, patient_id, payer_category, effective: nil, ends: nil, status: "active")
          reader.seed_patient_coverage(patient_id, payer_category, effective: effective, ends: ends, status: status)
        end
      end

      # Mock-specific behavior beyond the port contract: seed validation and
      # store isolation.
      class MockTest < Minitest::Test
        def setup
          @descriptor = Rook::SourceDescriptor.new(id: "site-a", platform: :rpms, channel: :supplemental)
          @mock = Mock.new(source_descriptor: @descriptor)
        end

        def test_default_descriptor_is_supplemental
          descriptor = Mock.new.source_descriptor

          assert_instance_of Rook::SourceDescriptor, descriptor
          assert descriptor.supplemental?
        end

        def test_exposes_configured_source_descriptor
          assert_equal @descriptor, @mock.source_descriptor
        end

        def test_seed_rejects_unknown_attribute
          assert_raises(ArgumentError) { @mock.seed_patient_attribute("1", "shoe-size", "11") }
        end

        def test_seed_rejects_attribute_at_wrong_level
          assert_raises(ArgumentError) { @mock.seed_patient_attribute("1", "visit-service-category", "medical") }
          assert_raises(ArgumentError) { @mock.seed_visit_attribute("1", "enc-1", "veteran-status", "veteran") }
        end

        def test_seed_rejects_value_outside_enumeration
          error = assert_raises(ArgumentError) { @mock.seed_patient_attribute("1", "housing-status", "condo") }
          assert_match(/housing-status value must be one of/, error.message)

          assert_raises(ArgumentError) { @mock.seed_patient_attribute("1", "veteran-status", true) }
          assert_raises(ArgumentError) { @mock.seed_visit_attribute("1", "enc-1", "visit-service-category", "spa") }
        end

        def test_seed_rejects_mistyped_percent_value
          error = assert_raises(ArgumentError) { @mock.seed_patient_attribute("1", "income-percent-fpl", "138") }
          assert_match(/must be finite Numeric/, error.message)
        end

        def test_seed_rejects_non_finite_percent_value
          assert_raises(ArgumentError) { @mock.seed_patient_attribute("1", "income-percent-fpl", Float::NAN) }
          assert_raises(ArgumentError) { @mock.seed_patient_attribute("1", "income-percent-fpl", Float::INFINITY) }
          assert_raises(ArgumentError) { @mock.seed_patient_attribute("1", "income-percent-fpl", -Float::INFINITY) }
        end

        def test_coverage_rejects_unknown_payer_category
          assert_raises(ArgumentError) { @mock.seed_patient_coverage("1", "gold-plan") }
        end

        def test_returned_resources_are_copies_of_the_store
          @mock.seed_patient_attribute("1", "veteran-status", "veteran")

          @mock.patient_attributes([ "1" ]).first.subject.reference = "Patient/corrupted"

          assert_equal "Patient/1", @mock.patient_attributes([ "1" ]).first.subject.reference
        end

        def test_coverage_returns_copies
          @mock.seed_patient_coverage("1", "private")

          @mock.patient_coverages([ "1" ]).first.beneficiary.reference = "Patient/corrupted"

          assert_equal "Patient/1", @mock.patient_coverages([ "1" ]).first.beneficiary.reference
        end

        def test_unparseable_effective_date_fails_closed
          observation = @mock.seed_patient_attribute("1", "veteran-status", "veteran")
          observation.effectiveDateTime = "2026-02-30"

          error = assert_raises(ArgumentError) { @mock.patient_attributes([ "1" ]) }
          assert_match(/2026-02-30/, error.message)
        end
      end
    end
  end
end
