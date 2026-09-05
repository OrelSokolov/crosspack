# frozen_string_literal: true

require_relative 'crosspack/version'
require_relative 'crosspack/target'
require_relative 'crosspack/manifest'
require_relative 'crosspack/package_manifest'
require_relative 'crosspack/resolver'
require_relative 'crosspack/matrix'
require_relative 'crosspack/builds'
require_relative 'crosspack/packer'
require_relative 'crosspack/builders/deb'
require_relative 'crosspack/builders/rpm'
require_relative 'crosspack/builders/pkgbuild'
require_relative 'crosspack/builders/wix'
require_relative 'crosspack/builders/app_dir'

module Crosspack
  BUILDERS = {
    deb: Builders::Deb,
    rpm: Builders::Rpm,
    pkgbuild: Builders::Pkgbuild,
    winget: Builders::Wix,
    cask: Builders::AppDir
  }.freeze

  # Shared options for all builders, expressed once so every format stages
  # the same file tree:
  #   files:       { source_path => destination_inside_package (no leading /) }
  #   symlinks:    { link_path_inside_package => link_target }
  #   executables: [destination paths to chmod 0755]
  class BuildError < StandardError; end

  # Convenience wrapper: Crosspack.pack(manifest: 'package.yaml',
  # deps: 'deps.yaml', target: Target.parse('debian-12'), version: '1.0-1')
  def self.pack(**kwargs)
    Packer.pack(**kwargs)
  end
end
