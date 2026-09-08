# frozen_string_literal: true

require_relative 'test_helper'

class PlatformTest < Minitest::Test
  def test_os_is_a_known_symbol
    assert_includes %i[linux darwin windows], Crossbuild::Platform.os
  end

  def test_arch_is_a_known_symbol
    assert_includes %i[x86_64 arm64], Crossbuild::Platform.arch
  end

  def test_to_s_form
    assert_match(/\A(linux|darwin|windows)\/(amd64|arm64)\z/, Crossbuild::Platform.to_s)
  end

  def test_display_arch
    assert_equal 'amd64', Crossbuild::Platform.display_arch(:x86_64)
    assert_equal 'arm64', Crossbuild::Platform.display_arch(:arm64)
  end
end
