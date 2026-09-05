# frozen_string_literal: true

require_relative 'test_helper'

class ManifestTest < Minitest::Test
  include ManifestHelper

  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir && File.directory?(@tmpdir)
  end

  def test_valid_manifest_passes
    m = load_manifest(<<~YAML)
      webkit2gtk:
        targets:
          debian:
            "12": [libwebkit2gtk-4.1-0]
          windows: system
    YAML
    assert m.valid?, m.errors.map(&:to_s).join('; ')
    assert_empty m.errors
  end

  def test_unknown_family_with_suggestion
    m = load_manifest(<<~YAML)
      webkit2gtk:
        targets:
          deban:
            "12": [libwebkit2gtk-4.1-0]
    YAML
    assert_equal 1, m.errors.size
    assert_includes m.errors.first.to_s, 'targets.deban'
    assert_includes m.errors.first.to_s, 'did you mean "debian"'
  end

  def test_numeric_version_key_is_rejected_with_hint
    m = load_manifest(<<~YAML)
      webkit2gtk:
        targets:
          debian:
            12: [libwebkit2gtk-4.1-0]
    YAML
    assert_equal 1, m.errors.size
    assert_includes m.errors.first.to_s, 'version key must be a quoted string'
    assert_includes m.errors.first.to_s, '"12"'
  end

  def test_missing_targets_field
    m = load_manifest("webkit2gtk:\n  debian: {}\n")
    assert_equal 1, m.errors.size
    assert_includes m.errors.first.to_s, 'missing required field targets'
  end

  def test_empty_package_list_is_error
    m = load_manifest(<<~YAML)
      webkit2gtk:
        targets:
          debian:
            "12": []
    YAML
    assert_equal 1, m.errors.size
    assert_includes m.errors.first.to_s, 'package list is empty'
  end

  def test_unknown_verdict_is_error
    m = load_manifest(<<~YAML)
      webkit2gtk:
        targets:
          debian: builtin
    YAML
    assert_equal 1, m.errors.size
    assert_includes m.errors.first.to_s, 'unknown verdict "builtin"'
  end

  def test_unknown_canonical_name_is_warning_not_error
    m = load_manifest(<<~YAML)
      myweirddep:
        targets:
          debian:
            "12": [some-pkg]
    YAML
    assert m.valid?
    assert_equal 1, m.warnings.size
  end

  def test_validate_raises_with_all_errors_at_once
    m = load_manifest(<<~YAML)
      a:
        targets:
          deban: {}
      b:
        targets: {}
    YAML
    error = assert_raises(Crosspack::InvalidManifestError) { m.validate! }
    assert_includes error.message, '2 errors'
    assert_includes error.message, 'a.targets.deban'
    assert_includes error.message, 'b.targets'
  end

  def test_missing_file_error_mentions_path
    error = assert_raises(Crosspack::InvalidManifestError) do
      Crosspack::Manifest.load('/nonexistent/deps.yaml')
    end
    assert_includes error.message, 'not found'
    assert_includes error.message, 'deps.yaml'
  end

  def test_yaml_syntax_error_is_reported_with_line
    file = File.join(Dir.mktmpdir('crosspack-syntax'), 'deps.yaml')
    File.write(file, "webkit2gtk:\n  targets:\n   [broken\n")
    error = assert_raises(Crosspack::InvalidManifestError) { Crosspack::Manifest.load(file) }
    assert_includes error.message, 'YAML syntax error'
  end
end
