# frozen_string_literal: true

require "rook/demo/measures/diabetes_hba1c_poor_control"

module Rook
  module Demo
    module Measures
      module Gpra
        # DEMO / REFERENCE ONLY — see Rook::Demo.
        #
        # IHS GPRA / CRS national clinical measure: Diabetes: Poor Glycemic
        # Control (Hemoglobin A1c > 9.0%). Reuses the exact HbA1c computation
        # behind the UDS Table 6B measure — the underlying clinical logic is
        # shared; only the GPRA labeling/packaging differs.
        #
        # Demo approximation: the real GPRA denominator is the "active adult
        # diabetic" register (age 18+, no upper bound), whereas UDS Table 6B
        # caps at age 75. This demo reuses the 18-75 denominator for both views
        # so the shared population lines up; a production engine would apply the
        # GPRA-specific denominator here.
        class DiabetesPoorGlycemicControl < DiabetesHbA1cPoorControl
          def id
            "demo-gpra-diabetes-poor-glycemic-control"
          end

          def title
            "Diabetes: Poor Glycemic Control (A1c > 9.0%)"
          end

          def interpretation
            "Lower is better. Numerator = poor glycemic control or no A1c in the period."
          end
        end
      end
    end
  end
end
