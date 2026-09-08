# frozen_string_literal: true

module Crossbuild
  class Error < StandardError; end
end

require_relative 'crosspack'

require_relative 'crossbuild/version'
require_relative 'crossbuild/platform'
require_relative 'crossbuild/version_scheme'
require_relative 'crossbuild/build_manifest'
require_relative 'crossbuild/runner'
require_relative 'crossbuild/distributor'
require_relative 'crossbuild/matrix'
require_relative 'crossbuild/builder'

module Crossbuild
  # Convenience wrapper: Crossbuild.build('build.yaml') runs every
  # host-buildable matrix entry and returns Builder::Result.
  def self.build(manifest, entry_id: nil, root: Dir.pwd, output_base: nil, version: nil,
                 host_os: Platform.os, host_arch: Platform.arch)
    m = manifest.is_a?(BuildManifest) ? manifest : BuildManifest.load(manifest)
    Builder.new(m, root: root, output_base: output_base, version: version,
                host_os: host_os, host_arch: host_arch).run(entry_id: entry_id)
  end
end
