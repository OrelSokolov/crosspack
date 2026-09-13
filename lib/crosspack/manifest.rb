# frozen_string_literal: true

module Crosspack
  # Canonical dependency names crosspack knows about. Anything else in the
  # deps: section still resolves, but produces a warning (possible typo).
  KNOWN_CANONICAL = %w[
    webkit2gtk gtk3 openmp ayatana-appindicator
    glib2 cairo pango gdk-pixbuf alsa-lib pulseaudio dbus
  ].freeze

  # Scalar verdicts a target may carry instead of a package list.
  VERDICTS = %w[system none bundled].freeze

  CANONICAL_NAME_RE = /\A[a-z0-9][a-z0-9+._-]*\z/.freeze

  # A single schema problem: full path into the deps: section + human
  # explanation.
  class Issue
    attr_reader :path, :message

    def initialize(path, message)
      @path = path
      @message = message
    end

    def to_s
      "#{@path}: #{@message}"
    end
  end

  class InvalidManifestError < StandardError; end

  # Parses and validates the deps: section of crosspack.yml. Keys are
  # canonical dependency names; each maps to
  # { targets: { family: { "version": [pkgs] } } } or a scalar verdict for a
  # whole family. A reserved `version:` key inside the section declares the
  # schema version (see SCHEMA_VERSION).
  class Manifest
    # The deps: section schema version this crosspack understands. Sections
    # declaring a newer version are rejected at load time with an upgrade
    # hint; older (or absent) versions are accepted.
    SCHEMA_VERSION = 1

    attr_reader :path, :deps, :schema_version, :errors, :warnings

    def initialize(path, raw)
      @path = path
      @schema_version = raw.is_a?(Hash) ? raw['version'] : nil
      @errors = []
      @warnings = []
      check_schema_version!
      @deps = raw.is_a?(Hash) ? raw.reject { |key, _| key == 'version' } : {}
      @raw = raw
      validate
    end

    def valid?
      @errors.empty?
    end

    # Raises with the full, formatted list of problems.
    def validate!
      return self if valid?

      lines = ["#{path}: the deps: section is invalid (#{@errors.size} errors):"]
      @errors.each { |e| lines << "  ✗ #{e}" }
      lines << 'Build aborted: fix the listed nodes and retry.'
      raise InvalidManifestError, lines.join("\n")
    end

    # Report used by rake abort: errors (if any) plus warnings.
    def error_report
      lines = []
      if valid?
        lines << "#{path}: the deps: section is valid."
      else
        lines << "#{path}: the deps: section is invalid (#{@errors.size} errors):"
        @errors.each { |e| lines << "  ✗ #{e}" }
      end
      @warnings.each { |w| lines << "  ⚠ #{w}" }
      lines.join("\n")
    end

    private

    # A schema version newer than this crosspack supports is a hard, loud
    # error at load time — every command (resolve, matrix, pack) reports it,
    # not just validate. Malformed versions (not an integer >= 1) are
    # ordinary schema errors.
    def check_schema_version!
      v = @schema_version
      return if v.nil?

      unless v.is_a?(Integer) && v >= 1
        @errors << Issue.new('version', "schema version must be an integer >= 1, got #{v.inspect}")
        return
      end
      return if v <= SCHEMA_VERSION

      raise InvalidManifestError,
            "#{@path}: the deps: section declares schema version #{v}, " \
            "but this crosspack (#{Crosspack::VERSION}) supports up to #{SCHEMA_VERSION}. " \
            'Update the gem (gem update crosspack) or lower the declared version.'
    end

    def validate
      unless @raw.is_a?(Hash) && !@raw.empty?
        @errors << Issue.new(
          '(root)',
          'the deps: section of crosspack.yml is missing or empty — ' \
          'it must map canonical names to per-distro packages'
        )
        return
      end
      @raw.each { |name, body| validate_dep(name.to_s, body) unless name == 'version' }
    end

    def validate_dep(name, body)
      if name !~ CANONICAL_NAME_RE
        @errors << Issue.new(
          name,
          "invalid canonical name #{name.inspect} " \
          '(lowercase letters, digits, "-", "_", "."; must start with a letter or digit)'
        )
      end
      unless KNOWN_CANONICAL.include?(name)
        @warnings << Issue.new(
          name,
          'unknown to crosspack — not an error if the rules below are correct (possible typo?)'
        )
      end
      unless body.is_a?(Hash) && body.key?('targets')
        @errors << Issue.new(
          name,
          "missing required field targets; expected:\n" \
          "    #{name}:\n      targets:\n        debian:\n          \"12\": [package]"
        )
        return
      end

      targets = body['targets']
      unless targets.is_a?(Hash) && !targets.empty?
        @errors << Issue.new(
          "#{name}.targets",
          "must be a non-empty mapping: family -> rules (debian, ubuntu, fedora, ...)"
        )
        return
      end
      targets.each { |family, rules| validate_family(name, family.to_s, rules) }
    end

    def validate_family(name, family, rules)
      path = "#{name}.targets.#{family}"
      known = Target::FAMILIES.map(&:to_s)
      unless known.include?(family)
        suggestion = suggest(family, known)
        hint = suggestion ? " (did you mean #{suggestion.inspect}?)" : ''
        @errors << Issue.new(
          path,
          "unknown distro family #{family.inspect}#{hint}; " \
          "allowed: #{known.join(', ')}"
        )
        return
      end

      if rules.is_a?(String)
        validate_verdict(path, rules)
        return
      end
      unless rules.is_a?(Hash) && !rules.empty?
        @errors << Issue.new(
          path,
          "expected a mapping { \"version\": [packages], ... } or a scalar: #{VERDICTS.join(' / ')}"
        )
        return
      end

      rules.each do |version, value|
        vpath = "#{path}.#{version.inspect}"
        unless version.is_a?(String)
          @errors << Issue.new(
            vpath,
            "version key must be a quoted string: \"#{version}\" — " \
            'without quotes YAML parses it as a number'
          )
          next
        end
        if value.is_a?(String)
          validate_verdict(vpath, value)
        elsif value.is_a?(Array)
          validate_package_list(vpath, value)
        else
          @errors << Issue.new(
            vpath,
            "value must be a list of packages [pkg, ...] or a scalar: #{VERDICTS.join(' / ')}"
          )
        end
      end
    end

    def validate_verdict(path, value)
      return if VERDICTS.include?(value)

      @errors << Issue.new(
        path,
        "unknown verdict #{value.inspect}; allowed: #{VERDICTS.join(' / ')}"
      )
    end

    def validate_package_list(path, value)
      if value.empty?
        @errors << Issue.new(
          path,
          'package list is empty — specify at least one package or the none verdict'
        )
        return
      end
      value.each_with_index do |pkg, i|
        next if pkg.is_a?(String) && !pkg.strip.empty? && pkg == pkg.strip

        @errors << Issue.new(
          "#{path}[#{i}]",
          'package name must be a non-empty string without surrounding whitespace'
        )
      end
    end

    def suggest(word, candidates)
      best = candidates.min_by { |c| levenshtein(word, c) }
      distance = levenshtein(word, best)
      distance <= 2 ? best : nil
    end

    def levenshtein(a, b)
      prev = (0..b.length).to_a
      a.chars.each_with_index do |ca, i|
        curr = [i + 1]
        b.chars.each_with_index do |cb, j|
          cost = ca == cb ? 0 : 1
          curr[j + 1] = [
            curr[j] + 1,        # insertion
            prev[j + 1] + 1,    # deletion
            prev[j] + cost      # substitution
          ].min
        end
        prev = curr
      end
      prev[b.length]
    end
  end
end
