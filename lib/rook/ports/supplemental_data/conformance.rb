# frozen_string_literal: true

require "date"

require "rook/ports/supplemental_data/base"

module Rook
  module Ports
    module SupplementalData
      # Conformance test suite for SupplementalData::Base implementations.
      #
      # Rook owns the port; per-EHR readers live in the integrations layer
      # and run this suite against themselves to prove they honor the
      # contract — the normalized FHIR shapes, the Attributes/PayerCategory
      # vocabularies, source provenance, and the temporal semantics
      # (as-of-period-end, undated-beats-dated, latest-wins per payer
      # category).
      #
      # Include into a Minitest::Test and implement the four hooks; every
      # +test_conformance_*+ method then runs against your reader:
      #
      #   class MyReaderConformanceTest < Minitest::Test
      #     include Rook::Ports::SupplementalData::Conformance
      #
      #     # A fresh reader with an empty backing dataset per test.
      #     def build_reader = MyReader.new(...)
      #
      #     # Arrange hooks: load one record into the reader's backing data
      #     # store (for the Mock these delegate to its seed_* methods; a
      #     # concrete adapter loads its backend fixture instead).
      #     def arrange_patient_attribute(reader, patient_id, attribute, value, effective: nil) = ...
      #     def arrange_visit_attribute(reader, patient_id, encounter_id, attribute, value, effective: nil) = ...
      #     def arrange_patient_coverage(reader, patient_id, payer_category, effective: nil, ends: nil,
      #                                  status: "active") = ...
      #   end
      #
      # Typing contract (architecture review, 2026-09-07): reads return raw
      # fhir_models resources — FHIR::Observation / FHIR::Coverage — never
      # decorator or source-system types; the suite asserts the FHIR::Model
      # kinds directly.
      module Conformance
        PERIOD_2026 = Date.new(2026, 1, 1)..Date.new(2026, 12, 31)

        # The reader under test, built once per test via the build_reader hook.
        def reader
          @conformance_reader ||= build_reader
        end

        # -- Descriptor and provenance --

        def test_conformance_source_descriptor_is_supplemental
          descriptor = reader.source_descriptor

          assert_kind_of Rook::SourceDescriptor, descriptor
          assert descriptor.supplemental?,
                 "a supplemental reader must carry a supplemental-channel descriptor"
        end

        def test_conformance_tags_meta_source_from_descriptor
          arrange_patient_attribute(reader, "1", "veteran-status", "non-veteran")
          arrange_visit_attribute(reader, "1", "enc-1", "visit-service-category", "medical")
          arrange_patient_coverage(reader, "1", "other-public")

          resources = reader.patient_attributes([ "1" ]) +
                      reader.visit_attributes([ "1" ]) +
                      reader.patient_coverages([ "1" ])

          refute_empty resources
          resources.each do |resource|
            assert_equal reader.source_descriptor.uri, resource.meta&.source,
                         "#{resource.class} must carry meta.source provenance"
          end
        end

        # -- Normalized FHIR shapes --

        def test_conformance_patient_attribute_normalizes_to_coded_observation
          arrange_patient_attribute(reader, "1", "housing-status", "homeless-shelter")

          observation = reader.patient_attributes([ "1" ]).first

          assert_kind_of FHIR::Observation, observation
          coding = observation.code.coding.first
          assert_equal Attributes::CODE_SYSTEM, coding.system
          assert_equal "housing-status", coding.code
          assert_equal "Patient/1", observation.subject.reference
          value_coding = observation.valueCodeableConcept.coding.first
          assert_equal Attributes::VALUE_SYSTEM, value_coding.system
          assert_equal "homeless-shelter", value_coding.code
          assert_nil observation.encounter
        end

        def test_conformance_percent_attribute_uses_ucum_value_quantity
          arrange_patient_attribute(reader, "1", "income-percent-fpl", 138)

          observation = reader.patient_attributes([ "1" ]).first

          assert_kind_of FHIR::Observation, observation
          # Whole-percent semantics: 138 = 138% FPL.
          assert_equal 138, observation.valueQuantity.value
          assert_equal "%", observation.valueQuantity.unit
          assert_equal "http://unitsofmeasure.org", observation.valueQuantity.system
          assert_equal "%", observation.valueQuantity.code
        end

        def test_conformance_coded_attribute_uses_value_codeable_concept
          arrange_patient_attribute(reader, "1", "veteran-status", "veteran")

          observation = reader.patient_attributes([ "1" ]).first

          assert_nil observation.valueBoolean
          assert_nil observation.valueString
          assert_equal "veteran", observation.valueCodeableConcept.coding.first.code
        end

        def test_conformance_visit_attribute_carries_encounter_reference
          arrange_visit_attribute(reader, "1", "enc-9", "visit-service-category", "dental",
                                  effective: Date.new(2026, 3, 5))

          observation = reader.visit_attributes([ "1" ]).first

          assert_kind_of FHIR::Observation, observation
          assert_equal "Encounter/enc-9", observation.encounter.reference
          assert_equal "visit-service-category", observation.code.coding.first.code
          assert_equal "dental", observation.valueCodeableConcept.coding.first.code
        end

        # -- Reads --

        def test_conformance_reads_cohort_across_patients
          arrange_patient_attribute(reader, "1", "sliding-fee-class", "class-a")
          arrange_patient_attribute(reader, "2", "sliding-fee-class", "class-b")

          results = reader.patient_attributes(%w[1 2])

          assert_equal %w[Patient/1 Patient/2], results.map { |o| o.subject.reference }.sort
        end

        def test_conformance_accepts_single_patient_id
          arrange_patient_attribute(reader, "1", "language-barrier", "best-served-other-language")

          assert_equal 1, reader.patient_attributes("1").length
        end

        def test_conformance_returns_empty_for_unknown_patient
          assert_equal [], reader.patient_attributes([ "999" ])
        end

        # -- Attribute filter --

        def test_conformance_filters_to_requested_attributes
          arrange_patient_attribute(reader, "1", "veteran-status", "veteran")
          arrange_patient_attribute(reader, "1", "housing-status", "housed")
          arrange_patient_attribute(reader, "1", "income-percent-fpl", 90)

          results = reader.patient_attributes([ "1" ], attributes: %w[veteran-status income-percent-fpl])

          assert_equal %w[income-percent-fpl veteran-status],
                       results.map { |o| o.code.coding.first.code }.sort
        end

        def test_conformance_attribute_filter_defaults_to_all
          arrange_patient_attribute(reader, "1", "veteran-status", "veteran")
          arrange_patient_attribute(reader, "1", "housing-status", "housed")

          assert_equal 2, reader.patient_attributes([ "1" ]).length
        end

        def test_conformance_attribute_filter_rejects_unknown_codes
          assert_raises(ArgumentError) { reader.patient_attributes([ "1" ], attributes: %w[shoe-size]) }
          # Visit-level code is unknown at patient level and vice versa.
          assert_raises(ArgumentError) { reader.patient_attributes([ "1" ], attributes: %w[visit-service-category]) }
          assert_raises(ArgumentError) { reader.visit_attributes([ "1" ], attributes: %w[veteran-status]) }
        end

        # -- Period semantics: current as of period end, latest-wins --

        def test_conformance_patient_read_returns_latest_value_as_of_period_end
          arrange_patient_attribute(reader, "1", "sliding-fee-class", "class-a", effective: Date.new(2025, 2, 1))
          arrange_patient_attribute(reader, "1", "sliding-fee-class", "class-b", effective: Date.new(2026, 2, 1))
          arrange_patient_attribute(reader, "1", "sliding-fee-class", "class-c", effective: Date.new(2027, 2, 1))

          results = reader.patient_attributes([ "1" ], period: PERIOD_2026)

          # One value per attribute per patient: the latest effective on or
          # before period end — not values dated within the period.
          assert_equal [ "class-b" ], results.map { |o| o.valueCodeableConcept.coding.first.code }
        end

        def test_conformance_value_predating_period_is_still_current_as_of_period_end
          arrange_patient_attribute(reader, "1", "sliding-fee-class", "class-a", effective: Date.new(2024, 6, 1))

          results = reader.patient_attributes([ "1" ], period: PERIOD_2026)

          assert_equal [ "class-a" ], results.map { |o| o.valueCodeableConcept.coding.first.code }
        end

        def test_conformance_period_end_is_inclusive
          arrange_patient_attribute(reader, "1", "sliding-fee-class", "class-a", effective: Date.new(2025, 6, 1))
          arrange_patient_attribute(reader, "1", "sliding-fee-class", "class-b", effective: Date.new(2026, 12, 31))

          results = reader.patient_attributes([ "1" ], period: PERIOD_2026)

          assert_equal [ "class-b" ], results.map { |o| o.valueCodeableConcept.coding.first.code }
        end

        def test_conformance_value_after_period_end_is_excluded
          arrange_patient_attribute(reader, "1", "sliding-fee-class", "class-b", effective: Date.new(2027, 1, 1))

          assert_equal [], reader.patient_attributes([ "1" ], period: PERIOD_2026)
        end

        def test_conformance_latest_wins_is_per_attribute_and_per_patient
          arrange_patient_attribute(reader, "1", "sliding-fee-class", "class-a", effective: Date.new(2025, 1, 1))
          arrange_patient_attribute(reader, "1", "sliding-fee-class", "class-b", effective: Date.new(2026, 1, 1))
          arrange_patient_attribute(reader, "1", "housing-status", "housed", effective: Date.new(2025, 1, 1))
          arrange_patient_attribute(reader, "2", "sliding-fee-class", "class-c", effective: Date.new(2025, 1, 1))

          results = reader.patient_attributes(%w[1 2], period: PERIOD_2026)

          summary = results.map do |o|
            [ o.subject.reference, o.code.coding.first.code, o.valueCodeableConcept.coding.first.code ]
          end
          assert_includes summary, [ "Patient/1", "sliding-fee-class", "class-b" ]
          assert_includes summary, [ "Patient/1", "housing-status", "housed" ]
          assert_includes summary, [ "Patient/2", "sliding-fee-class", "class-c" ]
          assert_equal 3, results.length
        end

        def test_conformance_undated_attributes_are_currently_effective
          arrange_patient_attribute(reader, "1", "agricultural-worker-status", "seasonal")

          results = reader.patient_attributes([ "1" ], period: PERIOD_2026)

          assert_equal [ "seasonal" ], results.map { |o| o.valueCodeableConcept.coding.first.code }
        end

        def test_conformance_undated_value_beats_all_dated_values
          # Undated = the registration-current value; it wins over any dated
          # history regardless of arrange order.
          arrange_patient_attribute(reader, "1", "housing-status", "homeless-shelter", effective: Date.new(2020, 5, 1))
          arrange_patient_attribute(reader, "1", "housing-status", "housed")
          arrange_patient_attribute(reader, "1", "housing-status", "doubling-up", effective: Date.new(2026, 3, 1))

          results = reader.patient_attributes([ "1" ], period: PERIOD_2026)

          assert_equal [ "housed" ], results.map { |o| o.valueCodeableConcept.coding.first.code }
        end

        def test_conformance_nil_period_excludes_future_dated_values
          # period: nil = "current now": nothing dated later than today
          # supersedes — or even matches. Dates are relative to today so the
          # test never crosses the boundary.
          arrange_patient_attribute(reader, "1", "sliding-fee-class", "class-a", effective: Date.today - 30)
          arrange_patient_attribute(reader, "1", "sliding-fee-class", "class-b", effective: Date.today + 30)
          arrange_patient_attribute(reader, "2", "sliding-fee-class", "class-c", effective: Date.today + 30)

          results = reader.patient_attributes(%w[1 2])

          # The future value neither supersedes patient 1's current value nor
          # appears at all for patient 2.
          assert_equal [ [ "Patient/1", "class-a" ] ],
                       results.map { |o| [ o.subject.reference, o.valueCodeableConcept.coding.first.code ] }
        end

        def test_conformance_visit_attributes_select_visits_within_period_inclusive
          arrange_visit_attribute(reader, "1", "enc-1", "visit-service-category", "medical",
                                  effective: Date.new(2025, 12, 31))
          arrange_visit_attribute(reader, "1", "enc-2", "visit-service-category", "dental",
                                  effective: Date.new(2026, 1, 1))
          arrange_visit_attribute(reader, "1", "enc-3", "visit-service-category", "vision",
                                  effective: Date.new(2026, 12, 31))
          arrange_visit_attribute(reader, "1", "enc-4", "visit-service-category", "other",
                                  effective: Date.new(2027, 1, 1))

          results = reader.visit_attributes([ "1" ], period: PERIOD_2026)

          assert_equal %w[Encounter/enc-2 Encounter/enc-3], results.map { |o| o.encounter.reference }.sort
        end

        # -- Payer-category coverage --

        def test_conformance_coverage_normalizes_to_typed_fhir_coverage
          arrange_patient_coverage(reader, "1", "medicaid")

          coverage = reader.patient_coverages([ "1" ]).first

          assert_kind_of FHIR::Coverage, coverage
          coding = coverage.type.coding.first
          assert_equal PayerCategory::CODE_SYSTEM, coding.system
          assert_equal "medicaid", coding.code
          assert_equal "Patient/1", coverage.beneficiary.reference
          assert_equal "active", coverage.status
          # R4 requires Coverage.payor (1..*).
          refute_empty Array(coverage.payor)
          assert_equal reader.source_descriptor.uri, coverage.meta.source
        end

        def test_conformance_coverage_latest_wins_per_payer_category_as_of_period_end
          # Superseded medicaid record loses to the newer one; future-dated
          # medicare does not match — but temporal selection is per
          # (beneficiary, payer category), never a collapse to one coverage
          # per patient.
          arrange_patient_coverage(reader, "1", "medicaid", effective: Date.new(2025, 1, 1))
          arrange_patient_coverage(reader, "1", "medicaid", effective: Date.new(2026, 6, 1))
          arrange_patient_coverage(reader, "1", "medicare", effective: Date.new(2027, 1, 1))

          results = reader.patient_coverages([ "1" ], period: PERIOD_2026)

          assert_equal [ "medicaid" ], results.map { |c| c.type.coding.first.code }
          assert_equal [ "2026-06-01" ], results.map { |c| c.period.start }
        end

        def test_conformance_dual_eligible_returns_medicare_and_medicaid_simultaneously
          # UDS Table 4 line 9a: dual-eligibles carry BOTH coverages.
          arrange_patient_coverage(reader, "1", "medicare", effective: Date.new(2025, 3, 1))
          arrange_patient_coverage(reader, "1", "medicaid", effective: Date.new(2026, 2, 1))

          results = reader.patient_coverages([ "1" ], period: PERIOD_2026)

          assert_equal %w[medicaid medicare], results.map { |c| c.type.coding.first.code }.sort
        end

        def test_conformance_expired_coverage_is_excluded
          # Coverage with an end before the as-of date (period end) is
          # terminated: current means start <= as-of <= end.
          arrange_patient_coverage(reader, "1", "private",
                                   effective: Date.new(2026, 1, 1), ends: Date.new(2026, 6, 30))

          assert_equal [], reader.patient_coverages([ "1" ], period: PERIOD_2026)
        end

        def test_conformance_coverage_end_is_inclusive
          arrange_patient_coverage(reader, "1", "private",
                                   effective: Date.new(2026, 1, 1), ends: Date.new(2026, 12, 31))

          results = reader.patient_coverages([ "1" ], period: PERIOD_2026)

          assert_equal [ "private" ], results.map { |c| c.type.coding.first.code }
        end

        def test_conformance_open_ended_coverage_is_included
          arrange_patient_coverage(reader, "1", "medicaid", effective: Date.new(2020, 1, 1))

          results = reader.patient_coverages([ "1" ], period: PERIOD_2026)

          assert_equal [ "medicaid" ], results.map { |c| c.type.coding.first.code }
        end

        def test_conformance_non_active_coverage_is_excluded
          arrange_patient_coverage(reader, "1", "private", effective: Date.new(2026, 1, 1), status: "cancelled")

          assert_equal [], reader.patient_coverages([ "1" ], period: PERIOD_2026)
        end
      end
    end
  end
end
