# frozen_string_literal: true

require_relative 'lib/crosspack/version'

Gem::Specification.new do |spec|
  spec.name = 'crosspack'
  spec.version = Crosspack::VERSION
  spec.authors = ['Oleg Orlov']
  spec.email = ['orelcokolov@gmail.com']

  spec.summary = 'Native package builder (deb/rpm/PKGBUILD) driven by a cross-distro deps.yaml'
  spec.description = 'Reads deps.yaml where root keys are canonical dependency names and ' \
                     'targets list concrete packages per distro family/version, validates the ' \
                     'schema, and builds native packages from an already compiled binary tree.'
  spec.homepage = 'https://github.com/OrelSokolov/crosspack'
  spec.license = 'Proprietary'

  spec.required_ruby_version = '>= 2.6.0'

  spec.files = Dir['lib/**/*.rb'] + ['exe/crosspack', 'README.md']
  spec.bindir = 'exe'
  spec.executables = ['crosspack']
  spec.require_paths = ['lib']
end
