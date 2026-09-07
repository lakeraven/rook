# frozen_string_literal: true

require "test_helper"

class Rook::Ingest::ResourceFeedTest < Minitest::Test
  SOURCE = Rook::SourceDescriptor.new(id: "feed-test", platform: :rpms, channel: :primary_fhir)

  def test_stamps_provenance_overwriting_prior_source
    feed = Rook::Ingest::ResourceFeed.new(
      resources: [
        { "resourceType" => "Patient", "id" => "1" },
        { "resourceType" => "Observation", "id" => "2",
          "meta" => { "source" => "https://foreign.example.test", "profile" => [ "kept" ] } }
      ],
      source: SOURCE
    )

    resources = feed.each_resource.to_a

    assert(resources.all? { |r| r.dig("meta", "source") == "urn:lakeraven:source:feed-test" })
    # Other meta fields survive; only source is authoritative to the feed.
    assert_equal [ "kept" ], resources.last.dig("meta", "profile")
  end

  def test_rejects_non_resources
    [ nil, "Patient", {}, { "resourceType" => "" } ].each do |bad|
      feed = Rook::Ingest::ResourceFeed.new(resources: [ bad ], source: SOURCE)
      assert_raises(Rook::Ingest::MalformedResourceError) { feed.each_resource.to_a }
    end
  end

  def test_loads_through_ingest_seam
    feed = Rook::Ingest::ResourceFeed.new(
      resources: [ { "resourceType" => "Patient", "id" => "1" } ], source: SOURCE)

    resources = Rook::Ingest.load(feed)

    assert_equal "feed-test", Rook::Ingest.source_id(resources.first)
  end
end
