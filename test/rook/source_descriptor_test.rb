# frozen_string_literal: true

require "test_helper"

class Rook::SourceDescriptorTest < Minitest::Test
  def test_primary_fhir_channel
    source = Rook::SourceDescriptor.new(id: "site-fhir", platform: :rpms, channel: :primary_fhir)

    assert source.primary?
    refute source.supplemental?
  end

  def test_supplemental_channel
    source = Rook::SourceDescriptor.new(id: "site-suppl", platform: :rpms, channel: :supplemental)

    refute source.primary?
    assert source.supplemental?
  end

  def test_vocabulary
    assert_equal %i[rpms epic nextgen greenway ecw], Rook::SourceDescriptor::KNOWN_PLATFORMS
    assert_equal %i[primary_fhir supplemental], Rook::SourceDescriptor::CHANNELS
  end

  def test_platform_is_an_open_set_of_lowercase_tokens
    # A new platform must not require a Rook release — any lowercase token
    # is accepted beyond KNOWN_PLATFORMS.
    source = Rook::SourceDescriptor.new(id: "src", platform: :abacus, channel: :primary_fhir)

    assert_equal :abacus, source.platform
  end

  def test_rejects_non_token_platform
    error = assert_raises(ArgumentError) do
      Rook::SourceDescriptor.new(id: "src", platform: "Abacus EHR!", channel: :primary_fhir)
    end
    assert_match(/lowercase token/, error.message)
  end

  def test_rejects_unknown_channel
    error = assert_raises(ArgumentError) do
      Rook::SourceDescriptor.new(id: "src", platform: :epic, channel: :sneakernet)
    end
    assert_match(/sneakernet/, error.message)
  end

  def test_rejects_blank_id
    assert_raises(ArgumentError) { Rook::SourceDescriptor.new(id: "", platform: :rpms, channel: :supplemental) }
    assert_raises(ArgumentError) { Rook::SourceDescriptor.new(id: "   ", platform: :rpms, channel: :supplemental) }
    assert_raises(ArgumentError) { Rook::SourceDescriptor.new(id: nil, platform: :rpms, channel: :supplemental) }
  end

  def test_descriptor_is_frozen_and_detached_from_caller_strings
    id = +"site-a"
    source = Rook::SourceDescriptor.new(id: id, platform: :rpms, channel: :supplemental)
    id << "-mutated"

    assert source.frozen?
    assert_equal "site-a", source.id
  end

  def test_value_equality
    a = Rook::SourceDescriptor.new(id: "site-a", platform: :rpms, channel: :supplemental)
    b = Rook::SourceDescriptor.new(id: "site-a", platform: "rpms", channel: "supplemental")
    c = Rook::SourceDescriptor.new(id: "site-a", platform: :rpms, channel: :primary_fhir)

    assert_equal a, b
    assert_equal a.hash, b.hash
    refute_equal a, c
  end

  def test_uri_round_trips_through_id_from_uri
    source = Rook::SourceDescriptor.new(id: "site-suppl", platform: :nextgen, channel: :supplemental)

    assert_equal "urn:lakeraven:source:site-suppl", source.uri
    assert_equal "site-suppl", Rook::SourceDescriptor.id_from_uri(source.uri)
  end

  def test_id_from_uri_rejects_foreign_uris
    assert_nil Rook::SourceDescriptor.id_from_uri(nil)
    assert_nil Rook::SourceDescriptor.id_from_uri("https://fhir.example.test/r4/Patient")
    assert_nil Rook::SourceDescriptor.id_from_uri("urn:uuid:0f3a")
    assert_nil Rook::SourceDescriptor.id_from_uri("")
  end

  def test_ingest_scoped_alias_stays_usable
    # Rook::Ingest::SourceDescriptor was the original home; the alias keeps
    # existing call sites working against the canonical class.
    assert_same Rook::SourceDescriptor, Rook::Ingest::SourceDescriptor
  end
end
