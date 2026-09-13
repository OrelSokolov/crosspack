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

  def test_render_lists_deps_resolution_for_host
    m = load_manifest(<<~YAML)
      name: myapp
      deps:
        imagemagick:
          hosts:
            ubuntu:
              verify: dpkg -s imagemagick
              install: sudo apt-get install -y imagemagick
      matrix:
        - build: linux/amd64
          steps: [make]
    YAML
    out = Crossbuild::Matrix.new(m, host_os: :linux, host_arch: :x86_64,
                                 selectors: ['ubuntu', 'linux', '*']).render
    assert_includes out, 'deps on this host'
    assert_includes out, '⚙ imagemagick'
    assert_includes out, 'ubuntu -> sudo apt-get install -y imagemagick'
  end

  def test_render_flags_verify_only_dep_rule
    m = load_manifest(<<~YAML)
      name: myapp
      deps:
        curl:
          hosts:
            "*": {verify: curl --version}
      matrix:
        - build: linux/amd64
          steps: [make]
    YAML
    out = Crossbuild::Matrix.new(m, host_os: :linux, host_arch: :x86_64,
                                 selectors: ['linux', '*']).render
    assert_includes out, '⚙ curl'
    assert_includes out, '(verify only: curl --version)'
  end

  def test_render_flags_dep_without_rule_for_host
    m = load_manifest(<<~YAML)
      name: myapp
      deps:
        imagemagick:
          hosts:
            darwin: {install: brew install imagemagick}
      matrix:
        - build: linux/amd64
          steps: [make]
    YAML
    out = Crossbuild::Matrix.new(m, host_os: :linux, host_arch: :x86_64,
                                 selectors: ['linux', '*']).render
    assert_includes out, '✗ imagemagick'
    assert_includes out, 'no rule for this host'
    assert_includes out, 'described: darwin'
  end

  def test_render_without_deps_omits_section
    out = Crossbuild::Matrix.new(manifest, host_os: :linux, host_arch: :x86_64).render
    refute_includes out, 'deps on this host'
  end
end
