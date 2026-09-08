# frozen_string_literal: true

require_relative 'test_helper'

class BuildMatrixTest < Minitest::Test
  include BuildManifestHelper

  def manifest
    load_manifest(<<~YAML)
      name: myapp
      matrix:
        - build: linux/amd64
          steps: [one, two]
          artifacts: { from: build/bin, to: [ubuntu-24.04, debian-12] }
        - build: windows/amd64
          steps: [three]
          artifacts: { from: build/bin, include: [myapp.exe], to: [windows-11.0] }
    YAML
  end

  def test_render_lists_entries_and_host_match
    out = Crossbuild::Matrix.new(manifest, host_os: :linux, host_arch: :x86_64).render
    assert_includes out, 'host: linux/amd64'
    assert_includes out, '✓ linux/amd64'
    assert_includes out, 'buildable here'
    assert_includes out, '2 steps'
    assert_includes out, 'build/bin -> ubuntu-24.04, debian-12'
    assert_includes out, '· windows/amd64'
    assert_includes out, 'needs windows/amd64'
    assert_includes out, '1 of 2 entries build here: linux/amd64'
  end

  def test_render_when_nothing_matches_host
    out = Crossbuild::Matrix.new(manifest, host_os: :darwin, host_arch: :arm64).render
    assert_includes out, 'Nothing can build on this host'
  end
end
