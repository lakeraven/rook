# frozen_string_literal: true

require "test_helper"

class Rook::ValueSetResolverTest < Minitest::Test
  URL = "https://example.org/fhir/ValueSet/diabetes"

  def setup
    @resolver = Rook::InMemoryValueSetResolver.new(URL => %w[E11.9 44054006])
  end

  def test_expands_a_known_value_set
    assert_equal %w[E11.9 44054006], @resolver.codes(URL)
  end

  def test_membership_via_the_port_default
    assert @resolver.include?(URL, "E11.9")
    refute @resolver.include?(URL, "I10")
  end

  def test_unknown_value_set_raises
    assert_raises(KeyError) { @resolver.codes("https://example.org/fhir/ValueSet/unknown") }
  end

  def test_port_base_class_is_abstract
    assert_raises(NotImplementedError) { Rook::ValueSetResolver.new.codes(URL) }
  end
end
