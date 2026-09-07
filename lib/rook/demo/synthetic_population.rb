# frozen_string_literal: true

require "json"
require "date"
require "rook/ingest"

module Rook
  module Demo
    # DEMO / REFERENCE ONLY — see Rook::Demo.
    #
    # Loads the synthetic FHIR R4 population and exposes it as a set of
    # lightweight Patient value objects. Loading goes through Rook::Ingest —
    # the same Bulk-Data-NDJSON seam the production path uses — as the two
    # channels a platform adapter delivers: the EHR's FHIR export plus the
    # supplemental channel of extra-FHIR UDS attributes normalized into FHIR
    # shapes. Plain-Ruby parsing only; no Pathling/Spark and no external FHIR
    # gem.
    class SyntheticPopulation
      FIXTURES_DIR = File.expand_path("fixtures", __dir__)

      PRIMARY_SOURCE = Rook::Ingest::SourceDescriptor.new(
        id: "demo-rpms-fhir", platform: :rpms, channel: :primary_fhir)
      SUPPLEMENTAL_SOURCE = Rook::Ingest::SourceDescriptor.new(
        id: "demo-rpms-supplemental", platform: :rpms, channel: :supplemental)

      # A single synthetic patient with its linked Conditions, Observations,
      # and Coverages.
      Patient = Struct.new(:id, :family_name, :given_name, :gender, :birth_date,
        :tribal_affiliation, :condition_codes, :observations, :coverages,
        keyword_init: true) do
        def name
          [ given_name, family_name ].compact.join(" ")
        end

        def age_on(date)
          years = date.year - birth_date.year
          years -= 1 if date < birth_date.next_year(years)
          years
        end

        def condition?(codes)
          !(condition_codes & Array(codes)).empty?
        end

        # Most recent Observation whose code is in +loinc_codes+ (a single code
        # or a value-set expansion) and whose effective date falls within the
        # (inclusive) period, or nil if none.
        def latest_observation(loinc_codes, period)
          codes = Array(loinc_codes)
          observations
            .select { |o| codes.include?(o.loinc) && period.cover?(o.effective_date) }
            .max_by(&:effective_date)
        end
      end

      # A flattened Observation. +loinc+ holds the primary code — a LOINC code
      # for clinical observations, or an internal attribute code for
      # supplemental-channel observations (whose coded value lands in +value+).
      # For blood pressure, +components+ maps a LOINC code to its numeric
      # value (systolic 8480-6, diastolic 8462-4). +source_id+ is ingest
      # provenance: which feed contributed this element.
      Observation = Struct.new(:loinc, :value, :effective_date, :components, :source_id,
        keyword_init: true) do
        # Value of the first component whose code is in +loinc_codes+ (a single
        # code or a value-set expansion), or nil.
        def component_value(loinc_codes)
          components.values_at(*Array(loinc_codes)).compact.first
        end
      end

      # A flattened Coverage: +payer_category+ is the coded payer bucket UDS
      # table 4 needs — supplemental-channel data, so +source_id+ says which
      # feed asserted it.
      Coverage = Struct.new(:payer_category, :source_id, keyword_init: true)

      # The committed fixture population, loaded through the ingest seam:
      # the primary FHIR feed merged with the supplemental UDS-attribute feed,
      # per-resource provenance retained.
      def self.default
        ingest(
          Rook::Ingest::NdjsonFeed.directory(File.join(FIXTURES_DIR, "primary_fhir"),
            source: PRIMARY_SOURCE),
          Rook::Ingest::NdjsonFeed.directory(File.join(FIXTURES_DIR, "supplemental"),
            source: SUPPLEMENTAL_SOURCE)
        )
      end

      # Builds the population from one or more Rook::Ingest feeds.
      def self.ingest(*feeds)
        new(resources: Rook::Ingest.load(*feeds))
      end

      # Accepts either a FHIR collection Bundle hash (+bundle+) or a flat
      # +resources+ array (the ingest-seam shape).
      def initialize(bundle = nil, resources: nil)
        @resources = resources || bundle.fetch("entry").map { |e| e.fetch("resource") }
        @patients = build_patients
      end

      attr_reader :patients

      private

      def build_patients
        by_type = @resources.group_by { |r| r["resourceType"] }
        conditions = (by_type["Condition"] || []).group_by { |c| subject_id(c) }
        observations = (by_type["Observation"] || []).group_by { |o| subject_id(o) }
        coverages = (by_type["Coverage"] || []).group_by { |c| subject_id(c) }

        (by_type["Patient"] || []).map do |p|
          id = p.fetch("id")
          Patient.new(
            id: id,
            family_name: p.dig("name", 0, "family"),
            given_name: Array(p.dig("name", 0, "given")).first,
            gender: p["gender"],
            birth_date: Date.parse(p.fetch("birthDate")),
            tribal_affiliation: tribal_affiliation(p),
            condition_codes: (conditions[id] || []).flat_map { |c| codings(c["code"]) }.uniq,
            observations: (observations[id] || []).map { |o| build_observation(o) },
            coverages: (coverages[id] || []).map { |c| build_coverage(c) }
          )
        end
      end

      def subject_id(resource)
        reference = resource.dig("subject", "reference") || resource.dig("beneficiary", "reference")
        reference.to_s.split("/").last
      end

      def codings(codeable_concept)
        Array(codeable_concept&.dig("coding")).map { |c| c["code"] }
      end

      def build_observation(obs)
        components = {}
        Array(obs["component"]).each do |comp|
          code = codings(comp["code"]).first
          components[code] = comp.dig("valueQuantity", "value")
        end
        Observation.new(
          loinc: codings(obs["code"]).first,
          value: obs.dig("valueQuantity", "value") || codings(obs["valueCodeableConcept"]).first,
          effective_date: Date.parse(obs.fetch("effectiveDateTime")),
          components: components,
          source_id: Rook::Ingest.source_id(obs)
        )
      end

      def build_coverage(coverage)
        Coverage.new(
          payer_category: codings(coverage["type"]).first,
          source_id: Rook::Ingest.source_id(coverage)
        )
      end

      def tribal_affiliation(patient)
        ext = Array(patient["extension"]).find do |e|
          e["url"] == "http://hl7.org/fhir/us/core/StructureDefinition/us-core-tribal-affiliation"
        end
        ext&.dig("extension", 0, "valueCodeableConcept", "text")
      end
    end
  end
end
