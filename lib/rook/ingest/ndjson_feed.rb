# frozen_string_literal: true

require "json"

module Rook
  module Ingest
    # One ingest feed: a set of FHIR NDJSON files (the Bulk Data export shape —
    # one resource per line, conventionally one file per resourceType) plus the
    # SourceDescriptor for the system they came from.
    #
    # Resources are streamed line by line and each is stamped with the feed's
    # source URI in +meta.source+, so provenance survives merging feeds.
    class NdjsonFeed
      attr_reader :source

      # +paths+: NDJSON file paths. +source+: a SourceDescriptor.
      def initialize(paths:, source:)
        @paths = Array(paths)
        @source = source
      end

      # A feed over every *.ndjson file in +dir+ (a Bulk Data export directory).
      def self.directory(dir, source:)
        new(paths: Dir[File.join(dir, "*.ndjson")].sort, source: source)
      end

      # Yields each resource hash with provenance stamped; returns an
      # Enumerator when no block is given.
      def each_resource
        return enum_for(:each_resource) unless block_given?

        @paths.each do |path|
          File.foreach(path) do |line|
            line = line.strip
            next if line.empty?
            yield stamp(JSON.parse(line))
          end
        end
      end

      private

      def stamp(resource)
        (resource["meta"] ||= {})["source"] = source.uri
        resource
      end
    end
  end
end
