# frozen_string_literal: true

require "date"
require "securerandom"

require "rook/ports/supplemental_data/base"

module Rook
  module Ports
    module SupplementalData
      # In-memory mock supplemental reader for testing without an EHR
      # backend. Also serves as the executable spec of the normalized
      # shape: seeding builds the same Attributes-coded FHIR::Observation
      # (and PayerCategory-typed FHIR::Coverage) a concrete reader must
      # emit, and reads implement the Base period contract — patient-level
      # reads are "current as of period end" (period nil = as of today):
      # latest dated value on or before the as-of date wins, an undated
      # value beats all dated ones, future-dated values never match.
      # Coverage reads return every currently-effective coverage per
      # patient (latest-wins per beneficiary + payer category, so
      # dual-eligibles carry multiple Coverages); visit-level reads select
      # visits within the period.
      #
      # Reads return copies of the stored resources, so callers mutating a
      # returned resource cannot corrupt the store.
      class Mock < Base
        attr_reader :source_descriptor

        def initialize(source_descriptor: default_descriptor)
          super()
          @source_descriptor = source_descriptor
          @patient_observations = {}
          @visit_observations = {}
          @coverages = {}
        end

        # Seed a patient-level attribute value.
        # @param patient_id [String]
        # @param attribute [String] one of Attributes::PATIENT_LEVEL
        # @param value [Numeric, String] per the attribute's value kind —
        #   a Numeric whole percent for :percent, an enumerated code
        #   (the attribute's +values:+) for :coded
        # @param effective [Date, nil] effective date (nil = undated, currently effective)
        # @return [FHIR::Observation] the normalized observation
        def seed_patient_attribute(patient_id, attribute, value, effective: nil)
          validate_attribute!(attribute, Attributes::PATIENT_LEVEL)
          validate_value!(attribute, value)
          observation = build_observation(patient_id, attribute, value, effective, nil)
          (@patient_observations[patient_id.to_s] ||= []) << observation
          observation
        end

        # Seed a visit-level attribute value.
        # @param patient_id [String]
        # @param encounter_id [String] visit the attribute classifies
        # @param attribute [String] one of Attributes::VISIT_LEVEL
        # @param value [String] enumerated code per the attribute's +values:+
        # @param effective [Date, nil] visit date (nil = undated, matches any period)
        # @return [FHIR::Observation] the normalized observation
        def seed_visit_attribute(patient_id, encounter_id, attribute, value, effective: nil)
          validate_attribute!(attribute, Attributes::VISIT_LEVEL)
          validate_value!(attribute, value)
          observation = build_observation(patient_id, attribute, value, effective, encounter_id)
          (@visit_observations[patient_id.to_s] ||= []) << observation
          observation
        end

        # Seed a payer-category coverage record.
        # @param patient_id [String]
        # @param payer_category [String] one of PayerCategory::ALL
        # @param effective [Date, nil] coverage start (nil = undated, currently effective)
        # @param ends [Date, nil] coverage end/termination date (nil = open-ended)
        # @param status [String] FHIR Coverage.status; only "active"
        #   coverages are returned by reads
        # @return [FHIR::Coverage] the normalized coverage
        def seed_patient_coverage(patient_id, payer_category, effective: nil, ends: nil, status: "active")
          unless PayerCategory::ALL.include?(payer_category)
            raise ArgumentError,
                  "payer_category must be one of: #{PayerCategory::ALL.join(', ')} (got #{payer_category.inspect})"
          end

          period = { start: effective&.to_s, end: ends&.to_s }.compact
          coverage = FHIR::Coverage.new(
            id: SecureRandom.uuid,
            status: status,
            type: { coding: [ { system: PayerCategory::CODE_SYSTEM, code: payer_category } ] },
            beneficiary: { reference: "Patient/#{patient_id}" },
            # R4 requires payor (1..*); the mock stamps a synthetic
            # display-only organization reference.
            payor: [ { display: "Example Payer Organization (#{payer_category})" } ],
            period: period.empty? ? nil : period
          )
          (@coverages[patient_id.to_s] ||= []) << coverage
          coverage
        end

        def patient_attributes(patient_ids, period: nil, attributes: nil)
          attributes = validate_attribute_filter!(attributes, Attributes::PATIENT_LEVEL)
          observations = gather(@patient_observations, patient_ids)
          observations = observations.select { |o| attributes.include?(attribute_code(o)) }
          emit(latest_per(observations, as_of(period)) { |o| [ o.subject.reference, attribute_code(o) ] })
        end

        def visit_attributes(patient_ids, period: nil, attributes: nil)
          attributes = validate_attribute_filter!(attributes, Attributes::VISIT_LEVEL)
          observations = gather(@visit_observations, patient_ids)
          observations = observations.select { |o| attributes.include?(attribute_code(o)) }
          observations = observations.select { |o| within_period?(o, period) } if period
          emit(observations)
        end

        # All currently-effective coverages per patient — dual-eligibles
        # carry Medicare AND Medicaid Coverages simultaneously, so there is
        # no collapse to one coverage per beneficiary: temporal latest-wins
        # applies per (beneficiary, payer category). "Currently effective"
        # at the as-of date means status "active" and start <= as-of <= end
        # (nil end = open-ended, nil start = registration-current).
        def patient_coverages(patient_ids, period: nil)
          date = as_of(period)
          coverages = gather(@coverages, patient_ids)
          coverages = coverages.select { |c| c.status == "active" && !terminated_by?(c, date) }
          emit(latest_per(coverages, date) { |c| [ c.beneficiary.reference, payer_code(c) ] })
        end

        private

        def default_descriptor
          Rook::SourceDescriptor.new(id: "mock", platform: :rpms, channel: :supplemental)
        end

        def validate_attribute!(attribute, allowed)
          return if allowed.include?(attribute)

          raise ArgumentError, "attribute must be one of: #{allowed.join(', ')} (got #{attribute.inspect})"
        end

        def validate_value!(attribute, value)
          definition = Attributes::DEFINITIONS.fetch(attribute)
          case definition[:value]
          when :percent
            unless value.is_a?(Numeric) && value.finite?
              raise ArgumentError, "#{attribute} value must be finite Numeric (got #{value.inspect})"
            end
          when :coded
            unless definition[:values].include?(value)
              raise ArgumentError,
                    "#{attribute} value must be one of: #{definition[:values].join(', ')} (got #{value.inspect})"
            end
          end
        end

        # @param attributes [Array<String>, nil] requested subset; nil = all
        # @return [Array<String>] the validated filter
        def validate_attribute_filter!(attributes, allowed)
          return allowed if attributes.nil?

          unknown = Array(attributes) - allowed
          unless unknown.empty?
            raise ArgumentError, "unknown attributes for this level: #{unknown.join(', ')} " \
                                 "(allowed: #{allowed.join(', ')})"
          end
          Array(attributes)
        end

        def build_observation(patient_id, attribute, value, effective, encounter_id)
          FHIR::Observation.new(
            id: SecureRandom.uuid,
            status: "final",
            code: { coding: [ { system: Attributes::CODE_SYSTEM, code: attribute } ] },
            subject: { reference: "Patient/#{patient_id}" },
            encounter: encounter_id ? { reference: "Encounter/#{encounter_id}" } : nil,
            effectiveDateTime: effective&.to_s,
            **value_element(Attributes::DEFINITIONS.fetch(attribute)[:value], value)
          )
        end

        def value_element(kind, value)
          case kind
          when :percent
            { valueQuantity: { value: value, unit: "%", system: "http://unitsofmeasure.org", code: "%" } }
          else
            { valueCodeableConcept: { coding: [ { system: Attributes::VALUE_SYSTEM, code: value } ] } }
          end
        end

        def attribute_code(observation)
          observation.code.coding.first.code
        end

        def gather(store, patient_ids)
          Array(patient_ids).flat_map { |id| store[id.to_s] || [] }
        end

        # Patient-level temporal contract, "current as of the as-of date":
        # values dated after the as-of date never match; among the rest the
        # latest dated value wins, except that an UNDATED value beats all
        # dated ones — undated is the registration-current value. At most
        # one resource per group key; seed order breaks ties.
        def latest_per(resources, as_of_date, &group_key)
          resources
            .select { |r| (date = effective_date(r)).nil? || date <= as_of_date }
            .group_by(&group_key)
            .values
            .map { |group| group.max_by.with_index { |r, i| rank(r, i) } }
        end

        def rank(resource, index)
          date = effective_date(resource)
          [ date.nil? ? 1 : 0, date || EARLIEST, index ]
        end

        # Base contract: period is "current as of period end"; period nil
        # is "current now" — as of today.
        def as_of(period)
          period ? period.end : Date.today
        end

        def payer_code(coverage)
          coverage.type.coding.first.code
        end

        # A coverage whose period end predates the as-of date is
        # terminated; end is inclusive (start <= as-of <= end is current)
        # and nil end is open-ended.
        def terminated_by?(coverage, as_of_date)
          end_date = parse_date(coverage.period&.end)
          !end_date.nil? && end_date < as_of_date
        end

        EARLIEST = Date.new(0)
        private_constant :EARLIEST

        # Visit-level period contract: the visit occurred within the period
        # (inclusive of both endpoints); undated visits always match.
        def within_period?(observation, period)
          date = effective_date(observation)
          date.nil? || period.cover?(date)
        end

        def effective_date(resource)
          value =
            if resource.is_a?(FHIR::Coverage)
              resource.period&.start
            else
              resource.effectiveDateTime
            end
          parse_date(value)
        end

        # Fail closed on unparseable dates: silently treating a bad date as
        # undated would promote it to "always current" under the
        # undated-beats-dated rule.
        def parse_date(value)
          return nil if value.nil? || value.to_s.empty?

          Date.parse(value.to_s)
        rescue ArgumentError
          raise ArgumentError, "unparseable effective date: #{value.inspect}"
        end

        # Return copies so callers mutating a returned resource cannot
        # corrupt the store; tag provenance on the copies.
        def emit(resources)
          tag_source(resources.map { |r| r.class.new(r.to_hash) })
        end
      end
    end
  end
end
