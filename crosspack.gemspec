# frozen_string_literal: true

require_relative 'lib/crosspack/version'

Gem::Specification.new do |spec|
  spec.name = 'crosspack'
  spec.version = Crosspack::VERSION
  spec.authors = ['Oleg Orlov']
  spec.email = ['orelcokolov@gmail.com']

  spec.summary = 'Staged cross-platform pipeline: deps → build → pack native packages (deb/rpm/PKGBUILD/winget/cask)'
  spec.description = 'One command, one target vocabulary: crosspack deps <target> verifies and ' \
                     'installs the build host dependencies, crosspack build <target> runs the ' \
                     'build.yaml matrix entry and fans artifacts into builds/, crosspack pack ' \
                     '<target> turns that tree into a native package. Stages are gated — no ' \
                     'packing before building — and keyed by the same target strings throughout.'
  spec.homepage = 'https://github.com/OrelSokolov/crosspack'
  spec.license = 'Nonstandard'

  spec.metadata = {
    'source_code_uri' => 'https://github.com/OrelSokolov/crosspack',
    'changelog_uri' => 'https://github.com/OrelSokolov/crosspack/blob/main/CHANGELOG.md'
  }

  spec.required_ruby_version = '>= 3.2.0'

  spec.files = Dir['lib/**/*.rb'] + ['exe/crosspack', 'README.md', 'CHANGELOG.md', 'LICENSE']
  spec.bindir = 'exe'
  spec.executables = ['crosspack']
  spec.require_paths = ['lib']
end
