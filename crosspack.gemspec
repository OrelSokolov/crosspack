# frozen_string_literal: true

require_relative 'lib/crosspack/version'

Gem::Specification.new do |spec|
  spec.name = 'crosspack'
  spec.version = Crosspack::VERSION
  spec.authors = ['Oleg Orlov']
  spec.email = ['orelcokolov@gmail.com']

  spec.summary = 'Cross-platform build orchestrator and native package builder (deb/rpm/PKGBUILD/winget/cask)'
  spec.description = 'Two cooperating commands: crossbuild runs the build steps of a project ' \
                     'from a build.yaml matrix and fans the produced artifacts out into the ' \
                     'per-target builds/ tree; crosspack turns that tree into native packages, ' \
                     'driven by a cross-distro deps.yaml. Both share the same target vocabulary ' \
                     'so the trees never drift apart.'
  spec.homepage = 'https://github.com/OrelSokolov/crosspack'
  spec.license = 'Nonstandard'

  spec.metadata = {
    'source_code_uri' => 'https://github.com/OrelSokolov/crosspack',
    'changelog_uri' => 'https://github.com/OrelSokolov/crosspack/blob/main/CHANGELOG.md'
  }

  spec.required_ruby_version = '>= 3.2.0'

  spec.files = Dir['lib/**/*.rb'] + ['exe/crosspack', 'exe/crossbuild', 'README.md', 'CHANGELOG.md', 'LICENSE']
  spec.bindir = 'exe'
  spec.executables = ['crosspack', 'crossbuild']
  spec.require_paths = ['lib']
end
