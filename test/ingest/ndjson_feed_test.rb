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

  def test_stamping_replaces_a_preexisting_meta_source_and_keeps_other_meta_fields
    # The feed descriptor is authoritative for provenance: a server-populated
    # meta.source is overwritten, while the rest of meta survives.
    exported = patient("p1").merge(
      "meta" => { "source" => "https://fhir.example.test/r4",
                 "versionId" => "3",
                 "profile" => [ "http://hl7.org/fhir/us/core/StructureDefinition/us-core-patient" ] })
    with_ndjson("Patient.ndjson" => [ exported ]) do |dir|
      resource = Rook::Ingest::NdjsonFeed.directory(dir, source: PRIMARY).each_resource.first

      assert_equal "urn:lakeraven:source:test-fhir", resource.dig("meta", "source")
      assert_equal "3", resource.dig("meta", "versionId")
      assert_equal [ "http://hl7.org/fhir/us/core/StructureDefinition/us-core-patient" ],
        resource.dig("meta", "profile")
    end
  end

  def test_malformed_ndjson_reports_file_and_line
    with_ndjson({}) do |dir|
      path = File.join(dir, "Patient.ndjson")
      File.write(path, "#{JSON.generate(patient('p1'))}\n\n{not json\n")
      feed = Rook::Ingest::NdjsonFeed.directory(dir, source: PRIMARY)

      error = assert_raises(JSON::ParserError) { feed.each_resource.to_a }
      assert_includes error.message, path
      assert_includes error.message, "#{path}:3"
    end
  end

  def test_non_resource_json_reports_file_and_line
    [ "{}", "[1,2]", "\"Patient\"", JSON.generate("resourceType" => "") ].each do |bad_line|
      with_ndjson({}) do |dir|
        path = File.join(dir, "Patient.ndjson")
        File.write(path, "#{JSON.generate(patient('p1'))}\n#{bad_line}\n")
        feed = Rook::Ingest::NdjsonFeed.directory(dir, source: PRIMARY)

        error = assert_raises(Rook::Ingest::MalformedResourceError) { feed.each_resource.to_a }
        assert_includes error.message, "#{path}:2"
        assert_includes error.message, "resourceType"
      end
    end
  end

  def test_load_raises_when_two_feeds_share_a_descriptor_id
    # The descriptor id is the provenance key persisted in meta.source: two
    # feeds sharing an id would be indistinguishable in audit evidence even
    # with different platform/channel.
    same_id_other_channel = Rook::Ingest::SourceDescriptor.new(
      id: "test-fhir", platform: :epic, channel: :supplemental)
    with_ndjson("Patient.ndjson" => [ patient("p1") ]) do |primary_dir|
      with_ndjson("Coverage.ndjson" => [ { "resourceType" => "Coverage", "id" => "cov1" } ]) do |suppl_dir|
        error = assert_raises(Rook::Ingest::DuplicateSourceError) do
          Rook::Ingest.load(
            Rook::Ingest::NdjsonFeed.directory(primary_dir, source: PRIMARY),
            Rook::Ingest::NdjsonFeed.directory(suppl_dir, source: same_id_other_channel))
        end

        assert_includes error.message, "test-fhir"
      end
    end
  end

  def test_directory_feed_raises_when_no_ndjson_files_present
    Dir.mktmpdir do |dir|
      error = assert_raises(ArgumentError) do
        Rook::Ingest::NdjsonFeed.directory(File.join(dir, "typod-path"), source: PRIMARY)
      end

      assert_includes error.message, "typod-path"
    end
  end

  def test_load_raises_on_id_collision_across_feeds
    with_ndjson("Patient.ndjson" => [ patient("p1") ]) do |primary_dir|
      with_ndjson("Patient.ndjson" => [ patient("p1") ]) do |suppl_dir|
        error = assert_raises(Rook::Ingest::DuplicateResourceError) do
          Rook::Ingest.load(
            Rook::Ingest::NdjsonFeed.directory(primary_dir, source: PRIMARY),
            Rook::Ingest::NdjsonFeed.directory(suppl_dir, source: SUPPLEMENTAL))
        end

        assert_includes error.message, "Patient/p1"
        assert_includes error.message, "test-fhir"
        assert_includes error.message, "test-suppl"
      end
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
