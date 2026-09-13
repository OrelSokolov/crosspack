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
require_relative 'crossbuild/dep_installer'
require_relative 'crossbuild/distributor'
require_relative 'crossbuild/matrix'
require_relative 'crossbuild/builder'

module Crossbuild
  # Convenience wrapper: Crossbuild.build('crosspack.yml') runs every
  # host-buildable matrix entry and returns Builder::Result. target: builds
  # the entry distributing to that target only; deps: false skips the
  # pre-build dependency check/install pass. The manifest argument may be a
  # Config, a path to crosspack.yml or a ready BuildManifest.
  def self.build(manifest, entry_id: nil, target: nil, root: Dir.pwd, output_base: nil, version: nil,
                 deps: true, host_os: Platform.os, host_arch: Platform.arch)
    m = case manifest
        when BuildManifest then manifest
        when Crosspack::Config then manifest.build_manifest
        else Crosspack::Config.coerce(manifest, root: root).build_manifest
        end
    Builder.new(m, root: root, output_base: output_base, version: version, deps: deps,
                host_os: host_os, host_arch: host_arch).run(entry_id: entry_id, target: target)
  end
end
