# frozen_string_literal: true

require "rook/source_descriptor"
require "rook/ingest/ndjson_feed"
require "rook/ingest/resource_feed"

module Rook
  # Ingest seam: FHIR Bulk Data NDJSON in, provenance-tagged resources out.
  #
  # This is the boundary the Tier-1 production path (Bulk Data export ->
  # per-tenant warehouse, rook#64 / rook#59) will grow behind. Every consumer —
  # including the demo — loads population data through this seam rather than
  # through bespoke parsers, so the ingestion contract is exercised everywhere.
  #
  # Each EHR platform contributes up to two feeds: its FHIR API export
  # (+:primary_fhir+) and a +:supplemental+ channel of extra-FHIR attributes
  # UDS reporting requires but vendor FHIR APIs don't expose, normalized into
  # FHIR shapes by per-platform adapters before they get here. Rook only ever
  # sees NDJSON feeds of FHIR resources.
  #
  # Provenance contract (rook#72): each feed carries a SourceDescriptor, and
  # every resource a feed emits is stamped with that source's URI in
  # +meta.source+. Supplemental-data audit rules require substantiating WHICH
  # channel/platform contributed a data element; retaining per-resource
  # provenance from ingest onward is what makes that substantiation possible
  # downstream.
  #
  # Feeds merged in one +load+ must be disjoint by resource identity
  # (resourceType, id): two feeds contributing the same resource would
  # silently double-count denominators, so +load+ raises instead.
  # Deduplication/merge semantics belong to the warehouse layer later.
  module Ingest
    # The canonical descriptor lives at Rook::SourceDescriptor (shared with
    # Rook::Ports); this alias keeps the original ingest-scoped name working.
    SourceDescriptor = Rook::SourceDescriptor

    # Two feeds contributed the same (resourceType, id) — see Rook::Ingest.
    class DuplicateResourceError < StandardError; end

    # Two feeds in one +load+ carry the same SourceDescriptor id. The
    # descriptor id is the provenance key: it is all that +meta.source+
    # persists, so feeds sharing an id would be indistinguishable in audit
    # evidence even if their platform/channel differ.
    class DuplicateSourceError < StandardError; end

    # A parsed ingest payload is not a usable FHIR resource (wrong JSON shape,
    # missing resourceType, or a missing/malformed subject reference).
    class MalformedResourceError < StandardError; end

    # Merges one or more feeds into a single resource set, preserving feed
    # order and per-resource provenance. In-memory only for now — the
    # warehouse-backed implementation replaces the storage, not this seam.
    # Raises DuplicateSourceError when two feeds share a descriptor id, and
    # DuplicateResourceError when feeds are not disjoint by (resourceType, id).
    def self.load(*feeds)
      duplicate_ids = feeds.map { |feed| feed.source.id }.tally.select { |_, count| count > 1 }.keys
      unless duplicate_ids.empty?
        raise DuplicateSourceError,
          "multiple feeds share source descriptor id(s) #{duplicate_ids.join(', ')} — " \
          "the descriptor id is the provenance key persisted in meta.source, " \
          "so every feed in a load must carry a unique id"
      end

      resources = feeds.flat_map { |feed| feed.each_resource.to_a }
      seen = {}
      resources.each do |resource|
        key = [ resource["resourceType"], resource["id"] ]
        if (prior = seen[key])
          raise DuplicateResourceError,
            "duplicate resource #{key.first}/#{key.last}: contributed by " \
            "both #{prior.inspect} and #{source_id(resource).inspect} — " \
            "feeds must be disjoint by (resourceType, id)"
        end
        seen[key] = source_id(resource)
      end
      resources
    end

    # The source id a resource was ingested from, recovered from +meta.source+
    # (nil when the resource did not pass through an ingest feed).
    def self.source_id(resource)
      SourceDescriptor.id_from_uri(resource.dig("meta", "source"))
    end
  end
end
