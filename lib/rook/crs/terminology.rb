# frozen_string_literal: true

module Rook
  module Crs
    # Code sets the CRS v25 trio measures reference, keyed by the BGP taxonomy
    # name each encodes (the join key to the published spec and the M source —
    # see docs/measures/). INTERIM: hand-seeded from the evidence extracts,
    # limited to what the trio needs; the taxonomy extraction pipeline
    # (#83–#85) replaces these with full ValueSets resolved through
    # Rook::ValueSetResolver. Wildcard families (ICD-10 "E10.*") match by
    # prefix, mirroring the spec's range notation.
    module Terminology
      ICD10 = "http://hl7.org/fhir/sid/icd-10-cm"
      SNOMED = "http://snomed.info/sct"
      LOINC = "http://loinc.org"
      CPT = "http://www.ama-assn.org/go/cpt"

      IHS_BENEFICIARY_EXT = "https://terminology.lakeraven.com/StructureDefinition/ihs-beneficiary-class"
      GPRA_COMMUNITY_EXT = "https://terminology.lakeraven.com/StructureDefinition/gpra-community"
      CLINIC_CODE_SYSTEM = "https://terminology.lakeraven.com/CodeSystem/ihs-clinic-code"
      MEASUREMENT_TYPE_SYSTEM = "https://terminology.lakeraven.com/CodeSystem/rpms-measurement-type"
      BH_EXAM_SYSTEM = "https://terminology.lakeraven.com/CodeSystem/bh-exam"
      BH_EXAM_RESULT_SYSTEM = "https://terminology.lakeraven.com/CodeSystem/bh-exam-result"
      BHS_PROBLEM_SYSTEM = "https://terminology.lakeraven.com/CodeSystem/bhs-problem-code"

      # [SURVEILLANCE DIABETES]: ICD-10 E10.* through E13.* (§2.1.2.5).
      DIABETES_ICD10_PREFIXES = %w[E10 E11 E12 E13].freeze

      # [BGP HYPERTENSION DXS]: ICD-10 I10 (§2.6.2.5).
      HYPERTENSION_ICD10 = %w[I10].freeze

      # [BGP HGBA1C LOINC CODES] (§2.1.2.5).
      A1C_LOINC = %w[17855-8 17856-6 41995-2 4547-6 4548-4 4549-2 71875-9 96595-4].freeze

      # [BGP HGBA1C CPTS] band codes and their numerator meanings (§2.1.2.5).
      A1C_CPT_POOR = %w[3046F].freeze              # > 9
      A1C_CPT_GOOD = %w[3044F 3051F].freeze        # counts in < 8
      A1C_CPTS = %w[83036 83037 3044F 3045F 3046F 3047F 3051F 3052F].freeze

      # [BGP ESRD PMS DXS] — trio subset; full set arrives with #83.
      ESRD_ICD10 = %w[I12.0 I13.11 I13.2 N18.5 N18.6 N19. Z48.22 Z91.15 Z94.0 Z99.2].freeze
      ESRD_ICD10_PREFIXES = %w[Z49].freeze

      # Pregnancy status (Reproductive Factors mapping — see fhir-mapping.md).
      PREGNANCY_STATUS_LOINC = "82810-3"
      PREGNANT_SNOMED = "77386006"

      # [BGP DEPRESSION SCRN DXS]: ICD-10 Z13.3* (§2.5.4.5).
      DEPRESSION_SCREEN_ICD10_PREFIXES = %w[Z13.3].freeze

      # [BGP DEPRESSION SCREEN CPTS] (§2.5.4.5).
      DEPRESSION_SCREEN_CPTS = %w[1220F 3725F G0444].freeze

      # [BGP MOOD DISORDERS] — trio subset of the family list (§2.5.4.5);
      # full enumeration arrives with #83.
      MOOD_DISORDER_ICD10_PREFIXES = %w[F30 F31 F32 F33 F34 F39 F43.21 F43.23].freeze

      # PHQ-9 total score LOINC; RPMS measurement-type codes per fhir-mapping.
      PHQ9_LOINC = "44261-6"
      DEPRESSION_MEASUREMENT_TYPES = %w[PHQ9 PHQT EPDS].freeze

      module_function

      def diabetes_code?(system, code)
        system == ICD10 && DIABETES_ICD10_PREFIXES.any? { |p| code.to_s.start_with?(p) }
      end

      def hypertension_code?(system, code)
        system == ICD10 && HYPERTENSION_ICD10.include?(code)
      end

      def esrd_code?(system, code)
        system == ICD10 &&
          (ESRD_ICD10.include?(code) || ESRD_ICD10_PREFIXES.any? { |p| code.to_s.start_with?(p) })
      end

      def mood_disorder_code?(system, code)
        system == ICD10 && MOOD_DISORDER_ICD10_PREFIXES.any? { |p| code.to_s.start_with?(p) }
      end

      def depression_screen_pov?(system, code)
        system == ICD10 && DEPRESSION_SCREEN_ICD10_PREFIXES.any? { |p| code.to_s.start_with?(p) }
      end

      def a1c_lab_code?(system, code)
        system == LOINC && A1C_LOINC.include?(code)
      end

      def depression_measurement?(system, code)
        (system == LOINC && code == PHQ9_LOINC) ||
          (system == MEASUREMENT_TYPE_SYSTEM && DEPRESSION_MEASUREMENT_TYPES.include?(code))
      end
    end
  end
end
