# frozen_string_literal: true

module Rook
  # Immutable value object identifying a data source feeding Rook: which EHR
  # platform the data comes from, and over which channel.
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
  # platform contributed a data element — quality-measure certification and
  # audit rules require supplemental data to be distinguishable from the
  # primary FHIR feed, by source.
  #
  # This is the canonical descriptor across the Lakeraven stack: ingest feeds
  # (Rook::Ingest) and supplemental-data readers
  # (Rook::Ports::SupplementalData::Base) both carry one, and external
  # implementations of Rook ports use this class rather than defining their
  # own.
  #
  # +id+ is the provenance key: it is the only part of the descriptor that
  # +meta.source+ persists, so it must be unique across the sources merged
  # into one dataset (Ingest.load enforces this per load) — two sources
  # sharing an id would be indistinguishable in audit evidence regardless of
  # platform/channel.
  class SourceDescriptor
    # EHR platforms with planned adapters. Not a closed set — any lowercase
    # token is accepted so a new platform doesn't require a Rook release.
    KNOWN_PLATFORMS = %i[rpms epic nextgen greenway ecw].freeze

    CHANNELS = %i[primary_fhir supplemental].freeze

    # +meta.source+ is a URI in FHIR; stamp source ids under this scheme.
    URI_PREFIX = "urn:lakeraven:source:"

    attr_reader :id, :platform, :channel

    # @param id [String] stable identifier for the source (unique per deployment)
    # @param platform [String, Symbol] platform token (see KNOWN_PLATFORMS)
    # @param channel [String, Symbol] one of CHANNELS
    def initialize(id:, platform:, channel:)
      raise ArgumentError, "id must be a non-empty string" if id.to_s.strip.empty?

      platform = platform.to_sym
      unless platform.match?(/\A[a-z][a-z0-9_]*\z/)
        raise ArgumentError, "platform must be a lowercase token (got #{platform.inspect})"
      end

      channel = channel.to_sym
      unless CHANNELS.include?(channel)
        raise ArgumentError, "unknown channel #{channel.inspect} (expected one of #{CHANNELS.join(', ')})"
      end

      # Deep-freeze: dup + freeze the id so callers holding the original
      # argument cannot mutate a descriptor's identity out from under
      # duplicate detection or meta.source stamping.
      @id = id.to_s.dup.freeze
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

    # URI form used to stamp resources' +meta.source+, so lineage survives on
    # the resource itself.
    def uri
      "#{URI_PREFIX}#{id}"
    end

    # The source id encoded in +uri+, or nil for URIs outside our scheme —
    # +meta.source+ can arrive server-populated with foreign values (e.g. a
    # FHIR base URL), which must not read back as fake source ids.
    def self.id_from_uri(uri)
      return nil unless uri&.start_with?(URI_PREFIX)

      uri.delete_prefix(URI_PREFIX)
    end

    def ==(other)
      other.is_a?(SourceDescriptor) &&
        other.id == id &&
        other.platform == platform &&
        other.channel == channel
    end
    alias eql? ==

    def hash
      [ self.class, id, platform, channel ].hash
    end
  end
end
