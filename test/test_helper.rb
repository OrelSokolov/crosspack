# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'crosspack'

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'

module ManifestHelper
  # Loads a deps.yaml from a heredoc string, writing it to a temp file so
  # error messages carry a realistic path.
  def load_manifest(yaml_text)
    file = File.join(@tmpdir ||= Dir.mktmpdir('crosspack-test'), 'deps.yaml')
    File.write(file, yaml_text)
    Crosspack::Manifest.load(file)
  end
end
