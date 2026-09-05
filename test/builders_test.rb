# frozen_string_literal: true

require_relative 'test_helper'

class BuildersTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('crosspack-builders')
    @bin = File.join(@tmpdir, 'app')
    File.write(@bin, "#!/bin/sh\necho hi\n")
    File.chmod(0o755, @bin)
    @asset = File.join(@tmpdir, 'model.bin')
    File.write(@asset, 'model-bytes')
  end

  def teardown
    FileUtils.remove_entry(@tmpdir)
  end

  def test_deb_end_to_end
    output = File.join(@tmpdir, 'out', 'app_1.0_amd64.deb')
    result = Crosspack::Builders::Deb.build(
      name: 'app', version: '1.0', architecture: 'amd64',
      maintainer: 'Test <t@example.com>',
      description: "Test app\nSecond line of description",
      depends: 'libwebkit2gtk-4.1-0 | libwebkit2gtk-4.0-37, libgtk-3-0',
      files: { @bin => 'usr/lib/app/app', @asset => 'usr/lib/app/model.bin' },
      symlinks: { 'usr/bin/app' => '../lib/app/app' },
      executables: ['usr/lib/app/app'],
      output: output
    )
    assert File.file?(result), 'deb file was not produced'

    control, = Open3.capture2e('dpkg-deb', '-f', result)
    assert_includes control, 'Package: app'
    assert_includes control, 'Version: 1.0'
    assert_includes control, 'Architecture: amd64'
    assert_includes control, 'Depends: libwebkit2gtk-4.1-0 | libwebkit2gtk-4.0-37, libgtk-3-0'
    assert_includes control, 'Description: Test app'
    assert_includes control, ' Second line of description'

    listing, = Open3.capture2e('dpkg-deb', '-c', result)
    assert_includes listing, 'usr/lib/app/app'
    assert_includes listing, 'usr/bin/app'
  end

  def test_deb_missing_source_reports_every_file
    error = assert_raises(Crosspack::BuildError) do
      Crosspack::Builders::Deb.build(
        name: 'app', version: '1.0', architecture: 'amd64',
        maintainer: 'T <t@e.com>', description: 'x', depends: '',
        files: { File.join(@tmpdir, 'nope1') => 'usr/lib/app/a',
                 File.join(@tmpdir, 'nope2') => 'usr/lib/app/b' },
        output: File.join(@tmpdir, 'x.deb')
      )
    end
    assert_includes error.message, 'nope1'
    assert_includes error.message, 'nope2'
    assert_includes error.message, 'Build the application'
  end

  def test_rpm_spec_contains_resolved_requires_and_files
    spec = Crosspack::Builders::Rpm.generate_spec(
      name: 'app', version: '2026.08.31', release: '1234',
      summary: 'Test app', license: 'Proprietary',
      requires: ['webkit2gtk4.1', 'libayatana-appindicator-gtk3'],
      files: { @bin => 'usr/local/lib/app/app' },
      symlinks: { 'usr/local/bin/app' => '../lib/app/app' }
    )
    assert_includes spec, 'Name: app'
    assert_includes spec, 'Version: 2026.08.31'
    assert_includes spec, 'Release: 1234'
    assert_includes spec, 'AutoReqProv: no'
    assert_includes spec, 'Requires: webkit2gtk4.1, libayatana-appindicator-gtk3'
    assert_includes spec, '%dir /usr/local/lib/app'
    assert_includes spec, '/usr/local/lib/app/app'
    assert_includes spec, '/usr/local/bin/app'
    refute_includes spec.lines, "%dir /usr\n", 'must not claim ownership of /usr'
    refute_includes spec.lines, "%dir /usr/local\n", 'must not claim ownership of /usr/local'
  end

  def test_rpm_requires_rpmbuild
    skip 'rpmbuild is not installed — only spec generation is checked' unless system('command -v rpmbuild > /dev/null 2>&1')

    error = assert_raises(Crosspack::BuildError) do
      Crosspack::Builders::Rpm.build(
        name: 'app', version: '1.0', release: '1', summary: 'x',
        license: 'Proprietary', requires: [],
        files: { File.join(@tmpdir, 'ghost') => 'usr/lib/app/a' },
        output: File.join(@tmpdir, 'x.rpm')
      )
    end
    assert_includes error.message, 'Source files for packing not found'
  end

  def test_pkgbuild_content
    output = File.join(@tmpdir, 'PKGBUILD')
    Crosspack::Builders::Pkgbuild.generate(
      name: 'app', version: '2026.08.31', release: '1234',
      pkgdesc: 'Test app', depends: ['webkit2gtk-4.1', 'gtk3'],
      arch: ['x86_64'],
      files: { 'app' => 'usr/local/lib/app/app', 'model.bin' => 'usr/local/lib/app/model.bin' },
      symlinks: { 'usr/local/bin/app' => '../lib/app/app' },
      executables: ['usr/local/lib/app/app'],
      source: ['app-2026.08.31.tar.gz'],
      output: output
    )
    content = File.read(output)
    assert_includes content, 'pkgname=app'
    assert_includes content, 'pkgver=2026.08.31'
    assert_includes content, "depends=('webkit2gtk-4.1' 'gtk3')"
    assert_includes content, "install -Dm755 \"$srcdir/$pkgname-$pkgver/app\" \"$pkgdir/usr/local/lib/app/app\""
    assert_includes content, 'install -Dm644'
    assert_includes content, 'ln -s ../lib/app/app "$pkgdir/usr/local/bin/app"'
  end
end
