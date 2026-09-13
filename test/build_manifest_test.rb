# frozen_string_literal: true

require_relative 'test_helper'

class BuildManifestTest < Minitest::Test
  include BuildManifestHelper

  VALID = <<~YAML
    name: myapp
    version: calver
    output: builds
    matrix:
      - build: linux/amd64
        env:
          CGO_LDFLAGS: "-Lthird_party -fopenmp"
        steps:
          - wails build -platform linux/amd64 -ldflags "-X app.version={{version}}"
          - cargo build --release -p helper
        artifacts:
          from: build/bin
          to: [ubuntu-22.04, debian-12]
      - id: windows
        build: windows/amd64
        steps:
          - wails build -platform windows/amd64
        artifacts:
          from: build/bin
          include: [myapp.exe]
          to: [windows-11.0]
  YAML

  def test_valid_manifest
    m = load_manifest(VALID)
    assert m.valid?, m.errors.map(&:to_s).join('; ')
    assert_equal 'myapp', m.name
    assert_equal 'calver', m.version
    assert_equal 'builds', m.output
    assert_equal 2, m.entries.size

    linux = m.entries.first
    assert_equal 'linux/amd64', linux.id
    assert_equal :linux, linux.os
    assert_equal :x86_64, linux.arch
    assert_equal 2, linux.steps.size
    assert_equal '-Lthird_party -fopenmp', linux.env['CGO_LDFLAGS']
    assert_equal 'build/bin', linux.artifacts.from
    assert_equal %w[ubuntu-22.04 debian-12], linux.artifacts.to
    assert_equal :symlink, linux.artifacts.mode

    windows = m.entries.last
    assert_equal 'windows', windows.id
    assert_equal ['myapp.exe'], windows.artifacts.include
  end

  def test_defaults_and_entry_ids
    m = load_manifest(<<~YAML)
      name: app
      matrix:
        - build: darwin/arm64
          steps: [make]
          artifacts: { from: build/bin, to: [macos] }
    YAML
    assert m.valid?, m.errors.map(&:to_s).join('; ')
    assert_equal 'calver', m.version
    assert_equal 'builds', m.output
    assert_equal 'darwin/arm64', m.entries.first.id
    assert_equal ['*'], m.entries.first.artifacts.include
    assert(m.warnings.any? { |w| w.to_s.include?('version') })
  end

  def test_missing_file
    assert_raises(Crossbuild::InvalidManifestError) do
      Crossbuild::BuildManifest.load('/nonexistent/build.yaml')
    end
  end

  def test_yaml_syntax_error
    file = File.join(Dir.mktmpdir('crossbuild-test'), 'build.yaml')
    File.write(file, "name: [unclosed\n  matrix:")
    error = assert_raises(Crossbuild::InvalidManifestError) { Crossbuild::BuildManifest.load(file) }
    assert_includes error.message, 'YAML syntax error'
  end

  def test_root_must_be_mapping
    m = load_manifest("- just\n- a\n- list\n")
    refute m.valid?
    assert(m.errors.any? { |e| e.path == '(root)' })
  end

  def test_unknown_top_level_key
    m = load_manifest("name: app\nmatrixs: []\n")
    refute m.valid?
    assert(m.errors.any? { |e| e.path == '(root).matrixs' && e.message.include?('matrix') })
  end

  def test_missing_name
    m = load_manifest("matrix:\n  - build: linux/amd64\n    steps: ['true']\n")
    refute m.valid?
    assert(m.errors.any? { |e| e.path == 'name' })
  end

  def test_invalid_version_spec
    m = load_manifest("name: app\nversion: 42\nmatrix:\n  - build: linux/amd64\n    steps: ['true']\n")
    refute m.valid?
    assert(m.errors.any? { |e| e.path == 'version' })
  end

  def test_env_without_var_name
    m = load_manifest("name: app\nversion: 'env:'\nmatrix:\n  - build: linux/amd64\n    steps: ['true']\n")
    refute m.valid?
    assert(m.errors.any? { |e| e.path == 'version' && e.message.include?('env:') })
  end

  def test_invalid_build_platform
    m = load_manifest("name: app\nmatrix:\n  - build: lunix/amd64\n    steps: ['true']\n")
    refute m.valid?
    error = m.errors.find { |e| e.path == 'matrix[0].build' }
    assert error
    assert_includes error.message, 'invalid build platform'
  end

  def test_invalid_steps
    m = load_manifest("name: app\nmatrix:\n  - build: linux/amd64\n    steps: []\n")
    refute m.valid?
    assert(m.errors.any? { |e| e.path == 'matrix[0].steps' })
  end

  def test_entry_without_steps_and_artifacts
    m = load_manifest("name: app\nmatrix:\n  - build: linux/amd64\n")
    refute m.valid?
    assert(m.errors.any? { |e| e.message.include?('would do nothing') })
  end

  def test_artifacts_from_required
    m = load_manifest("name: app\nmatrix:\n  - build: linux/amd64\n    steps: ['true']\n    artifacts:\n      to: [debian-12]\n")
    refute m.valid?
    assert(m.errors.any? { |e| e.path == 'matrix[0].artifacts.from' })
  end

  def test_artifacts_to_must_be_valid_targets
    m = load_manifest("name: app\nmatrix:\n  - build: linux/amd64\n    steps: ['true']\n    artifacts:\n      from: build/bin\n      to: [gentoo-1, debian]\n")
    refute m.valid?
    assert(m.errors.any? { |e| e.path.include?('gentoo-1') })
    assert(m.errors.any? { |e| e.path.include?('debian') && e.message.include?('version') })
  end

  def test_unknown_artifact_mode
    m = load_manifest("name: app\nmatrix:\n  - build: linux/amd64\n    steps: ['true']\n    artifacts:\n      from: build/bin\n      to: [debian-12]\n      mode: move\n")
    refute m.valid?
    assert(m.errors.any? { |e| e.path == 'matrix[0].artifacts.mode' })
  end

  def test_duplicate_ids_rejected
    m = load_manifest("name: app\nmatrix:\n  - build: linux/amd64\n    steps: ['true']\n  - build: linux/amd64\n    steps: ['true']\n")
    refute m.valid?
    assert(m.errors.any? { |e| e.path == 'matrix' && e.message.include?('duplicate entry id') })
  end

  def test_duplicate_target_warns
    m = load_manifest(<<~YAML)
      name: app
      matrix:
        - id: a
          build: linux/amd64
          steps: ['true']
          artifacts: { from: build/bin, to: [debian-12] }
        - id: b
          build: windows/amd64
          steps: ['true']
          artifacts: { from: build/bin, to: [debian-12] }
    YAML
    assert m.valid?
    assert(m.warnings.any? { |w| w.to_s.include?('debian-12') && w.to_s.include?('last entry wins') })
  end

  def test_validate_bang_raises_formatted_report
    m = load_manifest("name: app\nmatrix: []\n")
    error = assert_raises(Crossbuild::InvalidManifestError) { m.validate! }
    assert_includes error.message, 'build.yaml schema is invalid'
    assert_includes error.message, 'matrix'
  end

  def test_error_report_valid_form
    m = load_manifest(VALID)
    assert_includes m.error_report, 'schema is valid (2 entries: linux/amd64, windows)'
  end

  def test_buildable_entries_and_find
    m = load_manifest(VALID)
    assert_equal ['linux/amd64'], m.buildable_entries(:linux, :x86_64).map(&:id)
    assert_equal ['windows'], m.buildable_entries(:windows, :x86_64).map(&:id)
    assert_equal [], m.buildable_entries(:darwin, :arm64)
    assert_equal 'windows', m.find_entry('windows').id
    assert_nil m.find_entry('nope')
  end

  def test_arch_any_matches_both_arches
    m = load_manifest("name: app\nmatrix:\n  - build: darwin/any\n    steps: ['true']\n")
    assert m.valid?
    assert_equal ['darwin/amd64'], m.buildable_entries(:darwin, :x86_64).map(&:id)
    assert_equal ['darwin/amd64'], m.buildable_entries(:darwin, :arm64).map(&:id)
  end

  def test_deps_section_parses_into_dependencies
    m = load_manifest(<<~YAML)
      name: app
      deps:
        imagemagick:
          hosts:
            ubuntu:
              verify: dpkg -s imagemagick
              install: sudo apt-get install -y imagemagick
            windows:
              verify: where magick
              install: winget install -e --id ImageMagick.ImageMagick
            "*":
              install: ./scripts/install-imagemagick.sh
      matrix:
        - build: linux/amd64
          steps: ['true']
    YAML
    assert m.valid?, m.errors.map(&:to_s).join('; ')
    assert_equal 1, m.deps.size
    dep = m.deps.first
    assert_equal 'imagemagick', dep.name
    assert_equal 'dpkg -s imagemagick', dep.hosts['ubuntu']['verify']
    assert_equal 'sudo apt-get install -y imagemagick', dep.hosts['ubuntu']['install']
    assert_nil dep.hosts['*']['verify']
    assert_equal './scripts/install-imagemagick.sh', dep.hosts['*']['install']
  end

  def test_deps_verify_only_rule_is_valid
    m = load_manifest("name: app\ndeps:\n  curl:\n    hosts:\n      \"*\": {verify: curl --version}\nmatrix:\n  - build: linux/amd64\n    steps: ['true']\n")
    assert m.valid?
    assert_nil m.deps.first.hosts['*']['install']
  end

  def test_deps_must_be_mapping
    m = load_manifest("name: app\ndeps: [imagemagick]\nmatrix:\n  - build: linux/amd64\n    steps: ['true']\n")
    refute m.valid?
    assert(m.errors.any? { |e| e.path == 'deps' && e.message.include?('must be a mapping') })
  end

  def test_deps_unknown_key_rejected
    m = load_manifest("name: app\ndeps:\n  curl:\n    check: curl --version\n    hosts:\n      \"*\": {install: apt-get install curl}\nmatrix:\n  - build: linux/amd64\n    steps: ['true']\n")
    refute m.valid?
    assert(m.errors.any? { |e| e.path == 'deps.curl.check' && e.message.include?('unknown key') })
  end

  def test_deps_rule_must_be_verify_install_mapping
    m = load_manifest("name: app\ndeps:\n  curl:\n    hosts:\n      ubuntu: sudo apt-get install curl\nmatrix:\n  - build: linux/amd64\n    steps: ['true']\n")
    refute m.valid?
    assert(m.errors.any? { |e| e.path == 'deps.curl.hosts.ubuntu' && e.message.include?('verify and/or install') })
  end

  def test_deps_hosts_must_be_non_empty_mapping
    m = load_manifest("name: app\ndeps:\n  curl:\n    hosts: {}\nmatrix:\n  - build: linux/amd64\n    steps: ['true']\n")
    refute m.valid?
    assert(m.errors.any? { |e| e.path == 'deps.curl.hosts' })
  end

  def test_deps_unknown_rule_key_rejected
    m = load_manifest("name: app\ndeps:\n  curl:\n    hosts:\n      \"*\": {probe: curl --version, install: apt-get install curl}\nmatrix:\n  - build: linux/amd64\n    steps: ['true']\n")
    refute m.valid?
    assert(m.errors.any? { |e| e.path == 'deps.curl.hosts.*.probe' && e.message.include?('unknown key') })
  end

  def test_deps_command_must_be_string
    m = load_manifest("name: app\ndeps:\n  curl:\n    hosts:\n      \"*\": {install: 42}\nmatrix:\n  - build: linux/amd64\n    steps: ['true']\n")
    refute m.valid?
    assert(m.errors.any? { |e| e.path == 'deps.curl.hosts.*.install' })
  end

  def test_deps_invalid_name_rejected
    m = load_manifest("name: app\ndeps:\n  bad name!:\n    hosts:\n      \"*\": {install: 'true'}\nmatrix:\n  - build: linux/amd64\n    steps: ['true']\n")
    refute m.valid?
    assert(m.errors.any? { |e| e.path == 'deps.bad name!' })
  end

  def test_entry_for_target_finds_the_entry
    m = load_manifest(<<~YAML)
      name: app
      matrix:
        - build: linux/amd64
          steps: ['true']
          artifacts: { from: build/bin, to: [debian-12, ubuntu-24.04] }
        - build: windows/amd64
          steps: ['true']
          artifacts: { from: build/bin, to: [windows-11.0] }
    YAML
    assert_equal 'linux/amd64', m.entry_for_target('ubuntu-24.04').id
    assert_equal 'windows/amd64', m.entry_for_target('windows-11.0').id
  end

  def test_entry_for_target_unknown_raises_with_declared
    m = load_manifest("name: app\nmatrix:\n  - build: linux/amd64\n    steps: ['true']\n    artifacts: { from: build/bin, to: [debian-12] }\n")
    error = assert_raises(Crossbuild::Error) { m.entry_for_target('fedora-41') }
    assert_includes error.message, 'no matrix entry distributes to target "fedora-41"'
    assert_includes error.message, 'declared targets: debian-12'
  end

  def test_entry_for_target_ambiguous_raises
    m = load_manifest(<<~YAML)
      name: app
      matrix:
        - id: a
          build: linux/amd64
          steps: ['true']
          artifacts: { from: build/bin, to: [debian-12] }
        - id: b
          build: linux/amd64
          steps: ['true']
          artifacts: { from: build/bin, to: [debian-12] }
    YAML
    error = assert_raises(Crossbuild::Error) { m.entry_for_target('debian-12') }
    assert_includes error.message, 'several entries'
    assert_includes error.message, 'a, b'
  end
end
