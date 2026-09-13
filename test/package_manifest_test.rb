# frozen_string_literal: true

require_relative 'test_helper'

class PackageManifestTest < Minitest::Test
  include ConfigHelper

  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir && File.directory?(@tmpdir)
  end

  def load(yaml_text)
    load_config_section('package', yaml_text).package_manifest
  end

  VALID = <<~YAML
    name: app
    maintainer: Test <t@example.com>
    description: |-
      Test app
      Second line
    sources: build/bin
    prefix: usr/local
    payload:
      - app
      - model.bin
    executables: [app]
    links:
      bin/app: ../lib/app/app
    desktop:
      name: App
  YAML

  def test_valid_manifest_passes
    m = load(VALID)
    assert m.valid?, m.errors.map(&:to_s).join('; ')
    assert_equal 'app', m.name
    assert_equal File.join('lib', 'app'), m.lib_dir
    assert_equal 'Test app', m.summary
    assert_equal 'Proprietary', m.license
  end

  def test_missing_required_fields_are_all_reported
    m = load("summary: x\n")
    assert_equal 5, m.errors.size
    paths = m.errors.map(&:path)
    %w[maintainer description sources prefix payload].each { |k| assert_includes paths, k }
  end

  def test_unknown_field_is_error
    m = load(VALID + "unknown_key: 1\n")
    assert_equal 1, m.errors.size
    assert_includes m.errors.first.to_s, 'unknown field'
  end

  def test_executable_not_in_payload_is_error
    m = load(VALID.gsub('executables: [app]', 'executables: [ghost]'))
    assert_equal 1, m.errors.size
    assert_includes m.errors.first.to_s, 'ghost'
    assert_includes m.errors.first.to_s, 'payload'
  end

  def test_empty_payload_is_error
    stripped = VALID.gsub(/payload:\n( +- .*\n)+/, "payload: []\n")
                    .gsub('executables: [app]', 'executables: []')
    m = load(stripped)
    assert_equal 1, m.errors.size
    assert_includes m.errors.first.to_s, 'payload'
  end

  def test_absolute_link_path_is_error
    m = load(VALID.gsub('bin/app: ../lib/app/app', '/bin/app: ../lib/app/app'))
    assert_equal 1, m.errors.size
    assert_includes m.errors.first.to_s, 'relative'
  end

  def test_validate_raises_with_all_errors
    m = load_config_section('package', 'summary: x', "name: app\n").package_manifest
    error = assert_raises(Crosspack::InvalidManifestError) { m.validate! }
    assert_includes error.message, 'the package: section'
    assert_includes error.message, 'errors'
  end

  def test_missing_file_error_mentions_path
    error = assert_raises(Crosspack::InvalidManifestError) do
      Crosspack::Config.load('/nonexistent/crosspack.yml')
    end
    assert_includes error.message, 'not found'
    assert_includes error.message, 'crosspack.yml'
  end

  def test_payload_mapping_resolves_per_target
    m = load(<<~YAML)
      name: app
      maintainer: Test <t@example.com>
      description: x
      sources: build/bin
      prefix: usr/local
      payload:
        app:
          "*": app
          windows: app.exe
        model.onnx:
        libonnxruntime.so.1:
          linux: libonnxruntime.so.1
        onnxruntime.dll:
          windows: onnxruntime.dll
      executables: [app]
    YAML
    assert m.valid?, m.errors.map(&:to_s).join('; ')

    deb = Crosspack::Target.parse('ubuntu-24.04')
    assert_equal %w[app model.onnx libonnxruntime.so.1], m.payload_for(deb)
    assert_equal ['app'], m.executables_for(deb)

    win = Crosspack::Target.parse('windows-11.0')
    assert_equal %w[app.exe model.onnx onnxruntime.dll], m.payload_for(win)
    assert_equal ['app.exe'], m.executables_for(win)

    mac = Crosspack::Target.parse('macos')
    assert_equal %w[app model.onnx], m.payload_for(mac)
  end

  def test_payload_exact_target_beats_family
    m = load(<<~YAML)
      name: app
      maintainer: Test <t@example.com>
      description: x
      sources: build/bin
      prefix: usr/local
      payload:
        app:
          windows: app.exe
          windows-11.0: app11.exe
    YAML
    assert m.valid?, m.errors.map(&:to_s).join('; ')
    assert_equal ['app11.exe'], m.payload_for(Crosspack::Target.parse('windows-11.0'))
    assert_equal ['app.exe'], m.payload_for(Crosspack::Target.parse('windows-10.0'))
  end

  def test_payload_unknown_selector_is_error
    replaced = VALID.sub("payload:\n  - app\n  - model.bin\n",
                         "payload:\n  app:\n    androoid: app.apk\n  model.onnx:\n")
                    .sub('executables: [app]', 'executables: [model.onnx]')
    m = load(replaced)
    assert_equal 1, m.errors.size
    assert_includes m.errors.first.to_s, 'unknown target selector'
    assert_includes m.errors.first.to_s, 'androoid'
  end

  def test_payload_absolute_name_in_mapping_is_error
    replaced = VALID.sub("payload:\n  - app\n  - model.bin\n",
                         "payload:\n  app:\n    windows: /app.exe\n  model.onnx:\n")
                    .sub('executables: [app]', 'executables: [model.onnx]')
    m = load(replaced)
    assert_equal 1, m.errors.size
    assert_includes m.errors.first.to_s, 'relative'
  end

  def test_executable_resolving_to_nothing_for_target_raises
    m = load(<<~YAML)
      name: app
      maintainer: Test <t@example.com>
      description: x
      sources: build/bin
      prefix: usr/local
      payload:
        app:
          windows: app.exe
      executables: [app]
    YAML
    assert m.valid?, m.errors.map(&:to_s).join('; ')
    error = assert_raises(Crosspack::InvalidManifestError) do
      m.executables_for(Crosspack::Target.parse('ubuntu-24.04'))
    end
    assert_includes error.message, 'app'
    assert_includes error.message, 'ubuntu-24.04'
  end
end
