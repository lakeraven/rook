# frozen_string_literal: true

require_relative "lib/rook/version"

Gem::Specification.new do |spec|
  spec.name        = "rook"
  spec.version     = Rook::VERSION
  spec.authors     = [ "Lakeraven" ]
  spec.email       = [ "eng@lakeraven.com" ]
  spec.homepage    = "https://github.com/lakeraven/rook"
  spec.summary     = "Population health, quality measures, and clinical reporting engine"
  spec.description = "EHR-agnostic Rails engine for CQL-based quality measure execution, " \
                     "population health dashboards, and clinical reporting (GPRA, dHEDIS, eCQM). " \
                     "FHIR R4 data input, DEQM output."
  spec.license     = "MIT"
  spec.metadata    = {
    "homepage_uri"    => "https://github.com/lakeraven/rook",
    "source_code_uri" => "https://github.com/lakeraven/rook"
  }

  spec.required_ruby_version = ">= 3.4.0"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  spec.add_dependency "fhir_models", "~> 4.2"
  spec.add_dependency "rails", "~> 8.1"
end
