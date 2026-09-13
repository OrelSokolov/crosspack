# frozen_string_literal: true

require_relative 'test_helper'

class ColorsTest < Minitest::Test
  def teardown
    Crosspack::Colors.enabled = nil
    ENV.delete('NO_COLOR')
  end

  def test_wraps_text_when_enabled
    Crosspack::Colors.enabled = true
    assert_equal "\e[0;32;49mok\e[0m", Crosspack::Colors.green('ok')
    assert_equal "\e[0;31;49mboom\e[0m", Crosspack::Colors.red('boom')
    assert_equal "\e[0;33;49mwarn\e[0m", Crosspack::Colors.yellow('warn')
  end

  def test_plain_text_when_disabled
    Crosspack::Colors.enabled = false
    assert_equal 'ok', Crosspack::Colors.green('ok')
    assert_equal 'boom', Crosspack::Colors.red('boom')
  end

  def test_no_color_env_disables
    Crosspack::Colors.enabled = nil
    ENV['NO_COLOR'] = '1'
    refute Crosspack::Colors.enabled?
  end
end
