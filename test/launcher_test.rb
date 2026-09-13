# frozen_string_literal: true

require_relative 'test_helper'

class LauncherTest < Minitest::Test
  HOST_TARGET = 'ubuntu-24.04'

  def setup
    @dir = Dir.mktmpdir('crosspack-launch')
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_run_builds_then_launches_binary
    write_app_binary("echo \"$@\" > #{@dir}/proof.txt")
    config = write_config

    status = nil
    capturing_stdout do
      status = Crosspack::Launcher.run(config, root: @dir, host_string: HOST_TARGET,
                                       host_os: :linux, host_arch: host_arch, selectors: ['*'])
    end
    assert_equal 0, status
    assert File.exist?(File.join(@dir, 'proof.txt')), 'the binary did not run'
    assert File.exist?(built_binary), 'the build stage did not distribute the binary'
  end

  def test_run_passes_args_after_separator
    write_app_binary("echo \"$@\" > #{@dir}/proof.txt")
    config = write_config

    status = nil
    capturing_stdout do
      status = Crosspack::Launcher.run(config, root: @dir, args: ['--dev', 'extra'],
                                       host_string: HOST_TARGET,
                                       host_os: :linux, host_arch: host_arch, selectors: ['*'])
    end
    assert_equal 0, status
    assert_equal '--dev extra', File.read(File.join(@dir, 'proof.txt')).strip  end

  def test_run_exit_code_propagates
    write_app_binary('exit 3')
    config = write_config

    status = nil
    capturing_stdout do
      status = Crosspack::Launcher.run(config, root: @dir, host_string: HOST_TARGET,
                                       host_os: :linux, host_arch: host_arch, selectors: ['*'])
    end
    assert_equal 3, status
  end

  def test_run_override_command_replaces_the_default
    write_app_binary("echo ran > #{@dir}/never.txt")
    config = write_config(<<~YAML)
      run:
        hosts:
          "*": cp {{path}} #{@dir}/copied
    YAML

    status = nil
    capturing_stdout do
      status = Crosspack::Launcher.run(config, root: @dir, host_string: HOST_TARGET,
                                       host_os: :linux, host_arch: host_arch, selectors: ['*'])
    end
    assert_equal 0, status
    assert File.exist?(File.join(@dir, 'copied')), 'the run: override did not run'
    refute File.exist?(File.join(@dir, 'never.txt')), 'the default launch must not run'
  end

  def test_run_without_executables_raises
    write_app_binary("echo ran > #{@dir}/never.txt")
    write_config_file(<<~YAML)
      name: app
      version: '1.0.0'
      package:
        maintainer: dev@example.com
        description: test app
        sources: builds
        prefix: usr
        payload: [app]
      build:
        matrix:
          - build: linux/#{host_platform_arch}
            steps: [mkdir -p build/bin]
            artifacts: { from: build/bin, include: [app], to: [ubuntu-24.04] }
    YAML
    config = Crosspack::Config.load(File.join(@dir, 'crosspack.yml'))

    error = assert_raises(Crosspack::Launcher::Error) do
      capturing_stdout do
        Crosspack::Launcher.run(config, root: @dir, host_string: HOST_TARGET,
                                host_os: :linux, host_arch: host_arch, selectors: ['*'])
      end
    end
    assert_includes error.message, 'executables'
  end

  def test_run_when_binary_is_not_produced_raises
    # The build distributes only `app`; the executable to launch (`launcher`)
    # never lands in builds/.
    write_app_binary("echo ran > #{@dir}/never.txt")
    write_config_file(<<~YAML)
      name: app
      version: '1.0.0'
      package:
        maintainer: dev@example.com
        description: test app
        sources: builds
        prefix: usr
        payload: [app, launcher]
        executables: [launcher]
      build:
        matrix:
          - build: linux/#{host_platform_arch}
            steps: [mkdir -p build/bin]
            artifacts: { from: build/bin, include: [app], to: [ubuntu-24.04] }
    YAML
    config = Crosspack::Config.load(File.join(@dir, 'crosspack.yml'))

    error = assert_raises(Crosspack::Launcher::Error) do
      capturing_stdout do
        Crosspack::Launcher.run(config, root: @dir, host_string: HOST_TARGET,
                                host_os: :linux, host_arch: host_arch, selectors: ['*'])
      end
    end
    assert_includes error.message, 'expected the built binary'
  end

  def test_install_launches_package_with_override
    write_package('app_1.0.0_amd64.deb')
    config = write_config(<<~YAML)
      install:
        hosts:
          "*": cp {{path}} #{@dir}/installed
    YAML

    status = nil
    capturing_stdout do
      status = Crosspack::Launcher.install(config, root: @dir, host_string: HOST_TARGET,
                                           host_os: :linux, host_arch: host_arch, selectors: ['*'])
    end
    assert_equal 0, status
    assert File.exist?(File.join(@dir, 'installed')), 'the installer command did not run'
  end

  def test_install_picks_the_newest_package
    old_file = write_package('app_1.0.0_amd64.deb')
    File.write(old_file, 'old')
    newest = write_package('app_2.0.0_amd64.deb')
    File.write(newest, 'new')
    File.utime(0, 0, old_file)
    config = write_config(<<~YAML)
      install:
        hosts:
          "*": cp {{path}} #{@dir}/installed
    YAML

    capturing_stdout do
      Crosspack::Launcher.install(config, root: @dir, host_string: HOST_TARGET,
                                  host_os: :linux, host_arch: host_arch, selectors: ['*'])
    end
    assert_equal 'new', File.read(File.join(@dir, 'installed')), 'the newest package must win'
  end

  def test_install_without_pack_stage_raises
    config = write_config

    error = assert_raises(Crosspack::Launcher::Error) do
      capturing_stdout do
        Crosspack::Launcher.install(config, root: @dir, host_string: HOST_TARGET,
                                    host_os: :linux, host_arch: host_arch, selectors: ['*'])
      end
    end
    assert_includes error.message, 'Pack stage not done'
    assert_includes error.message, "crosspack pack #{HOST_TARGET}"
  end

  def test_install_pkgbuild_hints_makepkg
    config = write_config

    error = assert_raises(Crosspack::Launcher::Error) do
      capturing_stdout do
        Crosspack::Launcher.install(config, root: @dir, host_string: 'arch',
                                    host_os: :linux, host_arch: host_arch, selectors: ['*'])
      end
    end
    assert_includes error.message, 'makepkg -si'
  end

  def test_default_run_command
    bundle = File.join(@dir, 'MyApp.app')
    FileUtils.mkdir_p(bundle)
    assert_equal '{{path}}', Crosspack::Launcher.default_run_command(File.join(@dir, 'app'), :linux)
    assert_equal '{{path}}', Crosspack::Launcher.default_run_command(File.join(@dir, 'app.exe'), :windows)
    assert_equal 'open {{path}}', Crosspack::Launcher.default_run_command(bundle, :darwin)
    assert_equal '{{path}}', Crosspack::Launcher.default_run_command(File.join(@dir, 'app'), :darwin)
  end

  def test_default_install_command
    assert_equal 'xdg-open {{path}}', Crosspack::Launcher.default_install_command(:deb)
    assert_equal 'xdg-open {{path}}', Crosspack::Launcher.default_install_command(:rpm)
    assert_equal 'msiexec /i {{path}}', Crosspack::Launcher.default_install_command(:winget)
    assert_equal 'open {{path}}', Crosspack::Launcher.default_install_command(:cask)
  end

  private

  def host_arch
    Crossbuild::Platform.arch
  end

  def host_platform_arch
    Crossbuild::Platform.display_arch(host_arch)
  end

  def deb_arch
    host_arch == :x86_64 ? 'amd64' : 'arm64'
  end

  def built_binary
    File.join(@dir, 'builds', 'ubuntu', '24.04', deb_arch, 'app')
  end

  # A fake app binary that the build step "produces": the artifacts stage
  # symlinks it into builds/ (which is what Launcher executes).
  def write_app_binary(body)
    dir = File.join(@dir, 'build', 'bin')
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, 'app'), <<~SH)
      #!/bin/sh
      #{body}
    SH
    FileUtils.chmod(0o755, File.join(dir, 'app'))
  end

  def write_package(name)
    dir = File.join(@dir, 'crosspacks', 'ubuntu', '24.04', deb_arch)
    FileUtils.mkdir_p(dir)
    file = File.join(dir, name)
    FileUtils.touch(file)
    file
  end

  def write_config_file(yaml)
    File.write(File.join(@dir, 'crosspack.yml'), yaml)
  end

  def write_config(run_install = nil)
    yaml = <<~YAML + run_install.to_s
      name: app
      version: '1.0.0'
      package:
        maintainer: dev@example.com
        description: test app
        sources: builds
        prefix: usr
        payload: [app]
        executables: [app]
      build:
        matrix:
          - build: linux/#{host_platform_arch}
            steps: [mkdir -p build/bin]
            artifacts: { from: build/bin, include: [app], to: [ubuntu-24.04] }
    YAML
    write_config_file(yaml)
    Crosspack::Config.load(File.join(@dir, 'crosspack.yml'))
  end

  def capturing_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
  ensure
    $stdout = original
  end
end
