# frozen_string_literal: true

module Rook
  module Ingest
    # An in-memory ingest feed: already-parsed FHIR resource hashes plus the
    # SourceDescriptor they came from. Same contract and provenance stamping
    # as NdjsonFeed (the feed's descriptor overwrites any pre-existing
    # +meta.source+) — for adapters and drivers that produce resources
    # directly rather than NDJSON files, so their data still enters through
    # Rook::Ingest.load and carries per-resource lineage.
    class ResourceFeed
      attr_reader :source

      # +resources+: Array of FHIR resource hashes. +source+: a SourceDescriptor.
      def initialize(resources:, source:)
        @resources = resources
        @source = source
      end

      def each_resource
        return enum_for(:each_resource) unless block_given?

        @resources.each do |resource|
          unless resource.is_a?(Hash) && resource["resourceType"].is_a?(String) && !resource["resourceType"].empty?
            raise MalformedResourceError,
              "not a FHIR resource: expected a hash with a non-empty resourceType, got #{resource.inspect}"
          end
          (resource["meta"] ||= {})["source"] = source.uri
          yield resource
        end
      end
    end
  end
end
