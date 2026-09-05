# frozen_string_literal: true

require_relative 'test_helper'

class MatrixTest < Minitest::Test
  include ManifestHelper

  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir && File.directory?(@tmpdir)
  end

  def test_renders_columns_for_all_declared_targets
    m = load_manifest(<<~YAML)
      webkit2gtk:
        targets:
          debian:
            "12": [libwebkit2gtk-4.1-0, libwebkit2gtk-4.0-37]
          fedora:
            "*": [webkit2gtk4.1]
          macos: system
      gtk3:
        targets:
          debian:
            "12": [libgtk-3-0]
          macos: none
    YAML
    table = Crosspack::Matrix.new(m).render
    assert_includes table, 'dependency'
    assert_includes table, 'debian-12'
    assert_includes table, 'fedora'
    assert_includes table, 'macos'
    assert_includes table, 'libwebkit2gtk-4.1-0 | libwebkit2gtk-4.0-37'
    assert_includes table, 'webkit2gtk4.1'
    assert_includes table, 'system'
    assert_includes table, 'none'
    assert_includes table, 'webkit2gtk'
    assert_includes table, 'gtk3'
  end

  def test_gap_is_visible
    m = load_manifest(<<~YAML)
      webkit2gtk:
        targets:
          debian:
            "12": [libwebkit2gtk-4.1-0]
      gtk3:
        targets:
          debian:
            "12": [libgtk-3-0]
          fedora:
            "*": [gtk3]
    YAML
    table = Crosspack::Matrix.new(m).render
    assert_includes table, '—'
  end
end
