# frozen_string_literal: true

# DEMO / REFERENCE ONLY. Minimal cucumber bootstrap for the Rook::Demo user
# story. Plain-Ruby gem (no Rails) — load the lib path and the demo module
# directly; no rspec-expectations dependency (steps use plain assertions).
$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)

require "rook/demo"
