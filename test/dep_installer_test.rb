# frozen_string_literal: true

require_relative 'test_helper'

class DepInstallerTest < Minitest::Test
  SELECTORS = ['ubuntu', 'debian', 'linux', '*'].freeze

  def test_distro_selector_wins_over_os_and_wildcard
    Dir.mktmpdir('crossbuild-deps') do |dir|
      installer = new_installer(dir, hosts: "ubuntu: {verify: test -f u, install: touch u}\n" \
                                           'linux: {install: touch l}' \
                                           "\n\"*\": {install: touch a}")
      installer.ensure_all
      assert File.exist?(File.join(dir, 'u'))
      refute File.exist?(File.join(dir, 'l'))
      refute File.exist?(File.join(dir, 'a'))
      assert_equal 'ubuntu', installer.statuses.first.selector
    end
  end

  def test_falls_back_to_os_selector
    Dir.mktmpdir('crossbuild-deps') do |dir|
      installer = new_installer(dir, hosts: 'linux: {verify: test -f l, install: touch l}')
      installer.ensure_all
      assert File.exist?(File.join(dir, 'l'))
    end
  end

  def test_no_rule_raises_with_described_selectors
    Dir.mktmpdir('crossbuild-deps') do |dir|
      installer = new_installer(dir, hosts: "darwin: {install: brew install imagemagick}\n" \
                                           'windows: {install: winget install imagemagick}')
      error = assert_raises(Crossbuild::DepInstaller::DepError) { installer.ensure_all }
      assert_includes error.message, 'selectors tried: ubuntu, debian, linux, *'
      assert_includes error.message, 'described: darwin, windows'
    end
  end

  def test_present_dependency_skips_install
    Dir.mktmpdir('crossbuild-deps') do |dir|
      FileUtils.touch(File.join(dir, 'marker'))
      installer = new_installer(dir, hosts: '"*": {verify: test -f marker, install: touch should_not_exist}')
      installer.ensure_all
      refute File.exist?(File.join(dir, 'should_not_exist'))
      assert installer.statuses.first.installed
    end
  end

  def test_install_then_reverify_succeeds
    Dir.mktmpdir('crossbuild-deps') do |dir|
      installer = new_installer(dir, hosts: '"*": {verify: test -f marker, install: touch marker}')
      installer.ensure_all
      assert File.exist?(File.join(dir, 'marker'))
    end
  end

  def test_still_missing_after_install_raises
    Dir.mktmpdir('crossbuild-deps') do |dir|
      installer = new_installer(dir, hosts: '"*": {verify: test -f nope, install: touch other}')
      error = assert_raises(Crossbuild::DepInstaller::DepError) { installer.ensure_all }
      assert_includes error.message, 'still fails'
      assert_includes error.message, 'test -f nope'
    end
  end

  def test_failed_install_command_raises
    Dir.mktmpdir('crossbuild-deps') do |dir|
      installer = new_installer(dir, hosts: '"*": {verify: test -f nope, install: exit 7}')
      error = assert_raises(Crossbuild::DepInstaller::DepError) { installer.ensure_all }
      assert_includes error.message, 'install command failed'
      assert_includes error.message, 'exit 7'
    end
  end

  def test_verify_only_rule_without_install_raises_when_missing
    Dir.mktmpdir('crossbuild-deps') do |dir|
      installer = new_installer(dir, hosts: '"*": {verify: test -f nope}')
      error = assert_raises(Crossbuild::DepInstaller::DepError) { installer.ensure_all }
      assert_includes error.message, 'no install command'
      assert_includes error.message, 'deps.marker.hosts.*.install'
      refute File.exist?(File.join(dir, 'nope'))
    end
  end

  def test_verify_only_rule_ok_when_present
    Dir.mktmpdir('crossbuild-deps') do |dir|
      FileUtils.touch(File.join(dir, 'marker'))
      installer = new_installer(dir, hosts: '"*": {verify: test -f marker}')
      installer.ensure_all
      assert installer.statuses.first.installed
      assert_includes installer.report, 'verify only'
    end
  end

  def test_check_all_never_installs
    Dir.mktmpdir('crossbuild-deps') do |dir|
      installer = new_installer(dir, hosts: '"*": {verify: test -f marker, install: touch marker}')
      installer.check_all
      refute File.exist?(File.join(dir, 'marker'))
      refute installer.statuses.first.installed
      assert_includes installer.report, 'MISSING'
    end
  end

  def test_default_verify_probes_path
    Dir.mktmpdir('crossbuild-deps') do |dir|
      installer = new_installer(dir, name: 'ls', hosts: '"*": {install: exit 1}') # never runs: ls is on PATH
      installer.ensure_all
      assert installer.statuses.first.installed
    end
  end

  def test_placeholders_expand_in_both_commands
    Dir.mktmpdir('crossbuild-deps') do |dir|
      installer = new_installer(dir, name: 'app',
                                      hosts: '"*": {verify: test -f who.txt, install: \'echo {{name}} > who.txt\'}')
      installer.ensure_all
      assert_equal "app\n", File.read(File.join(dir, 'who.txt'))
    end
  end

  def test_report_without_deps
    Dir.mktmpdir('crossbuild-deps') do |dir|
      manifest = load_manifest(dir, 'name: app')
      installer = Crossbuild::DepInstaller.new(manifest, root: dir, selectors: SELECTORS)
      assert_includes installer.report, 'no deps declared'
    end
  end

  private

  # Builds a manifest with a single dependency named `name` (default marker)
  # and runs DepInstaller against it in dir. `hosts` is the raw YAML body of
  # the hosts: mapping (selector -> {verify?, install?}).
  def new_installer(dir, hosts:, name: 'marker')
    dep = +"deps:\n  #{name}:\n    hosts:\n"
    hosts.each_line { |line| dep << "      #{line.strip}\n" unless line.strip.empty? }
    manifest = load_manifest(dir, "name: app\n#{dep}matrix:\n  - build: linux/amd64\n    steps: ['true']\n")
    Crossbuild::DepInstaller.new(manifest, root: dir, selectors: SELECTORS)
  end

  def load_manifest(dir, body)
    file = File.join(dir, 'crosspack.yml')
    File.write(file, "name: app\nbuild:\n#{body.lines.map { |l| l.strip.empty? ? "\n" : "  #{l}" }.join}")
    Crosspack::Config.load(file).build_manifest
  end
end
