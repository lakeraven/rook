# frozen_string_literal: true

require "rook/demo/measures/controlling_high_blood_pressure"

module Rook
  module Demo
    module Measures
      module Gpra
        # DEMO / REFERENCE ONLY — see Rook::Demo.
        #
        # IHS GPRA / CRS national clinical measure: Controlling High Blood
        # Pressure (< 140/90). Same clinical basis (NQF 0018) as the UDS Table 6B
        # measure, so this reuses the exact BP computation and only re-labels it
        # for the GPRA view. The 18-85 hypertension denominator matches between
        # the GPRA and UDS specs, so no denominator override is needed here.
        class ControllingHighBloodPressure < Measures::ControllingHighBloodPressure
          def id
            "gpra-controlling-high-blood-pressure"
          end

          def title
            "Controlling High Blood Pressure (< 140/90)"
          end
        end
      end
    end
  end
end
