# frozen_string_literal: true

require_relative 'test_helper'

class PackageManifestTest < Minitest::Test
  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir && File.directory?(@tmpdir)
  end

  def load(yaml_text)
    file = File.join(@tmpdir ||= Dir.mktmpdir('crosspack-pkg'), 'package.yaml')
    File.write(file, yaml_text)
    Crosspack::PackageManifest.load(file)
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
    assert_equal 6, m.errors.size
    paths = m.errors.map(&:path)
    %w[name maintainer description sources prefix payload].each { |k| assert_includes paths, k }
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
    m = load("name: app\n")
    error = assert_raises(Crosspack::InvalidManifestError) { m.validate! }
    assert_includes error.message, 'package.yaml'
    assert_includes error.message, 'errors'
  end

  def test_missing_file_error_mentions_path
    error = assert_raises(Crosspack::InvalidManifestError) do
      Crosspack::PackageManifest.load('/nonexistent/package.yaml')
    end
    assert_includes error.message, 'not found'
    assert_includes error.message, 'package.yaml'
  end
end
