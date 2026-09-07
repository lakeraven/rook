# frozen_string_literal: true

require "test_helper"

# Guards the two most expensive lies (product facts, 2026-09-07):
#
# 1. Rook is a Rails-FREE compute gem — it must never regrow a rails
#    dependency or advertise itself as a Rails engine. A host application
#    (rook-saas) supplies persistence and HTTP; this gem boots with plain
#    Ruby ("gem until it breaks" — reopening this is an ADR, not a drift).
# 2. The demo's GPRA packaging is UDS/eCQM-shaped logic under GPRA labels —
#    it must be impossible to mistake for the CRS-faithful engine
#    (Rook::Crs). The id-level fence: every demo GPRA measure id says so.
class GemHygieneTest < Minitest::Test
  def gemspec
    @gemspec ||= Gem::Specification.load(File.expand_path("../rook.gemspec", __dir__))
  end

  def test_gem_has_no_rails_dependency
    dependency_names = gemspec.dependencies.map(&:name)

    refute_includes dependency_names, "rails"
    refute_includes dependency_names, "railties"
    refute_includes dependency_names, "activerecord"
  end

  def test_gem_does_not_advertise_itself_as_a_rails_engine
    refute_match(/rails engine/i, gemspec.summary.to_s)
    refute_match(/rails engine/i, gemspec.description.to_s)
  end

  def test_packaged_files_are_lib_only
    assert(gemspec.files.none? { |f| f.start_with?("app/", "config/", "db/") },
           "a compute gem packages lib/ only — app/config/db belong to a host")
  end

  def test_demo_gpra_measures_are_fenced_by_id
    Rook::Demo::Report.gpra_measures.each do |measure|
      assert measure.id.start_with?("demo-"),
             "#{measure.id}: demo GPRA measures must carry the demo- id prefix so " \
             "UDS-shaped logic under GPRA labels cannot be mistaken for Rook::Crs " \
             "(crs-v25-* ids)"
    end
  end

  def test_demo_gpra_framework_is_labeled_a_preview
    assert_match(/demo preview/, Rook::Demo::Report.gpra.framework)
  end
end
