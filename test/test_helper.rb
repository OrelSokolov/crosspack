# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'crosspack'
require 'crossbuild'

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'stringio'

module ConfigHelper
  # Writes a crosspack.yml with `top` (default: just the name) plus the
  # given body indented under `key:` and loads it, so error messages carry
  # a realistic path.
  def load_config_section(key, body, top = "name: app\n")
    dir = (@tmpdir ||= Dir.mktmpdir('crosspack-test'))
    file = File.join(dir, 'crosspack.yml')
    File.write(file, "#{top}#{key}:\n#{indent(body)}")
    Crosspack::Config.load(file)
  end

  private

  def indent(text)
    text.lines.map { |l| l.strip.empty? ? "\n" : "  #{l}" }.join
  end
end

module ManifestHelper
  include ConfigHelper

  # Loads a deps: section from a heredoc string.
  def load_manifest(yaml_text)
    load_config_section('deps', yaml_text).deps_manifest
  end
end

module BuildManifestHelper
  include ConfigHelper

  # Loads a build: section from a heredoc string.
  def load_manifest(yaml_text)
    load_config_section('build', yaml_text).build_manifest
  end
end
