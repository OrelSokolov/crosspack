# frozen_string_literal: true

require_relative 'test_helper'

class TargetTest < Minitest::Test
  def test_parse_versioned_family
    t = Crosspack::Target.parse('debian-12')
    assert_equal :debian, t.family
    assert_equal '12', t.version
    assert_equal :deb, t.format
    assert_equal 'debian-12', t.to_s
  end

  def test_parse_ubuntu_with_dot_version
    t = Crosspack::Target.parse('ubuntu-24.04')
    assert_equal '24.04', t.version
    assert_equal :deb, t.format
  end

  def test_parse_versionless_family
    t = Crosspack::Target.parse('arch')
    assert_nil t.version
    assert_equal :pkgbuild, t.format
  end

  def test_parse_rejects_unknown_family
    error = assert_raises(Crosspack::Target::Error) { Crosspack::Target.parse('gentoo-1') }
    assert_includes error.message, 'unknown distro family "gentoo"'
  end

  def test_parse_rejects_version_on_versionless_family
    error = assert_raises(Crosspack::Target::Error) { Crosspack::Target.parse('arch-2024') }
    assert_includes error.message, 'does not use a version'
  end

  def test_parse_rejects_version_missing_on_versioned_family
    error = assert_raises(Crosspack::Target::Error) { Crosspack::Target.parse('debian') }
    assert_includes error.message, 'specify a version'
  end

  def test_arch_normalization
    assert_equal :x86_64, Crosspack::Target.normalize_arch('amd64')
    assert_equal :x86_64, Crosspack::Target.normalize_arch('x86_64')
    assert_equal :arm64, Crosspack::Target.normalize_arch('aarch64')
    assert_nil Crosspack::Target.normalize_arch('armhf')
  end

  def test_output_dir_layout
    t = Crosspack::Target.parse('ubuntu-26.04', arch: 'amd64')
    assert_equal 'crosspacks/ubuntu/26.04/amd64', t.output_dir('crosspacks', :deb)

    fedora = Crosspack::Target.parse('fedora-41')
    assert_equal 'crosspacks/fedora/41/x86_64', fedora.output_dir('crosspacks', :rpm)

    versionless = Crosspack::Target.parse('arch')
    assert_equal 'crosspacks/arch/x86_64', versionless.output_dir('crosspacks', :pkgbuild)

    windows = Crosspack::Target.parse('windows-11.0')
    assert_equal 'crosspacks/windows/11.0/x86_64', windows.output_dir('crosspacks')
  end

  def test_package_arch_per_format
    t = Crosspack::Target.parse('debian-12', arch: 'amd64')
    assert_equal 'amd64', t.package_arch(:deb)
    assert_equal 'x86_64', t.package_arch(:rpm)

    arm = Crosspack::Target.parse('fedora-41', arch: 'aarch64')
    assert_equal 'aarch64', arm.package_arch(:rpm)
  end
end
