# frozen_string_literal: true

require_relative 'test_helper'

class BuilderTest < Minitest::Test
  include BuildManifestHelper

  def setup
    @dir = Dir.mktmpdir('crossbuild-build')
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def write_manifest(yaml)
    file = File.join(@dir, 'build.yaml')
    File.write(file, yaml)
    Crossbuild::BuildManifest.load(file)
  end

  def test_end_to_end_steps_then_distribution
    m = write_manifest(<<~YAML)
      name: app
      version: '1.0.0'
      matrix:
        - build: #{host_platform}
          steps:
            - mkdir -p build/bin
            - echo {{name}}-{{version}} > build/bin/app
          artifacts:
            from: build/bin
            include: [app]
            to: [debian-12, ubuntu-24.04]
    YAML
    result = nil
    capturing_stdout do
      result = Crossbuild::Builder.new(m, root: @dir, host_os: host_os, host_arch: host_arch).run
    end

    assert_equal '1.0.0', result.version
    assert_equal 1, result.entries.size
    stamp = File.join(@dir, 'builds', 'debian', '12', host_deb_arch, 'app')
    assert File.exist?(stamp), "expected #{stamp}"
    assert_equal "app-1.0.0\n", File.read(stamp)
    assert File.exist?(File.join(@dir, 'builds', 'ubuntu', '24.04', host_deb_arch, 'app'))
  end

  def test_version_override
    m = write_manifest(<<~YAML)
      name: app
      version: calver
      matrix:
        - build: #{host_platform}
          steps: [mkdir -p build/bin]
          artifacts: { from: build/bin, include: [marker], to: [debian-12] }
    YAML
    FileUtils.mkdir_p(File.join(@dir, 'build', 'bin'))
    FileUtils.touch(File.join(@dir, 'build', 'bin', 'marker'))

    result = nil
    capturing_stdout do
      result = Crossbuild::Builder.new(m, root: @dir, version: '9.9.9',
                                       host_os: host_os, host_arch: host_arch).run
    end
    assert_equal '9.9.9', result.version
  end

  def test_explicit_entry_id_may_target_foreign_platform
    m = write_manifest(<<~YAML)
      name: app
      version: '1.0'
      matrix:
        - id: foreign
          build: windows/amd64
          steps: [echo hello > proof.txt]
    YAML
    capturing_stdout do
      Crossbuild::Builder.new(m, root: @dir, host_os: :linux, host_arch: :x86_64).run(entry_id: 'foreign')
    end
    assert File.exist?(File.join(@dir, 'proof.txt'))
  end

  def test_unknown_entry_id_raises
    m = write_manifest(<<~YAML)
      name: app
      matrix:
        - build: #{host_platform}
          steps: ['true']
    YAML
    error = assert_raises(Crossbuild::Error) do
      capturing_stdout do
        Crossbuild::Builder.new(m, root: @dir, host_os: host_os, host_arch: host_arch).run(entry_id: 'nope')
      end
    end
    assert_includes error.message, 'unknown matrix entry "nope"'
  end

  def test_nothing_buildable_on_host_raises
    m = write_manifest(<<~YAML)
      name: app
      matrix:
        - build: windows/amd64
          steps: ['true']
    YAML
    skip 'host is windows' if host_os == :windows

    error = assert_raises(Crossbuild::Error) do
      capturing_stdout do
        Crossbuild::Builder.new(m, root: @dir, host_os: host_os, host_arch: host_arch).run
      end
    end
    assert_includes error.message, 'nothing to build'
  end

  def test_invalid_manifest_raises
    m = write_manifest("name: app\nmatrix: []\n")
    assert_raises(Crossbuild::InvalidManifestError) do
      capturing_stdout { Crossbuild::Builder.new(m, root: @dir).run }
    end
  end

  def test_crossbuild_build_convenience_api
    m = write_manifest(<<~YAML)
      name: app
      version: '2.0.0'
      matrix:
        - build: #{host_platform}
          steps: [mkdir -p build/bin]
          artifacts: { from: build/bin, include: [marker], to: [debian-12] }
    YAML
    FileUtils.mkdir_p(File.join(@dir, 'build', 'bin'))
    FileUtils.touch(File.join(@dir, 'build', 'bin', 'marker'))

    result = nil
    capturing_stdout { result = Crossbuild.build(m, root: @dir, host_os: host_os, host_arch: host_arch) }
    assert_equal '2.0.0', result.version
    assert File.exist?(File.join(@dir, 'builds', 'debian', '12', host_deb_arch, 'marker'))
  end

  private

  def host_os
    Crossbuild::Platform.os
  end

  def host_arch
    Crossbuild::Platform.arch
  end

  def host_platform
    "#{host_os}/#{Crossbuild::Platform.display_arch(host_arch)}"
  end

  # deb spelling of the host arch for builds/<family>/<version>/<arch>/
  def host_deb_arch
    host_arch == :x86_64 ? 'amd64' : 'arm64'
  end

  def capturing_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
  ensure
    $stdout = original
  end
end
