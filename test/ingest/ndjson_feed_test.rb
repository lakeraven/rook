# frozen_string_literal: true

require "test_helper"
require "json"
require "tmpdir"

class Rook::Ingest::NdjsonFeedTest < Minitest::Test
  PRIMARY = Rook::Ingest::SourceDescriptor.new(id: "test-fhir", platform: :rpms, channel: :primary_fhir)
  SUPPLEMENTAL = Rook::Ingest::SourceDescriptor.new(id: "test-suppl", platform: :rpms, channel: :supplemental)

  def test_streams_one_resource_per_line
    with_ndjson("Patient.ndjson" => [ patient("p1"), patient("p2") ]) do |dir|
      feed = Rook::Ingest::NdjsonFeed.directory(dir, source: PRIMARY)

      assert_equal %w[p1 p2], feed.each_resource.map { |r| r["id"] }
    end
  end

  def test_skips_blank_lines
    with_ndjson({}) do |dir|
      File.write(File.join(dir, "Patient.ndjson"), "#{JSON.generate(patient('p1'))}\n\n")
      feed = Rook::Ingest::NdjsonFeed.directory(dir, source: PRIMARY)

      assert_equal 1, feed.each_resource.count
    end
  end

  def test_stamps_each_resource_with_the_source_uri
    with_ndjson("Patient.ndjson" => [ patient("p1") ]) do |dir|
      resource = Rook::Ingest::NdjsonFeed.directory(dir, source: PRIMARY).each_resource.first

      assert_equal "urn:lakeraven:source:test-fhir", resource.dig("meta", "source")
      assert_equal "test-fhir", Rook::Ingest.source_id(resource)
    end
  end

  def test_stamping_preserves_other_meta_fields
    profiled = patient("p1").merge(
      "meta" => { "profile" => [ "http://hl7.org/fhir/us/core/StructureDefinition/us-core-patient" ] })
    with_ndjson("Patient.ndjson" => [ profiled ]) do |dir|
      resource = Rook::Ingest::NdjsonFeed.directory(dir, source: PRIMARY).each_resource.first

      assert_equal [ "http://hl7.org/fhir/us/core/StructureDefinition/us-core-patient" ],
        resource.dig("meta", "profile")
    end
  end

  def test_directory_feed_reads_every_ndjson_file
    files = { "Patient.ndjson" => [ patient("p1") ],
             "Condition.ndjson" => [ { "resourceType" => "Condition", "id" => "c1" } ] }
    with_ndjson(files) do |dir|
      types = Rook::Ingest::NdjsonFeed.directory(dir, source: PRIMARY).each_resource.map { |r| r["resourceType"] }

      assert_equal %w[Condition Patient], types.sort
    end
  end

  def test_load_merges_channels_and_keeps_per_feed_provenance
    with_ndjson("Patient.ndjson" => [ patient("p1") ]) do |primary_dir|
      with_ndjson("Coverage.ndjson" => [ { "resourceType" => "Coverage", "id" => "cov1" } ]) do |suppl_dir|
        resources = Rook::Ingest.load(
          Rook::Ingest::NdjsonFeed.directory(primary_dir, source: PRIMARY),
          Rook::Ingest::NdjsonFeed.directory(suppl_dir, source: SUPPLEMENTAL))

        assert_equal 2, resources.size
        by_type = resources.to_h { |r| [ r["resourceType"], Rook::Ingest.source_id(r) ] }
        assert_equal({ "Patient" => "test-fhir", "Coverage" => "test-suppl" }, by_type)
      end
    end
  end

  def test_source_id_is_nil_for_resources_that_bypassed_ingest
    assert_nil Rook::Ingest.source_id(patient("p1"))
  end

  private

  def patient(id)
    { "resourceType" => "Patient", "id" => id }
  end

  def with_ndjson(files)
    Dir.mktmpdir do |dir|
      files.each do |name, resources|
        File.write(File.join(dir, name), resources.map { |r| "#{JSON.generate(r)}\n" }.join)
      end
      yield dir
    end
  end
end
