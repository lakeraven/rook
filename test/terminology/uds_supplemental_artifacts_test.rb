# frozen_string_literal: true

require "test_helper"
require "json"

# The UDS supplemental vocabulary ships twice: as Ruby constants
# (Rook::Ports::SupplementalData::Attributes / PayerCategory — what readers
# validate against) and as FHIR terminology artifacts under
# lib/rook/terminology/ (what a terminology server hosts). This suite pins
# the two representations to each other so neither can drift.
class UdsSupplementalArtifactsTest < Minitest::Test
  Attributes = Rook::Ports::SupplementalData::Attributes
  PayerCategory = Rook::Ports::SupplementalData::PayerCategory

  ARTIFACTS_DIR = File.expand_path("../../lib/rook/terminology/uds-supplemental", __dir__)

  def artifact(name)
    JSON.parse(File.read(File.join(ARTIFACTS_DIR, "#{name}.json")))
  end

  def test_every_artifact_parses_as_a_fhir_resource
    Dir[File.join(ARTIFACTS_DIR, "*.json")].sort.each do |path|
      resource = FHIR.from_contents(File.read(path))

      assert_kind_of FHIR::Model, resource, path
      assert_includes [ FHIR::CodeSystem, FHIR::ValueSet ], resource.class, path
      assert_equal File.basename(path, ".json").split("-", 2).last, resource.id, path
    end
  end

  def test_attribute_code_system_matches_ruby_vocabulary
    code_system = artifact("CodeSystem-uds-supplemental-attribute")

    assert_equal Attributes::CODE_SYSTEM, code_system["url"]
    assert_equal "complete", code_system["content"]
    assert_equal Attributes::ALL, code_system["concept"].map { |c| c["code"] }
  end

  def test_attribute_code_system_levels_match_definitions
    code_system = artifact("CodeSystem-uds-supplemental-attribute")

    code_system["concept"].each do |concept|
      properties = concept["property"].to_h { |p| [ p["code"], p["valueCode"] ] }
      definition = Attributes::DEFINITIONS.fetch(concept["code"])

      assert_equal definition[:level].to_s, properties["level"], concept["code"]
      assert_equal definition[:value].to_s, properties["value-kind"], concept["code"]
    end
  end

  def test_value_code_system_is_the_union_of_coded_enumerations
    code_system = artifact("CodeSystem-uds-supplemental-value")

    expected = Attributes::DEFINITIONS.values
                                      .filter_map { |d| d[:values] }
                                      .flatten.uniq
    assert_equal Attributes::VALUE_SYSTEM, code_system["url"]
    assert_equal expected.sort, code_system["concept"].map { |c| c["code"] }.sort
  end

  def test_each_coded_attribute_has_a_matching_value_set
    Attributes::DEFINITIONS.each do |attribute, definition|
      next unless definition[:value] == :coded

      value_set = artifact("ValueSet-uds-supplemental-#{attribute}")
      include_block = value_set["compose"]["include"].first

      assert_equal "https://terminology.lakeraven.com/ValueSet/uds-supplemental-#{attribute}",
                   value_set["url"]
      assert_equal Attributes::VALUE_SYSTEM, include_block["system"]
      assert_equal definition[:values], include_block["concept"].map { |c| c["code"] }
    end
  end

  def test_percent_attributes_have_no_value_set
    Attributes::DEFINITIONS.each do |attribute, definition|
      next unless definition[:value] == :percent

      refute File.exist?(File.join(ARTIFACTS_DIR, "ValueSet-uds-supplemental-#{attribute}.json")),
             "#{attribute} is a quantity — a value enumeration ValueSet for it would be wrong"
    end
  end

  def test_payer_category_artifacts_match_ruby_vocabulary
    code_system = artifact("CodeSystem-uds-payer-category")
    value_set = artifact("ValueSet-uds-payer-category")

    assert_equal PayerCategory::CODE_SYSTEM, code_system["url"]
    assert_equal PayerCategory::ALL, code_system["concept"].map { |c| c["code"] }

    include_block = value_set["compose"]["include"].first
    assert_equal PayerCategory::CODE_SYSTEM, include_block["system"]
    assert_equal PayerCategory::ALL, include_block["concept"].map { |c| c["code"] }
  end

  def test_no_stray_artifacts
    # Every artifact file corresponds to a vocabulary this suite pins.
    expected = %w[CodeSystem-uds-supplemental-attribute CodeSystem-uds-supplemental-value
                  CodeSystem-uds-payer-category ValueSet-uds-payer-category] +
               Attributes::DEFINITIONS.filter_map { |code, d| "ValueSet-uds-supplemental-#{code}" if d[:value] == :coded }

    actual = Dir[File.join(ARTIFACTS_DIR, "*.json")].map { |p| File.basename(p, ".json") }
    assert_equal expected.sort, actual.sort
  end
end
