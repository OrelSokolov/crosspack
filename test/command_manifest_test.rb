# frozen_string_literal: true

require_relative 'test_helper'

class CommandManifestTest < Minitest::Test
  include ConfigHelper

  def test_absent_section_is_valid_and_silent
    m = load_config_section('run', '').run_manifest
    refute m.present?
    assert m.valid?
    assert_nil m.command_for(%w[ubuntu linux *])
  end

  def test_valid_hosts_and_selector_priority
    m = load_manifest(<<~YAML)
      hosts:
        darwin: open {{path}}
        ubuntu: "{{path}} --ubuntu"
        linux: "{{path}} --linux"
        "*": "{{path}} --any"
    YAML
    assert m.valid?
    assert_equal '{{path}} --ubuntu', m.command_for(%w[ubuntu linux *])
    assert_equal '{{path}} --linux', m.command_for(%w[fedora linux *])
    assert_equal '{{path}} --any', m.command_for(%w[*])
    assert_equal 'open {{path}}', m.command_for(%w[darwin *])
    assert_nil m.command_for([])
  end

  def test_unknown_section_key
    m = load_manifest("hosts: {}\ncommand: {{path}}\n")
    refute m.valid?
    assert_includes m.error_report, 'run.command: unknown key'
  end

  def test_hosts_must_be_a_mapping
    m = load_manifest("hosts: [{{path}}]\n")
    refute m.valid?
    assert_includes m.error_report, 'run.hosts: must be a non-empty mapping'
  end

  def test_empty_command_is_invalid
    m = load_manifest("hosts:\n  ubuntu: ''\n")
    refute m.valid?
    assert_includes m.error_report, "run.hosts.ubuntu: must be a non-empty shell command"
  end

  def test_bad_selector_is_invalid
    m = load_manifest("hosts:\n  ubuntu 24.04: {{path}}\n")
    refute m.valid?
    assert_includes m.error_report, 'invalid host selector'
  end

  def test_section_must_be_a_mapping
    m = Crosspack::CommandManifest.new('/x/crosspack.yml', ['nope'], 'run')
    refute m.valid?
    assert_includes m.error_report, 'run: must be a non-empty mapping'
  end

  def test_validate_raises_with_report
    m = load_manifest("hosts:\n  ubuntu: ''\n")
    e = assert_raises(Crosspack::InvalidManifestError) { m.validate! }
    assert_includes e.message, 'run.hosts.ubuntu'
  end

  private

  def load_manifest(yaml_text)
    load_config_section('run', yaml_text).run_manifest
  end
end
