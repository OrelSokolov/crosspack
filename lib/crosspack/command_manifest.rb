# frozen_string_literal: true

module Crosspack
  # Parses and validates the optional run:/install: sections of crosspack.yml.
  # Both map host selectors (the same vocabulary as the deps: rules of the
  # build: section: distro id from os-release, ID_LIKE token, os name, "*")
  # to a shell command with {{path}} and the usual build facts:
  #
  #   run:
  #     hosts:
  #       darwin: open build/bin/MyApp.app
  #       "*": "{{path}} --dev"
  #
  # A section is optional; when absent the host-only default applies
  # (see Launcher).
  class CommandManifest
    SECTION_KEYS = %w[hosts].freeze
    # A host selector: "*" or a distro id / ID_LIKE token / os name —
    # the same vocabulary as the deps: rules of the build: section.
    SELECTOR_RE = /\A(\*|[a-z0-9][a-z0-9+._-]*)\z/i.freeze

    attr_reader :path, :section, :errors, :warnings

    def initialize(path, raw, section)
      @path = path
      @section = section
      @raw = raw
      @hosts = {}
      @errors = []
      @warnings = []
      validate
    end

    def present?
      !@raw.nil?
    end

    def valid?
      @errors.empty?
    end

    # The command for the given host selectors (see Crossbuild::Platform
    # .selectors), first match wins; nil when nothing applies.
    def command_for(selectors)
      selectors.each { |s| return @hosts[s] if @hosts.key?(s) }
      nil
    end

    def error_report
      return "#{@path}: the #{@section}: section is absent — defaults apply" unless present?

      lines = ["#{@path}: the #{@section}: section is #{@errors.empty? ? 'valid' : "invalid (#{@errors.size} errors)"}:"]
      @errors.each { |e| lines << "  ✗ #{e}" }
      @warnings.each { |w| lines << "  ⚠ #{w}" }
      lines.join("\n")
    end

    def validate!
      return self if valid?

      raise InvalidManifestError, error_report
    end

    private

    def validate
      return unless present?

      unless @raw.is_a?(Hash) && !@raw.empty?
        @errors << Issue.new("#{@section}", "must be a non-empty mapping with the key: hosts; expected:\n" \
                                            "    #{@section}:\n" \
                                            "      hosts:\n" \
                                            "        ubuntu: #{@section == 'install' ? 'xdg-open {{path}}' : '{{path}} --dev'}")
        return
      end
      check_unknown_keys

      hosts = @raw['hosts']
      return unless hosts

      unless hosts.is_a?(Hash) && !hosts.empty?
        @errors << Issue.new("#{@section}.hosts", 'must be a non-empty mapping of host selector -> shell command')
        return
      end

      hosts.each do |selector, command|
        validate_rule(selector.to_s, command)
      end
    end

    def check_unknown_keys
      @raw.keys.map(&:to_s).each do |key|
        next if SECTION_KEYS.include?(key)

        @errors << Issue.new("#{@section}.#{key}", "unknown key; allowed: #{SECTION_KEYS.join(', ')}")
      end
    end

    def validate_rule(selector, command)
      path = "#{@section}.hosts.#{selector}"
      unless selector =~ SELECTOR_RE
        @errors << Issue.new(path, "invalid host selector (expected a distro id, os name or \"*\")")
        return
      end
      unless command.is_a?(String) && !command.strip.empty?
        @errors << Issue.new(path, 'must be a non-empty shell command')
      end
      @hosts[selector] = command if command.is_a?(String) && !command.strip.empty?
    end
  end
end
