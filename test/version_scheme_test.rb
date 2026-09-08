# frozen_string_literal: true

require_relative 'test_helper'

class VersionSchemeTest < Minitest::Test
  def test_calver_matches_hvoice_format
    now = Time.local(2026, 8, 31, 9, 24, 12)
    version = Crossbuild::VersionScheme.new('calver').compute(now: now)
    assert_equal '2026.08.31-33852', version
  end

  def test_nil_defaults_to_calver
    now = Time.local(2026, 1, 2, 0, 0, 0)
    assert_equal '2026.01.02-0', Crossbuild::VersionScheme.new(nil).compute(now: now)
  end

  def test_git_tag
    Dir.mktmpdir('crossbuild-git') do |dir|
      system('git init -q', chdir: dir) or flunk 'git init failed'
      system('git commit --allow-empty -m init -q', chdir: dir) or flunk 'git commit failed'
      system('git tag v1.2.3', chdir: dir) or flunk 'git tag failed'
      assert_equal 'v1.2.3', Crossbuild::VersionScheme.new('git-tag').compute(root: dir)
    end
  end

  def test_git_tag_fallback_without_repo
    Dir.mktmpdir('crossbuild-nogit') do |dir|
      assert_equal '0.0.0-dev', Crossbuild::VersionScheme.new('git-tag').compute(root: dir)
    end
  end

  def test_env_scheme
    ENV['APP_TEST_VERSION'] = '3.4.5'
    assert_equal '3.4.5', Crossbuild::VersionScheme.new('env:APP_TEST_VERSION').compute
  ensure
    ENV.delete('APP_TEST_VERSION')
  end

  def test_env_scheme_missing_var_raises
    error = assert_raises(Crossbuild::VersionScheme::Error) do
      Crossbuild::VersionScheme.new('env:APP_UNSET_VERSION').compute
    end
    assert_includes error.message, 'APP_UNSET_VERSION'
  end

  def test_literal_string
    assert_equal '1.0.0', Crossbuild::VersionScheme.new('1.0.0').compute
  end
end
