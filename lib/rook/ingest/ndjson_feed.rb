# frozen_string_literal: true

require "json"

module Rook
  module Ingest
    # One ingest feed: a set of FHIR NDJSON files (the Bulk Data export shape —
    # one resource per line, conventionally one file per resourceType) plus the
    # SourceDescriptor for the system they came from.
    #
    # Resources are streamed line by line and each is stamped with the feed's
    # source URI in +meta.source+, so provenance survives merging feeds. The
    # feed's descriptor is authoritative: any +meta.source+ already present on
    # a resource (e.g. server-populated by the exporting FHIR server) is
    # OVERWRITTEN; other +meta+ fields are left intact.
    class NdjsonFeed
      attr_reader :source

      # +paths+: NDJSON file paths. +source+: a SourceDescriptor.
      def initialize(paths:, source:)
        @paths = Array(paths)
        @source = source
      end

      # A feed over every *.ndjson file in +dir+ (a Bulk Data export directory).
      # Raises when the directory holds no .ndjson files — a typo'd path must
      # not silently yield an empty population.
      def self.directory(dir, source:)
        paths = Dir[File.join(dir, "*.ndjson")].sort
        raise ArgumentError, "no .ndjson files found in #{dir}" if paths.empty?

        new(paths: paths, source: source)
      end

      # Yields each resource hash with provenance stamped; returns an
      # Enumerator when no block is given.
      def each_resource
        return enum_for(:each_resource) unless block_given?

        @paths.each do |path|
          File.foreach(path).with_index(1) do |line, lineno|
            line = line.strip
            next if line.empty?
            yield stamp(parse(line, path, lineno))
          end
        end
      end

      private

      def parse(line, path, lineno)
        JSON.parse(line)
      rescue JSON::ParserError => e
        raise JSON::ParserError, "malformed NDJSON at #{path}:#{lineno}: #{e.message}"
      end

      def stamp(resource)
        (resource["meta"] ||= {})["source"] = source.uri
        resource
      end
    end
  end
end
