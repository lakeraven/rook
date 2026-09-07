# frozen_string_literal: true

require "test_helper"

module Rook
  module Ports
    module SupplementalData
      class AttributesTest < Minitest::Test
        def test_code_system_uri
          assert_equal "https://terminology.lakeraven.com/CodeSystem/uds-supplemental-attribute",
                       Attributes::CODE_SYSTEM
        end

        def test_value_system_uri
          assert_equal "https://terminology.lakeraven.com/CodeSystem/uds-supplemental-value",
                       Attributes::VALUE_SYSTEM
        end

        def test_attribute_vocabulary
          expected = %w[
            income-percent-fpl sliding-fee-class housing-status
            agricultural-worker-status veteran-status language-barrier
            visit-service-category
          ]
          assert_equal expected, Attributes::ALL
        end

        def test_payer_category_is_not_an_attribute
          refute_includes Attributes::ALL, "payer-category"
          refute_includes Attributes::ALL, "payer_category"
        end

        def test_patient_level_attributes
          expected = %w[
            income-percent-fpl sliding-fee-class housing-status
            agricultural-worker-status veteran-status language-barrier
          ]
          assert_equal expected, Attributes::PATIENT_LEVEL
        end

        def test_visit_level_attributes
          assert_equal %w[visit-service-category], Attributes::VISIT_LEVEL
        end

        def test_every_attribute_has_level_and_value_kind
          Attributes::DEFINITIONS.each do |code, definition|
            assert_includes %i[patient visit], definition[:level], "#{code} level"
            assert_includes %i[percent coded], definition[:value], "#{code} value kind"
          end
        end

        def test_coded_attributes_enumerate_their_values
          Attributes::DEFINITIONS.each do |code, definition|
            next unless definition[:value] == :coded

            values = definition[:values]
            refute_nil values, "#{code} values"
            refute_empty values, "#{code} values"
            values.each { |v| assert_match(/\A[a-z][a-z0-9-]*\z/, v, "#{code} value #{v}") }
          end
        end

        def test_value_enumerations
          assert_equal %w[class-a class-b class-c class-d class-e],
                       Attributes::DEFINITIONS["sliding-fee-class"][:values]
          # UDS Table 4 shelter categories need transitional and other.
          assert_equal %w[housed homeless-shelter doubling-up unsheltered transitional
                          permanent-supportive other unknown],
                       Attributes::DEFINITIONS["housing-status"][:values]
          assert_equal %w[migratory seasonal none],
                       Attributes::DEFINITIONS["agricultural-worker-status"][:values]
          assert_equal %w[veteran non-veteran],
                       Attributes::DEFINITIONS["veteran-status"][:values]
          assert_equal %w[best-served-other-language english-proficient],
                       Attributes::DEFINITIONS["language-barrier"][:values]
          # Mental health and substance use are distinct — UDS Table 5
          # lines 20/21 must be distinguishable.
          assert_equal %w[medical dental mental-health substance-use vision enabling other],
                       Attributes::DEFINITIONS["visit-service-category"][:values]
        end

        def test_income_percent_fpl_is_a_quantity
          assert_equal :percent, Attributes::DEFINITIONS["income-percent-fpl"][:value]
        end
      end

      class PayerCategoryTest < Minitest::Test
        def test_code_system_uri
          assert_equal "https://terminology.lakeraven.com/CodeSystem/uds-payer-category",
                       PayerCategory::CODE_SYSTEM
        end

        def test_category_vocabulary
          assert_equal %w[medicaid medicare private uninsured other-public], PayerCategory::ALL
        end
      end
    end
  end
end
