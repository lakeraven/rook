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

      # Observations coded under this system are supplemental registration
      # attributes (sliding-fee class, housing status, ...) — the one class of
      # observation for which an undated value means "registration-current".
      SUPPLEMENTAL_ATTRIBUTE_SYSTEM =
        "https://terminology.lakeraven.com/CodeSystem/uds-supplemental-attribute"

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

        # Most recent Observation whose code is in +loinc_codes+ (a single
        # code or a value-set expansion) within the period, or nil.
        # Two read semantics, split by coding system (the shared cross-repo
        # UDS rule):
        #
        # Supplemental registration attributes (coded under
        # SUPPLEMENTAL_ATTRIBUTE_SYSTEM) read as "current as of period end":
        # the latest dated value with date <= period end wins, and an UNDATED
        # value beats all dated ones — it is the registration-current value.
        #
        # Clinical observations (everything else) require a date: only dated
        # readings inside the (inclusive) period match, and an undated
        # clinical observation never matches — a dateless lab result must not
        # flip a measure outcome.
        #
        # NOTE: matching is still on the bare code string; only the
        # undated-wins rule is system-scoped. Full system-aware code matching
        # arrives with the production reader.
        def latest_observation(loinc_codes, period)
          codes = Array(loinc_codes)
          supplemental, clinical = observations
            .select { |o| codes.include?(o.loinc) }
            .partition(&:supplemental_attribute?)
          if supplemental.any?
            undated, dated = supplemental.partition { |o| o.effective_date.nil? }
            undated.last ||
              dated.select { |o| o.effective_date <= period.end }.max_by(&:effective_date)
          else
            clinical.select { |o| o.effective_date && period.cover?(o.effective_date) }
              .max_by(&:effective_date)
          end
        end

        # Coverages that are current as of +as_of+: only +status+ "active"
        # counts, and the coverage period must cover the date (nil bounds are
        # open). A patient may legitimately hold several current coverages
        # (e.g. dual-eligible), so this stays a list — no collapsing.
        def current_coverages(as_of)
          coverages.select { |c| c.current_on?(as_of) }
        end
      end

      # A flattened Observation. +loinc+ holds the primary code — a LOINC code
      # for clinical observations, or an internal attribute code for
      # supplemental-channel observations (whose coded value lands in +value+).
      # +code_system+ is that primary coding's system, used to scope the
      # undated-wins read rule to supplemental registration attributes.
      # For blood pressure, +components+ maps a LOINC code to its numeric
      # value (systolic 8480-6, diastolic 8462-4). +effective_date+ resolves
      # FHIR effective[x] (effectiveDateTime, effectivePeriod — its end,
      # falling back to start — or effectiveInstant); nil means undated, which
      # is "registration-current" for supplemental attributes and never
      # matches a period lookup for clinical observations. +source_id+ is
      # ingest provenance: which feed contributed this element.
      Observation = Struct.new(:loinc, :value, :effective_date, :components, :code_system,
        :source_id, keyword_init: true) do
        def supplemental_attribute?
          code_system == SUPPLEMENTAL_ATTRIBUTE_SYSTEM
        end

        # Value of the first component whose code is in +loinc_codes+ (a single
        # code or a value-set expansion), or nil.
        def component_value(loinc_codes)
          components.values_at(*Array(loinc_codes)).compact.first
        end
      end

      # A flattened Coverage: +payer_category+ is the coded payer bucket UDS
      # table 4 needs — supplemental-channel data, so +source_id+ says which
      # feed asserted it. +status+ and the period bounds are kept so payer
      # reads can honor only active, period-current coverage.
      Coverage = Struct.new(:payer_category, :status, :period_start, :period_end,
        :source_id, keyword_init: true) do
        # Active and period-current as of +date+ (start <= date <= end; a nil
        # bound is open — in particular nil end = still in force).
        def current_on?(date)
          status == "active" &&
            (period_start.nil? || period_start <= date) &&
            (period_end.nil? || date <= period_end)
        end
      end

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

      # Fails closed: a resource whose subject/beneficiary reference is
      # missing or malformed must not silently vanish from every patient.
      def subject_id(resource)
        reference = resource.dig("subject", "reference") || resource.dig("beneficiary", "reference")
        id = reference.to_s.split("/", -1).last
        if id.nil? || id.empty?
          raise Rook::Ingest::MalformedResourceError,
            "#{resource['resourceType']}/#{resource['id']} has a missing or malformed " \
            "subject/beneficiary reference (#{reference.inspect})"
        end
        id
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
          # Undated = no effective[x] at all; see Patient#latest_observation.
          effective_date: effective_date(obs),
          components: components,
          code_system: obs.dig("code", "coding", 0, "system"),
          source_id: Rook::Ingest.source_id(obs)
        )
      end

      # Resolves FHIR effective[x]: effectiveDateTime, effectivePeriod (its
      # end, falling back to start), or effectiveInstant. Nil when absent.
      def effective_date(obs)
        raw = obs["effectiveDateTime"] ||
          obs.dig("effectivePeriod", "end") || obs.dig("effectivePeriod", "start") ||
          obs["effectiveInstant"]
        raw && Date.parse(raw)
      end

      def build_coverage(coverage)
        Coverage.new(
          payer_category: codings(coverage["type"]).first,
          status: coverage["status"],
          period_start: coverage.dig("period", "start")&.then { |d| Date.parse(d) },
          period_end: coverage.dig("period", "end")&.then { |d| Date.parse(d) },
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
