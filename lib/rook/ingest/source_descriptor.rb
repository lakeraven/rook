# frozen_string_literal: true

module Rook
  module Ingest
    # Identifies where an ingest feed's data comes from: which EHR platform,
    # and over which channel.
    #
    # +channel+ distinguishes the two feeds every platform adapter produces:
    #
    # +:primary_fhir+::  the platform's FHIR API export (Bulk Data NDJSON).
    # +:supplemental+::  the second channel — extra-FHIR attributes UDS
    #                    reporting needs that vendor FHIR APIs don't expose
    #                    (sliding-fee class, payer category, housing status,
    #                    migratory/seasonal agricultural worker status,
    #                    veteran status, ...), fetched per-platform and
    #                    normalized into FHIR shapes before reaching Rook.
    #
    # Keeping the channels distinguishable per resource is what lets measure
    # evaluation and UDS table generation substantiate which channel and
    # platform contributed a data element.
    class SourceDescriptor
      PLATFORMS = %i[rpms epic nextgen greenway ecw].freeze
      CHANNELS = %i[primary_fhir supplemental].freeze

      # +meta.source+ is a URI in FHIR; stamp source ids under this scheme.
      URI_PREFIX = "urn:lakeraven:source:"

      attr_reader :id, :platform, :channel

      def initialize(id:, platform:, channel:)
        platform = platform.to_sym
        channel = channel.to_sym
        unless PLATFORMS.include?(platform)
          raise ArgumentError, "unknown platform #{platform.inspect} (expected one of #{PLATFORMS.join(', ')})"
        end
        unless CHANNELS.include?(channel)
          raise ArgumentError, "unknown channel #{channel.inspect} (expected one of #{CHANNELS.join(', ')})"
        end
        @id = id.to_s
        @platform = platform
        @channel = channel
        freeze
      end

      def primary?
        channel == :primary_fhir
      end

      def supplemental?
        channel == :supplemental
      end

      # URI form used to stamp resources' +meta.source+.
      def uri
        "#{URI_PREFIX}#{id}"
      end

      def self.id_from_uri(uri)
        uri&.delete_prefix(URI_PREFIX)
      end
    end
  end
end
