# frozen_string_literal: true

require_relative 'test_helper'

class DistributorTest < Minitest::Test
  include BuildManifestHelper

  def setup
    @dir = Dir.mktmpdir('crossbuild-dist')
    FileUtils.mkdir_p(File.join(@dir, 'build', 'bin'))
    %w[myapp helper model.onnx stale.tmp].each do |f|
      FileUtils.touch(File.join(@dir, 'build', 'bin', f))
    end
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def entry(yaml)
    body = yaml.lines.map { |l| "  #{l}" }.join
    load_manifest("name: app\nmatrix:\n#{body}\n").entries.first
  end

  def test_symlinks_artifacts_into_per_target_dirs
    e = entry(<<~YAML)
      - build: linux/amd64
        steps: ['true']
        artifacts:
          from: build/bin
          include: [myapp, helper, model.onnx]
          to: [ubuntu-22.04, debian-12]
    YAML
    dirs = Crossbuild::Distributor.new(root: @dir, output_base: 'builds').distribute(e, host_arch: :x86_64)

    assert_equal [%w[ubuntu 22.04 amd64], %w[debian 12 amd64]],
                 dirs.map { |d| d.sub("#{@dir}/builds/", '').split('/') }
    %w[ubuntu/22.04/amd64 debian/12/amd64].each do |rel|
      %w[myapp helper model.onnx].each do |f|
        link = File.join(@dir, 'builds', rel, f)
        assert File.symlink?(link), "expected symlink at #{link}"
        assert File.exist?(link), "dangling symlink at #{link}"
      end
      refute File.exist?(File.join(@dir, 'builds', rel, 'stale.tmp'))
    end
  end

  def test_copy_mode_copies_real_files
    e = entry(<<~YAML)
      - build: linux/amd64
        steps: ['true']
        artifacts: { from: build/bin, include: [myapp], to: [debian-12], mode: copy }
    YAML
    Crossbuild::Distributor.new(root: @dir, output_base: 'builds').distribute(e, host_arch: :x86_64)

    placed = File.join(@dir, 'builds', 'debian', '12', 'amd64', 'myapp')
    refute File.symlink?(placed)
    assert File.exist?(placed)
  end

  def test_replaces_existing_links_on_rerun
    e = entry(<<~YAML)
      - build: linux/amd64
        steps: ['true']
        artifacts: { from: build/bin, include: [myapp], to: [debian-12] }
    YAML
    dist = Crossbuild::Distributor.new(root: @dir, output_base: 'builds')
    dist.distribute(e, host_arch: :x86_64)
    dist.distribute(e, host_arch: :x86_64) # must not fail with EEXIST

    assert File.exist?(File.join(@dir, 'builds', 'debian', '12', 'amd64', 'myapp'))
  end

  def test_arch_comes_from_entry_not_host
    e = entry(<<~YAML)
      - build: darwin/arm64
        steps: ['true']
        artifacts: { from: build/bin, include: [myapp], to: [macos] }
    YAML
    Crossbuild::Distributor.new(root: @dir, output_base: 'builds').distribute(e, host_arch: :x86_64)

    # macos (cask layout) spells the arch aarch64, matching crosspack's
    # Target#package_arch for non-deb formats.
    assert File.directory?(File.join(@dir, 'builds', 'macos', 'aarch64'))
  end

  def test_missing_from_dir_raises
    e = entry(<<~YAML)
      - build: linux/amd64
        steps: ['true']
        artifacts: { from: nowhere, include: [myapp], to: [debian-12] }
    YAML
    error = assert_raises(Crossbuild::Error) do
      Crossbuild::Distributor.new(root: @dir, output_base: 'builds').distribute(e, host_arch: :x86_64)
    end
    assert_includes error.message, 'nowhere'
  end

  def test_pattern_matching_nothing_raises
    e = entry(<<~YAML)
      - build: linux/amd64
        steps: ['true']
        artifacts: { from: build/bin, include: ["*.exe"], to: [debian-12] }
    YAML
    error = assert_raises(Crossbuild::Error) do
      Crossbuild::Distributor.new(root: @dir, output_base: 'builds').distribute(e, host_arch: :x86_64)
    end
    assert_includes error.message, '*.exe'
  end

  def test_directory_artifact_is_distributed_whole
    app_bundle = File.join(@dir, 'build', 'bin', 'MyApp.app')
    FileUtils.mkdir_p(File.join(app_bundle, 'Contents', 'MacOS'))
    FileUtils.touch(File.join(app_bundle, 'Contents', 'MacOS', 'MyApp'))

    e = entry(<<~YAML)
      - build: darwin/arm64
        steps: ['true']
        artifacts: { from: build/bin, include: ["*.app"], to: [macos] }
    YAML
    Crossbuild::Distributor.new(root: @dir, output_base: 'builds').distribute(e, host_arch: :arm64)

    assert File.directory?(File.join(@dir, 'builds', 'macos', 'aarch64', 'MyApp.app'))
  end
end
