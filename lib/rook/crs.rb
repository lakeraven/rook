# frozen_string_literal: true

# Rook::Crs — the CRS-faithful measure engine (rook#2).
#
# Encodes IHS CRS v25 GPRA measure logic from pinned evidence (the published
# measure definitions + the BGP v25.1 M source — docs/measures/) over FHIR
# resources shaped per docs/measures/fhir-mapping.md. Verified by the parity
# features (features/parity/), which the #99 harness also runs against real
# CRS. Deliberately DISTINCT from the UDS/eCQM-shaped Rook::Demo measures:
# same clinical topics, different programs, different logic — see the
# divergence flags in each dossier.
require "rook/crs/terminology"
require "rook/crs/population"
require "rook/crs/measures"
require "rook/crs/national_gpra_report"

module Rook
  module Crs
  end
end
