# frozen_string_literal: true

require_relative 'test_helper'

class ResolverTest < Minitest::Test
  include ManifestHelper

  def teardown
    FileUtils.remove_entry(@tmpdir) if @tmpdir && File.directory?(@tmpdir)
  end

  def manifest
    load_manifest(<<~YAML)
      webkit2gtk:
        targets:
          debian:
            "12": [libwebkit2gtk-4.1-0, libwebkit2gtk-4.0-37]
            "11": [libwebkit2gtk-4.0-37]
          fedora:
            "*": [webkit2gtk4.1]
          arch: { "*": [webkit2gtk-4.1] }
          macos: system
          windows: system
      gtk3:
        targets:
          debian:
            "12": [libgtk-3-0]
            "13": [libgtk-3-0t64]
          fedora:
            "*": [gtk3]
          arch: { "*": [gtk3] }
          macos: none
          windows: none
    YAML
  end

  def test_deb_depends_line_with_alternatives
    line = Crosspack::Resolver.new(manifest).depends(
      Crosspack::Target.parse('debian-12')
    )
    assert_equal 'libwebkit2gtk-4.1-0 | libwebkit2gtk-4.0-37, libgtk-3-0', line
  end

  def test_exact_version_wins_over_wildcard
    deps = Crosspack::Resolver.new(manifest).depends(
      Crosspack::Target.parse('fedora-41')
    )
    assert_equal ['webkit2gtk4.1', 'gtk3'], deps
  end

  def test_rpm_takes_first_alternative_only
    deps = Crosspack::Resolver.new(manifest).depends(
      Crosspack::Target.parse('debian-12'), format: :rpm
    )
    assert_equal ['libwebkit2gtk-4.1-0', 'libgtk-3-0'], deps
  end

  def test_system_and_none_are_skipped_in_package_deps
    line = Crosspack::Resolver.new(manifest).depends(
      Crosspack::Target.parse('arch'), format: :pkgbuild
    )
    assert_equal ['webkit2gtk-4.1', 'gtk3'], line
  end

  def test_missing_version_falls_back_to_newest_recipe_with_warning
    resolver = Crosspack::Resolver.new(manifest)
    deps = nil
    _out, err = capture_io do
      deps = resolver.depends(Crosspack::Target.parse('debian-14'), format: :rpm)
    end
    # Newest described debian version is "12" (webkit2gtk) / "13" (gtk3).
    assert_equal ['libwebkit2gtk-4.1-0', 'libgtk-3-0t64'], deps
    assert_includes err, 'webkit2gtk: no recipe for debian "14"'
    assert_includes err, 'using the rules of the newest described version "12"'
    assert_includes err, 'gtk3: no recipe for debian "14"'
    assert_includes err, 'using the rules of the newest described version "13"'
  end

  def test_newest_recipe_compares_versions_numerically
    manifest = load_manifest(<<~YAML)
      gtk3:
        targets:
          ubuntu:
            "24.4": [libgtk-3-0]
            "24.10": [libgtk-3-1]
            "9": [libgtk-3-old]
    YAML
    _out, err = capture_io do
      deps = Crosspack::Resolver.new(manifest).depends(
        Crosspack::Target.parse('ubuntu-26.04'), format: :rpm
      )
      assert_equal ['libgtk-3-1'], deps
    end
    assert_includes err, 'using the rules of the newest described version "24.10"'
  end

  def test_missing_family_error_names_the_family
    error = assert_raises(Crosspack::ResolveError) do
      Crosspack::Resolver.new(manifest).depends(Crosspack::Target.parse('opensuse-15.6'))
    end
    assert_includes error.message, 'no rules for family opensuse'
    assert_includes error.message, 'debian, fedora, arch, macos, windows'
  end

  def test_resolver_refuses_invalid_manifest
    bad = load_manifest("webkit2gtk:\n  targets: {}\n")
    assert_raises(Crosspack::InvalidManifestError) { Crosspack::Resolver.new(bad) }
  end
end
