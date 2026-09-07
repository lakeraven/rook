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

  def test_dossiers_cite_resolvable_evidence
    dossiers = Dir[File.join(DOSSIER_DIR, "*.md")].reject { |p| p.end_with?("README.md") }
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
      extract = body[%r{evidence/crs-v25/spec/([\w-]+\.txt)}, 1]
      refute_nil extract, "#{name} must cite its spec evidence extract"
      assert lock["extracts"].key?(extract), "#{name} cites unlocked evidence #{extract}"
      dossier = body[%r{docs/measures/([\w-]+\.md)}, 1]
      assert dossier && File.exist?(File.join(DOSSIER_DIR, dossier)),
             "#{name} must cite an existing dossier"
      # Pending-engine features must be loud (@wip keeps CI green by exclusion,
      # never by a silently-passing stub) — drop the tags only with a driver.
      assert_match(/@wip @crs-v25 @pending-engine/, body,
                   "#{name} must carry the pending tags until a driver exists")
    end
  end
end
