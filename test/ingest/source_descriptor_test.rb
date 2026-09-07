# frozen_string_literal: true

require "test_helper"

class Rook::Ingest::SourceDescriptorTest < Minitest::Test
  def test_primary_fhir_channel_is_not_supplemental
    source = Rook::Ingest::SourceDescriptor.new(id: "site-fhir", platform: :rpms, channel: :primary_fhir)

    assert_predicate source, :primary?
    refute_predicate source, :supplemental?
    assert_equal :rpms, source.platform
  end

  def test_supplemental_channel_is_supplemental
    source = Rook::Ingest::SourceDescriptor.new(id: "site-suppl", platform: :rpms, channel: :supplemental)

    assert_predicate source, :supplemental?
    refute_predicate source, :primary?
  end

  def test_platform_vocabulary_is_the_adapter_roster
    assert_equal %i[rpms epic nextgen greenway ecw], Rook::Ingest::SourceDescriptor::PLATFORMS
    assert_equal %i[primary_fhir supplemental], Rook::Ingest::SourceDescriptor::CHANNELS
  end

  def test_rejects_unknown_platform
    error = assert_raises(ArgumentError) do
      Rook::Ingest::SourceDescriptor.new(id: "src", platform: :abacus, channel: :primary_fhir)
    end

    assert_includes error.message, "abacus"
  end

  def test_rejects_unknown_channel
    error = assert_raises(ArgumentError) do
      Rook::Ingest::SourceDescriptor.new(id: "src", platform: :epic, channel: :sneakernet)
    end

    assert_includes error.message, "sneakernet"
  end

  def test_uri_round_trips_the_source_id
    source = Rook::Ingest::SourceDescriptor.new(id: "site-suppl", platform: :nextgen, channel: :supplemental)

    assert_equal "urn:lakeraven:source:site-suppl", source.uri
    assert_equal "site-suppl", Rook::Ingest::SourceDescriptor.id_from_uri(source.uri)
  end

  def test_id_from_uri_handles_nil
    assert_nil Rook::Ingest::SourceDescriptor.id_from_uri(nil)
  end

  def test_id_from_uri_rejects_foreign_meta_source_values
    # meta.source can arrive server-populated (e.g. a FHIR base URL); a URI
    # outside our scheme must not read back as a fake feed id.
    assert_nil Rook::Ingest::SourceDescriptor.id_from_uri("https://fhir.example.test/r4/Patient")
    assert_nil Rook::Ingest::SourceDescriptor.id_from_uri("urn:uuid:0f3a")
    assert_nil Rook::Ingest::SourceDescriptor.id_from_uri("")
  end
end
