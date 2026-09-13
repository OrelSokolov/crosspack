# frozen_string_literal: true

require_relative 'test_helper'

class ConfigTest < Minitest::Test
  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir && File.directory?(@tmpdir)
  end

  def load(yaml_text)
    file = File.join(@tmpdir ||= Dir.mktmpdir('crosspack-config'), 'crosspack.yml')
    File.write(file, yaml_text)
    Crosspack::Config.load(file)
  end

  FULL = <<~YAML
    name: myapp
    version: calver
    build:
      matrix:
        - build: linux/amd64
          steps: ['true']
          artifacts: { from: build/bin, to: [debian-12] }
    package:
      maintainer: Test <t@example.com>
      description: Test app
      sources: builds
      prefix: usr/local
      payload: [app]
    deps:
      webkit2gtk:
        targets:
          debian:
            "12": [libwebkit2gtk-4.1-0]
  YAML

  def test_full_config_valid_all_sections
    config = load(FULL)
    assert config.valid?, config.errors.map(&:to_s).join('; ')
    assert config.build_manifest.valid?
    assert config.package_manifest.valid?
    assert config.deps_manifest.valid?
  end

  def test_name_and_version_are_injected_into_build_section
    config = load(FULL)
    assert_equal 'myapp', config.build_manifest.name
    assert_equal 'calver', config.build_manifest.version
  end

  def test_name_is_injected_into_package_section
    config = load(FULL)
    assert_equal 'myapp', config.package_manifest.name
  end

  def test_missing_version_defaults_to_calver_with_warning
    config = load(FULL.gsub("version: calver\n", ''))
    assert config.valid?
    assert_equal 'calver', config.build_manifest.version
    assert(config.build_manifest.warnings.any? { |w| w.message.include?('defaulting to calver') })
  end

  def test_section_values_override_the_shared_top_level
    config = load(FULL.sub('build:', "build:\n  version: '1.2.3'"))
    assert config.build_manifest.valid?
    assert_equal '1.2.3', config.build_manifest.version
  end

  def test_missing_sections_report_their_section
    config = load("name: app\n")
    assert config.valid?

    build = config.build_manifest
    refute build.valid?
    assert(build.errors.any? { |e| e.path == '(root)' && e.message.include?('build: section') })

    pkg = config.package_manifest
    refute pkg.valid?
    assert(pkg.errors.any? { |e| e.path == '(root)' && e.message.include?('package: section') })

    deps = config.deps_manifest
    refute deps.valid?
    assert(deps.errors.any? { |e| e.path == '(root)' && e.message.include?('deps: section') })
  end

  def test_missing_name_is_error
    config = load("build:\n  matrix:\n    - build: linux/amd64\n      steps: ['true']\n")
    refute config.valid?
    assert(config.errors.any? { |e| e.path == 'name' })
  end

  def test_invalid_name_is_error
    config = load("name: My App\n")
    refute config.valid?
    assert(config.errors.any? { |e| e.path == 'name' && e.message.include?('invalid name') })
  end

  def test_invalid_version_type_is_error
    config = load("name: app\nversion: 42\n")
    refute config.valid?
    assert(config.errors.any? { |e| e.path == 'version' })
  end

  def test_unknown_top_level_key_is_error
    config = load("name: app\nbuuld: {}\n")
    refute config.valid?
    assert(config.errors.any? { |e| e.path == '(root).buuld' })
  end

  def test_section_of_wrong_type_is_error
    config = load("name: app\nbuild: yes\n")
    refute config.valid?
    assert(config.errors.any? { |e| e.path == 'build' && e.message.include?('mapping') })
  end

  def test_root_must_be_mapping
    config = load("- just\n- a\n- list\n")
    refute config.valid?
    assert(config.errors.any? { |e| e.path == '(root)' })
  end

  def test_error_report
    config = load(FULL)
    assert_includes config.error_report, 'config is valid'

    broken = load("name: app\nunknown: 1\n")
    assert_includes broken.error_report, 'crosspack.yml is invalid'
    assert_includes broken.error_report, '(root).unknown'
  end

  def test_coerce_accepts_config_and_path
    config = load(FULL)
    assert_equal config, Crosspack::Config.coerce(config)
    assert_equal config.path, Crosspack::Config.coerce(config.path).path
    # Relative paths resolve against root.
    assert_equal config.path, Crosspack::Config.coerce('crosspack.yml', root: @tmpdir).path
  end

  def test_load_default_path
    Dir.mktmpdir('crosspack-default') do |dir|
      Dir.chdir(dir) do
        error = assert_raises(Crosspack::InvalidManifestError) { Crosspack::Config.load }
        assert_includes error.message, 'crosspack.yml not found'

        File.write('crosspack.yml', FULL)
        assert Crosspack::Config.load.valid?
      end
    end
  end
end
