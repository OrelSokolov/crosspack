# frozen_string_literal: true

require_relative 'lib/crosspack/version'

Gem::Specification.new do |spec|
  spec.name = 'crosspack'
  spec.version = Crosspack::VERSION
  spec.authors = ['Oleg Orlov']
  spec.email = ['orelcokolov@gmail.com']

  spec.summary = 'Painless packaging for any platform'
  spec.description = 'The build matrix in crosspack.yml helps you to build and deliver your program ' \
                     'without pain — one config drives a staged pipeline (deps → build → pack) that ' \
                     'produces native packages for every platform: deb, rpm, PKGBUILD, winget and cask.'
  spec.homepage = 'https://github.com/OrelSokolov/crosspack'
  spec.license = 'Nonstandard'

  spec.metadata = {
    'source_code_uri' => 'https://github.com/OrelSokolov/crosspack',
    'changelog_uri' => 'https://github.com/OrelSokolov/crosspack/blob/main/CHANGELOG.md'
  }

  spec.required_ruby_version = '>= 3.2.0'

  spec.files = Dir['lib/**/*.rb'] + ['exe/crosspack', 'README.md', 'CHANGELOG.md', 'LICENSE', 'logo.png']
  spec.bindir = 'exe'
  spec.executables = ['crosspack']
  spec.require_paths = ['lib']

  spec.add_dependency 'colorize', '~> 1.0'
end
