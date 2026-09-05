# frozen_string_literal: true

require_relative 'test_helper'
require 'open3'

class PackerTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir('crosspack-root')
    # Fake compiled artifacts staged into the mirrored builds tree:
    # builds/<family>[/<version>]/<arch>/ — same shape as the output tree.
    artifacts = { 'debian/12/amd64' => true, 'fedora/41/x86_64' => true,
                  'arch/x86_64' => true, 'windows/11.0/x86_64' => true,
                  'macos/x86_64' => true }
    artifacts.each_key do |rel|
      dir = File.join(@root, 'builds', rel)
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, 'app'), "#!/bin/sh\necho hi\n")
      File.chmod(0o755, File.join(dir, 'app'))
      File.write(File.join(dir, 'model.bin'), 'model')
    end
    FileUtils.mkdir_p(File.join(@root, 'build'))
    File.write(File.join(@root, 'build', 'icon.png'), 'png')

    File.write(File.join(@root, 'package.yaml'), <<~YAML)
      name: app
      maintainer: Test <t@example.com>
      description: |-
        Test app
        Second line
      sources: builds
      prefix: usr/local
      lib_dir: lib/app
      payload: [app, model.bin]
      executables: [app]
      links:
        bin/app: ../lib/app/app
      desktop:
        name: App
        comment: Test comment
      icon: build/icon.png
    YAML

    File.write(File.join(@root, 'deps.yaml'), <<~YAML)
      webkit2gtk:
        targets:
          debian:
            "12": [libwebkit2gtk-4.1-0]
          fedora:
            "*": [webkit2gtk4.1]
          arch:
            "*": [webkit2gtk-4.1]
    YAML
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def pack(target_str, output_base = File.join(@root, 'crosspacks'))
    Crosspack.pack(
      manifest: File.join(@root, 'package.yaml'),
      deps: File.join(@root, 'deps.yaml'),
      target: Crosspack::Target.parse(target_str),
      version: '2026.08.31-1234',
      root: @root,
      output_base: output_base
    )
  end

  def test_pack_deb_end_to_end
    path = pack('debian-12')
    assert File.file?(path)
    assert_equal 'app_2026.08.31-1234_amd64.deb', File.basename(path)
    assert_includes path, File.join('crosspacks', 'debian', '12', 'amd64')

    control, = Open3.capture2e('dpkg-deb', '-f', path)
    assert_includes control, 'Package: app'
    assert_includes control, 'Version: 2026.08.31-1234'
    assert_includes control, 'Depends: libwebkit2gtk-4.1-0'
    assert_includes control, 'Description: Test app'

    listing, = Open3.capture2e('dpkg-deb', '-c', path)
    assert_includes listing, 'usr/local/lib/app/app'
    assert_includes listing, 'usr/local/lib/app/model.bin'
    assert_includes listing, 'usr/local/bin/app'
    assert_includes listing, 'usr/local/share/applications/app.desktop'
    assert_includes listing, 'usr/local/share/pixmaps/app.png'
  end

  def test_pack_pkgbuild
    path = pack('arch')
    assert File.file?(path)
    assert_equal 'PKGBUILD', File.basename(path)
    assert_includes path, File.join('crosspacks', 'arch', 'x86_64')

    content = File.read(path)
    assert_includes content, 'pkgname=app'
    assert_includes content, 'pkgver=2026.08.31'
    assert_includes content, 'pkgrel=1234'
    assert_includes content, "'webkit2gtk-4.1'"
    assert_includes content, 'ln -s ../lib/app/app "$pkgdir/usr/local/bin/app"'
  end

  def test_pack_missing_build_dir_gives_actionable_error
    error = assert_raises(Crosspack::BuildError) { pack('debian-13') }
    assert_includes error.message, 'No compiled artifacts for target debian-13'
    assert_includes error.message, 'builds/debian/13/amd64'
    assert_includes error.message, 'available builds'
    assert_includes error.message, 'debian-12'
  end

  def test_builds_available_scans_mirrored_tree
    targets = Crosspack::Builds.available(File.join(@root, 'builds'))
    labels = targets.map(&:to_s)
    assert_includes labels, 'debian-12'
    assert_includes labels, 'fedora-41'
    assert_includes labels, 'arch'
    assert_includes labels, 'windows-11.0'
    assert_includes labels, 'macos'
    assert_equal 5, targets.size
  end

  def test_builds_available_empty_for_missing_root
    assert_empty Crosspack::Builds.available(File.join(@root, 'nope'))
  end

  def test_pack_invalid_package_manifest_lists_errors
    File.write(File.join(@root, 'package.yaml'), "name: app\n")
    error = assert_raises(Crosspack::InvalidManifestError) { pack('debian-12') }
    assert_includes error.message, 'package.yaml'
  end

  def test_pack_unsupported_format
    skip 'all families now have builders; test kept for future formats'
    error = assert_raises(Crosspack::BuildError) { pack('macos') }
    assert_includes error.message, 'macos'
    assert_includes error.message, 'not defined'
  end

  def test_pack_windows_generates_wix_sources
    path = pack('windows-11.0')
    assert path.end_with?('.wxs'), "expected .wxs fallback artifact, got #{path}"
    assert_includes path, File.join('crosspacks', 'windows', '11.0', 'x86_64')

    content = File.read(path)
    assert_includes content, '<Wix xmlns="http://wixtoolset.org/schemas/v4/wxs">'
    assert_includes content, 'Name="app"'
    assert_includes content, 'ProgramFiles64Folder'
    assert_includes content, 'Source='
    assert File.file?(File.join(File.dirname(path), 'BUILD-MSI.txt'))
  end

  def test_pack_macos_stages_app_bundle
    path = pack('macos')
    # pack returns the .app bundle directory itself.
    assert File.directory?(path)
    assert path.end_with?('app.app')
    assert_includes path, File.join('crosspacks', 'macos', 'x86_64')
    assert File.file?(File.join(path, 'Contents', 'MacOS', 'app'))
    assert File.file?(File.join(path, 'Contents', 'MacOS', 'model.bin'))
    assert File.file?(File.join(path, 'Contents', 'Info.plist'))
    assert File.file?(File.join(File.dirname(path), 'BUILD-DMG.txt'))

    plist = File.read(File.join(path, 'Contents', 'Info.plist'))
    assert_includes plist, '<key>CFBundleExecutable</key>'
    assert_includes plist, '<string>app</string>'
  end
end
