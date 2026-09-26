# frozen_string_literal: true

require_relative 'test_helper'
require 'open3'
require 'tmpdir'

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

    File.write(File.join(@root, 'crosspack.yml'), <<~YAML)
      name: app
      package:
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
          categories: Utility;Audio
        icon: build/icon.png
      deps:
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
      config: File.join(@root, 'crosspack.yml'),
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

    # The staged .desktop is spec-conformant: every Categories value is
    # terminated with ";" (the manifest says "Utility;Audio").
    Dir.mktmpdir do |x|
      Open3.capture2e('dpkg-deb', '-x', path, x)
      entry = File.read(File.join(x, 'usr/local/share/applications/app.desktop'))
      assert_includes entry, 'Categories=Utility;Audio;'
      assert_includes entry, 'Icon=app'
      assert_includes entry, 'Name=App'
    end
  end

  def test_pack_deb_svg_icon_goes_to_hicolor
    File.write(File.join(@root, 'build', 'icon.svg'), '<svg/>')
    yml = File.read(File.join(@root, 'crosspack.yml')).sub('icon: build/icon.png',
                                                           'icon: build/icon.svg')
    File.write(File.join(@root, 'crosspack.yml'), yml)

    path = pack('debian-12')
    listing, = Open3.capture2e('dpkg-deb', '-c', path)
    # An SVG named .png in pixmaps would never be found; it belongs to the
    # hicolor scalable theme dir.
    assert_includes listing, 'usr/local/share/icons/hicolor/scalable/apps/app.svg'
    refute_includes listing, 'pixmaps'
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
    # Desktop integration must not be deb/rpm-only: the .desktop file and
    # the icon are installed on arch too.
    assert_includes content,
                     'install -Dm644 "$srcdir/$pkgname-$pkgver/app.desktop" "$pkgdir/usr/local/share/applications/app.desktop"'
    assert_includes content,
                     'install -Dm644 "$srcdir/$pkgname-$pkgver/icon.png" "$pkgdir/usr/local/share/pixmaps/app.png"'
    assert_includes content, "license=('Proprietary')"
  end

  def test_pack_missing_build_dir_gives_actionable_error
    error = assert_raises(Crosspack::BuildError) { pack('debian-13') }
    assert_includes error.message, 'Build stage not done for target debian-13'
    assert_includes error.message, 'builds/debian/13/amd64'
    assert_includes error.message, 'crosspack build debian-13'
  end

  def test_pack_version_defaults_to_build_stamp
    stamp = File.join(@root, 'builds', 'debian', '12', 'amd64', Crossbuild::Distributor::STAMP_NAME)
    File.write(stamp, "7.7.7\n")
    path = Crosspack.pack(
      config: File.join(@root, 'crosspack.yml'),
      target: Crosspack::Target.parse('debian-12'),
      version: nil,
      root: @root,
      output_base: File.join(@root, 'crosspacks')
    )
    assert_includes File.basename(path), '7.7.7'
  end

  def test_pack_without_version_and_stamp_raises_stage_hint
    error = assert_raises(Crosspack::BuildError) do
      Crosspack.pack(
        config: File.join(@root, 'crosspack.yml'),
        target: Crosspack::Target.parse('arch'),
        version: nil,
        root: @root,
        output_base: File.join(@root, 'crosspacks')
      )
    end
    assert_includes error.message, 'no build stamp'
    assert_includes error.message, 'crosspack build arch'
    assert_includes error.message, '--version'
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
    File.write(File.join(@root, 'crosspack.yml'), "name: app\npackage:\n  summary: x\n")
    error = assert_raises(Crosspack::InvalidManifestError) { pack('debian-12') }
    assert_includes error.message, 'the package: section'
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
    assert_includes content, '<Wix xmlns="http://wixtoolset.org/schemas/v4/wxs"'
    assert_includes content, 'xmlns:ui="http://wixtoolset.org/schemas/v4/wxs/ui"'
    assert_includes content, 'Name="app"'
    assert_includes content, 'ProgramFiles64Folder'
    assert_includes content, 'Source='
    # The directory Id must be INSTALLFOLDER (anything else makes WiX add a
    # phantom "[Manufacturer] [ProductName]" directory, error 1324 on install).
    assert_includes content, '<Directory Id="INSTALLFOLDER" Name="app" />'
    refute_includes content, 'Id="INSTALLDIR"'
    # Maintainer keeps only the name half: the deb-style "<email>" must not
    # reach the MSI Manufacturer property.
    assert_includes content, 'Manufacturer="Test"'
    refute_includes content, '<t@example.com>'
    # Install wizard (WixUI_InstallDir) + its license file.
    assert_includes content, '<Property Id="WixUILicenseRtf" Value="app-license.rtf" />'
    assert_includes content, '<ui:WixUI Id="WixUI_InstallDir" InstallDirectory="INSTALLFOLDER" />'
    assert File.file?(File.join(File.dirname(path), 'app-license.rtf'))
    # Start Menu / Desktop shortcuts from desktop:/executables:.
    assert_includes content, 'Id="StartMenuShortcut" Directory="ProgramMenuFolder"'
    assert_includes content, 'Id="DesktopShortcut" Directory="DesktopFolder"'
    assert_includes content, 'Name="App" Target="[INSTALLFOLDER]app"'
    assert_includes content, '<RegistryValue Root="HKLM" Key="Software\App"'
    assert_includes content, 'KeyPath="yes"'
    assert File.file?(File.join(File.dirname(path), 'BUILD-MSI.txt'))
  end

  def test_pack_windows_resolves_payload_names
    win_dir = File.join(@root, 'builds', 'windows', '11.0', 'x86_64')
    File.delete(File.join(win_dir, 'app'))
    File.delete(File.join(win_dir, 'model.bin'))
    File.write(File.join(win_dir, 'app.exe'), 'exe')
    File.write(File.join(win_dir, 'model.onnx'), 'model')
    File.write(File.join(win_dir, 'onnxruntime.dll'), 'dll')
    File.write(File.join(@root, 'crosspack.yml'), <<~YAML)
      name: app
      package:
        maintainer: Test <t@example.com>
        description: |-
          Test app
        sources: builds
        prefix: usr/local
        payload:
          app:
            "*": app
            windows: app.exe
          model.onnx:
          onnxruntime.dll:
            windows: onnxruntime.dll
        executables: [app]
      deps:
        webkit2gtk:
          targets:
            debian:
              "12": [libwebkit2gtk-4.1-0]
            windows: system
    YAML

    path = pack('windows-11.0')
    content = File.read(path)
    assert path.end_with?('.wxs')
    assert_includes content, 'app.exe'
    assert_includes content, 'onnxruntime.dll'
    assert_includes content, 'model.onnx'
    # Shortcuts resolve through the payload map too: app -> app.exe.
    assert_includes content, 'Target="[INSTALLFOLDER]app.exe"'
    # The unix name must not leak into the Windows payload.
    refute_includes content, 'x86_64\\app"'
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
    # Display name from desktop:, icon from the manifest, no raw &/<>& in
    # the XML.
    assert_includes plist, '<key>CFBundleDisplayName</key>'
    assert_includes plist, '<string>App</string>'
    assert_includes plist, '<key>CFBundleIconFile</key>'
    assert_includes plist, '<string>icon.png</string>'
    assert File.file?(File.join(path, 'Contents', 'Resources', 'icon.png'))
  end
end
