# frozen_string_literal: true

require "test_helper"
require "json"
require "digest"

# Evidence-station lint (rook#2 method / factory discipline): the CRS parity
# artifacts must trace to pinned evidence, and the chain must not rot.
#
# In-repo half, enforced here in CI:
#   - every spec extract's checksum matches evidence.lock.json (no silent edits
#     to extracted spec text — re-extract and re-lock instead);
#   - every dossier and parity feature cites evidence that resolves.
# External pins (the source PDF, the BGP M routines) live outside this repo;
# their checksums are recorded in the lockfile at extraction time and
# re-verified by the parity rig, which runs in the workspace checkout.
class EvidenceLockTest < Minitest::Test
  EVIDENCE_DIR = File.expand_path("../../docs/measures/evidence/crs-v25", __dir__)
  DOSSIER_DIR = File.expand_path("../../docs/measures", __dir__)
  FEATURES_DIR = File.expand_path("../../features/parity", __dir__)

  def lock
    @lock ||= JSON.parse(File.read(File.join(EVIDENCE_DIR, "evidence.lock.json")))
  end

  def test_lockfile_pins_all_evidence_classes
    assert lock["spec_source"]["sha256"].match?(/\A\h{64}\z/)
    assert_match(/25\.1 Build 98/, lock["m_source"]["bgp_version"],
                 "M evidence must be pinned to a named BGP build")
    refute_empty lock["m_source"]["routines"]
    refute_empty lock["extracts"]
  end

  def test_spec_extracts_match_locked_checksums
    lock["extracts"].each do |name, sha|
      path = File.join(EVIDENCE_DIR, "spec", name)
      assert File.exist?(path), "locked extract missing: #{name}"
      assert_equal sha, Digest::SHA256.file(path).hexdigest,
                   "#{name} differs from its locked checksum — evidence extracts are " \
                   "not hand-editable; re-extract from the source and re-lock"
    end
  end

  def test_no_unlocked_extracts
    on_disk = Dir[File.join(EVIDENCE_DIR, "spec", "*")].map { |p| File.basename(p) }
    assert_equal lock["extracts"].keys.sort, on_disk.sort,
                 "every extract must be pinned in evidence.lock.json"
  end

  def test_every_extract_declares_its_provenance
    lock["extracts"].each_key do |name|
      head = File.read(File.join(EVIDENCE_DIR, "spec", name)).lines.first(5).join
      assert_match(/EVIDENCE EXTRACT/, head, "#{name} missing provenance header")
      assert_includes head, lock["spec_source"]["sha256"],
                      "#{name} provenance must cite the locked source checksum"
    end
  end

  # Docs that are rook's OWN design (divergence-flagged), not encodings of the
  # CRS spec — they carry no spec citations by nature. Explicit allowlist so a
  # new dossier can't silently opt out.
  NON_DOSSIER_DOCS = %w[README.md fhir-mapping.md].freeze

  def test_dossiers_cite_resolvable_evidence
    dossiers = Dir[File.join(DOSSIER_DIR, "*.md")].reject { |p| NON_DOSSIER_DOCS.include?(File.basename(p)) }
    refute_empty dossiers
    dossiers.each do |dossier|
      body = File.read(dossier)
      cited_extracts = body.scan(%r{evidence/crs-v25/spec/([\w-]+\.txt)}).flatten.uniq
      refute_empty cited_extracts, "#{File.basename(dossier)} cites no spec evidence"
      cited_extracts.each do |name|
        assert lock["extracts"].key?(name),
               "#{File.basename(dossier)} cites unlocked evidence #{name}"
      end
      body.scan(/`(BGPX\w+\.m)`/).flatten.uniq.each do |routine|
        assert lock["m_source"]["routines"].key?(routine),
               "#{File.basename(dossier)} cites unpinned M routine #{routine}"
      end
    end
  end

  def test_parity_features_cite_resolvable_evidence_and_stay_loud
    features = Dir[File.join(FEATURES_DIR, "*.feature")]
    refute_empty features
    features.each do |feature|
      body = File.read(feature)
      name = File.basename(feature)

      body.scan(%r{evidence/crs-v25/spec/([\w-]+\.txt)}).flatten.uniq.tap do |extracts|
        refute_empty extracts, "#{name} must cite its spec evidence extract"
        extracts.each { |e| assert lock["extracts"].key?(e), "#{name} cites unlocked evidence #{e}" }
        assert_includes extracts, "populations.txt",
                        "#{name} must cite the population-base evidence its denominators build on"
      end

      body.scan(/(BGPX\w+\.m)/).flatten.uniq.tap do |routines|
        refute_empty routines, "#{name} must cite its M evidence routines"
        routines.each do |r|
          assert lock["m_source"]["routines"].key?(r), "#{name} cites unpinned M routine #{r}"
        end
      end

      dossier = body[%r{docs/measures/([\w-]+\.md)}, 1]
      assert dossier && File.exist?(File.join(DOSSIER_DIR, dossier)),
             "#{name} must cite an existing dossier"
      assert_match(%r{features/parity/VOCABULARY\.md}, body,
                   "#{name} must cite the seed vocabulary")

      # The rook driver exists (Rook::Crs) — parity features run in CI, so
      # the tag line carries @crs-v25 (version pin) and must NOT reintroduce
      # @wip, which would silently exclude them from the CI cucumber run.
      lines = body.lines.map(&:strip)
      feature_index = lines.index { |l| l.start_with?("Feature:") }
      refute_nil feature_index, "#{name} has no Feature: line"
      tag_line = lines[0...feature_index].reverse.find { |l| !l.empty? && !l.start_with?("#") }
      assert_includes tag_line.to_s.split, "@crs-v25",
                      "#{name}: @crs-v25 version tag must be on the Feature's tag line"
      refute_includes tag_line.to_s.split, "@wip",
                      "#{name}: parity features must not be excluded from CI via @wip"
    end
  end

  def test_steps_are_a_live_typed_driver
    steps = File.read(File.join(FEATURES_DIR, "step_definitions", "parity_steps.rb"))

    definitions = steps.scan(/^(?:Given|When|Then)\(/).size
    assert_operator definitions, :>, 15, "typed vocabulary unexpectedly small"

    # The driver landed with Rook::Crs — no step may regress to pending.
    refute_match(/\bpending\(/, steps.gsub(/^#.*$/, ""),
                 "parity steps must exercise the engine, not raise pending")

    # The vocabulary must stay typed: no catch-all fact parser. A regex that
    # swallows arbitrary English after has/had/is recreates the "parser, not a
    # vocabulary" hole — new facts get new steps instead.
    refute_match(/\(\.\+\)\$/, steps.gsub(/^#.*$/, ""),
                 "no step may end in an untyped catch-all capture")
  end
end
