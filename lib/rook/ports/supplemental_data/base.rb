# frozen_string_literal: true

require "fhir_models"

require "rook/source_descriptor"
require "rook/ports/supplemental_data/attributes"
require "rook/ports/supplemental_data/payer_category"

module Rook
  module Ports
    module SupplementalData
      # Abstract per-EHR-platform reader interface for UDS supplemental
      # data: patient/visit-level attributes that the platform's FHIR API
      # does not expose, living in its registration/eligibility/billing
      # internals (income as % FPL, sliding-fee class, housing status,
      # agricultural-worker status, veteran status, language barrier, visit
      # service category) — plus payer-category coverage records.
      #
      # Rook owns this port; per-EHR implementations live in the
      # integrations layer and conformance-test themselves against
      # Conformance. Concrete readers reach into each platform's non-FHIR
      # access path internally — this interface stays transport-agnostic;
      # consumers see only FHIR. Attribute reads return raw fhir_models
      # FHIR::Observation resources normalized to the Attributes vocabulary
      # (one internal code system, so downstream SQL-on-FHIR sees a single
      # vocabulary regardless of source EHR); #patient_coverages returns
      # FHIR::Coverage resources typed from the PayerCategory vocabulary.
      # Everything returned is tagged with source provenance (+meta.source+
      # from #source_descriptor — see #tag_source).
      #
      # == Patient IDs
      #
      # Every read accepts +patient_ids+ as a single String or an
      # Array<String>.
      #
      # == Period semantics
      #
      # +period:+ is a Range<Date> with an *inclusive* end. For
      # patient-level, registration-derived data (patient attributes and
      # coverages) it means "current as of period end": the latest dated
      # value effective on or before the period's end date wins, and an
      # UNDATED value beats all dated ones — undated is the
      # registration-current value. Values dated after the as-of date
      # never match. At most one value per attribute per patient per read;
      # coverages are latest-wins per (patient, payer category) instead —
      # see #patient_coverages. +period: nil+ means "current now" (as of
      # today; future-dated values are excluded). For visit-level
      # attributes the period selects visits occurring within the period
      # (inclusive of both endpoints); an UNDATED visit attribute matches
      # only +period: nil+ reads — fail-closed, because a visit without a
      # date matching every bounded period would double-count across
      # reporting periods. +period: nil+ returns all visits, undated and
      # future-dated included.
      #
      # "Undated" always means the date element is ABSENT on the returned
      # resource (no +effectiveDateTime+ / +period.start+) — an
      # implementation must never stamp a synthetic date (today, epoch,
      # period start) in place of a missing one: under undated-beats-dated
      # that would silently promote or demote the value.
      #
      # == Batching and failure
      #
      # Callers with large cohorts should batch +patient_ids+ themselves;
      # implementations define (and document) their own batch limits and
      # may reject oversized requests. Partial-failure contract: a read
      # either returns complete results for every requested patient or
      # raises — implementations must never silently skip patients they
      # failed to read.
      #
      # Read-only by design: supplemental data substantiates reporting, it
      # is never written back to the source EHR.
      class Base
        # Descriptor identifying this source for provenance and audit.
        # @return [Rook::SourceDescriptor]
        def source_descriptor
          raise NotImplementedError, "#{self.class}#source_descriptor not implemented"
        end

        # Patient-level UDS supplemental attributes (Attributes::PATIENT_LEVEL).
        # @param patient_ids [String, Array<String>] patient ID(s) (cohort or single)
        # @param period [Range<Date>, nil] current as of period end (inclusive); nil = current
        # @param attributes [Array<String>, nil] subset of Attributes::PATIENT_LEVEL
        #   codes to read; nil = all
        # @return [Array<FHIR::Observation>] coded from Attributes::CODE_SYSTEM
        def patient_attributes(patient_ids, period: nil, attributes: nil)
          raise NotImplementedError, "#{self.class}#patient_attributes not implemented"
        end

        # Visit-level UDS supplemental attributes (Attributes::VISIT_LEVEL),
        # each carrying an +encounter+ reference.
        # @param patient_ids [String, Array<String>] patient ID(s) (cohort or single)
        # @param period [Range<Date>, nil] visits within the period (inclusive); nil = all
        # @param attributes [Array<String>, nil] subset of Attributes::VISIT_LEVEL
        #   codes to read; nil = all
        # @return [Array<FHIR::Observation>] coded from Attributes::CODE_SYSTEM
        def visit_attributes(patient_ids, period: nil, attributes: nil)
          raise NotImplementedError, "#{self.class}#visit_attributes not implemented"
        end

        # Payer-category coverage from eligibility/billing internals,
        # normalized as FHIR::Coverage with +type.coding+ from
        # PayerCategory::CODE_SYSTEM (medicaid, medicare, private,
        # uninsured, other-public) and +beneficiary+ referencing the
        # patient.
        #
        # Returns ALL currently-effective coverages per patient — never a
        # collapse to one per beneficiary: dual-eligibles carry Medicare
        # AND Medicaid Coverages simultaneously (UDS Table 4 line 9a).
        # Temporal latest-wins applies per (beneficiary, payer category).
        # "Currently effective" at the as-of date (period end, or today
        # when +period+ is nil) means status active and period.start <=
        # as-of <= period.end, with nil start = registration-current and
        # nil end = open-ended.
        # @param patient_ids [String, Array<String>] patient ID(s) (cohort or single)
        # @param period [Range<Date>, nil] current as of period end (inclusive); nil = current
        # @return [Array<FHIR::Coverage>] provenance-tagged coverage resources
        def patient_coverages(patient_ids, period: nil)
          raise NotImplementedError, "#{self.class}#patient_coverages not implemented"
        end

        private

        # Stamp source provenance onto returned resources so downstream
        # consumers keep source-level lineage on the resource itself.
        # Concrete readers call this on every batch they return.
        #
        # @param resources [Array<FHIR::Model>]
        # @return [Array<FHIR::Model>] the same resources, tagged
        def tag_source(resources)
          resources.each do |resource|
            resource.meta ||= FHIR::Meta.new
            resource.meta.source = source_descriptor.uri
          end
        end
      end
    end
  end
end
