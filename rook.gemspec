# frozen_string_literal: true

require_relative "lib/rook/version"

Gem::Specification.new do |spec|
  spec.name        = "rook"
  spec.version     = Rook::VERSION
  spec.authors     = [ "Lakeraven" ]
  spec.email       = [ "eng@lakeraven.com" ]
  spec.homepage    = "https://github.com/lakeraven/rook"
  spec.summary     = "Population health, quality measures, and clinical reporting compute library"
  spec.description = "Rails-free, EHR-agnostic Ruby library for quality-measure computation, " \
                     "population health reporting, and CRS-faithful GPRA measure logic " \
                     "(IHS/tribal/FQHC programs). FHIR R4 data input via NDJSON/Bulk Data ingest, " \
                     "FHIR MeasureReport output. A host application supplies persistence and HTTP; " \
                     "this gem is the engine-neutral core and boots with plain Ruby."
  spec.license     = "MIT"
  spec.metadata    = {
    "homepage_uri"    => "https://github.com/lakeraven/rook",
    "source_code_uri" => "https://github.com/lakeraven/rook"
  }

  spec.required_ruby_version = ">= 3.4.0"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["lib/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  spec.add_dependency "fhir_models", "~> 4.3"
end
