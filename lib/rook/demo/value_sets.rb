# frozen_string_literal: true

require "rook/in_memory_value_set_resolver"

module Rook
  module Demo
    # DEMO / REFERENCE ONLY — see Rook::Demo.
    #
    # Canonical value-set URLs the demo measures reference, plus an in-memory
    # Rook::ValueSetResolver seeded with the codes as authored in the synthetic
    # fixture. Measures never see these code lists directly — they expand the
    # URLs through the resolver, so a terminology-server-backed resolver
    # (rook#63) can drop in behind the same URLs.
    module ValueSets
      BASE = "https://rook.lakeraven.com/fhir/ValueSet"

      DIABETES = "#{BASE}/demo-diabetes"
      HYPERTENSION = "#{BASE}/demo-hypertension"
      HBA1C_LABORATORY_TEST = "#{BASE}/demo-hba1c-laboratory-test"
      BLOOD_PRESSURE_PANEL = "#{BASE}/demo-blood-pressure-panel"
      SYSTOLIC_BLOOD_PRESSURE = "#{BASE}/demo-systolic-blood-pressure"
      DIASTOLIC_BLOOD_PRESSURE = "#{BASE}/demo-diastolic-blood-pressure"
      DEPRESSION_SCREENING_INSTRUMENT = "#{BASE}/demo-depression-screening-instrument"

      CODES = {
        # Diabetes: ICD-10-CM E11.9 + SNOMED 44054006 (as authored in the fixture).
        DIABETES => %w[E11.9 44054006],
        # Hypertension: ICD-10-CM I10 + SNOMED 38341003.
        HYPERTENSION => %w[I10 38341003],
        # LOINC observation codes.
        HBA1C_LABORATORY_TEST => %w[4548-4],
        BLOOD_PRESSURE_PANEL => %w[85354-9],
        SYSTOLIC_BLOOD_PRESSURE => %w[8480-6],
        DIASTOLIC_BLOOD_PRESSURE => %w[8462-4],
        DEPRESSION_SCREENING_INSTRUMENT => %w[44261-6]
      }.freeze

      def self.resolver
        @resolver ||= InMemoryValueSetResolver.new(CODES)
      end
    end
  end
end
