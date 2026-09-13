# frozen_string_literal: true

require 'yaml'

module Crosspack
  # crosspack.yml — the single configuration file. The top level carries the
  # shared facts (name, version scheme) plus three sections:
  #   build:   what and where to build (the former build.yaml)
  #   package: what and how to pack   (the former package.yaml)
  #   deps:    runtime dependencies   (the former deps.yaml)
  # The shared name/version are injected into the build section and the name
  # into the package section; each section is then validated by its manifest
  # class (Crossbuild::BuildManifest, PackageManifest, Manifest). A missing
  # section yields a manifest whose root error names the section — gating
  # happens per section, not per file.
  class Config
    DEFAULT_PATH = 'crosspack.yml'
    TOP_LEVEL_KEYS = %w[name version build package deps run install].freeze
    NAME_RE = /\A[a-z0-9][a-z0-9+._-]*\z/i.freeze

    attr_reader :path, :errors, :warnings

    def self.load(path = DEFAULT_PATH)
      unless File.file?(path)
        raise InvalidManifestError,
              "crosspack.yml not found: #{path}\n" \
              'Create crosspack.yml in the project root (see crosspack/README.md).'
      end
      begin
        raw = YAML.safe_load(File.read(path), permitted_classes: [], aliases: false)
      rescue Psych::SyntaxError => e
        raise InvalidManifestError,
              "#{path}: YAML syntax error on line #{e.line}: #{e.problem}"
      end
      new(path, raw)
    end

    # A Config, or a path to crosspack.yml, -> Config. Relative paths are
    # resolved against root.
    def self.coerce(config, root: Dir.pwd)
      return config if config.is_a?(self)

      load(File.expand_path(config.to_s, root))
    end

    def initialize(path, raw)
      @path = path
      @raw = raw
      @errors = []
      @warnings = []
      validate
    end

    def valid?
      @errors.empty?
    end

    def error_report
      lines = []
      if valid?
        lines << "#{@path}: config is valid."
      else
        lines << "#{@path}: crosspack.yml is invalid (#{@errors.size} errors):"
        @errors.each { |e| lines << "  ✗ #{e}" }
      end
      @warnings.each { |w| lines << "  ⚠ #{w}" }
      lines.join("\n")
    end

    def build_manifest
      require_relative '../crossbuild' unless defined?(::Crossbuild::BuildManifest)

      @build_manifest ||= Crossbuild::BuildManifest.new(@path, build_section)
    end

    def package_manifest
      @package_manifest ||= PackageManifest.new(@path, package_section)
    end

    def deps_manifest
      @deps_manifest ||= Manifest.new(@path, deps_section)
    end

    # The optional run:/install: sections (host-only launch commands).
    def run_manifest
      @run_manifest ||= CommandManifest.new(@path, @raw['run'], 'run')
    end

    def install_manifest
      @install_manifest ||= CommandManifest.new(@path, @raw['install'], 'install')
    end

    private

    def validate
      unless @raw.is_a?(Hash) && !@raw.empty?
        @errors << Issue.new('(root)',
                             'crosspack.yml must be a non-empty mapping: name, version?, build:, package:, deps:')
        return
      end

      check_unknown_keys
      validate_name
      validate_version
      check_section_types
    end

    def check_unknown_keys
      @raw.keys.each do |key|
        next if TOP_LEVEL_KEYS.include?(key.to_s)

        @errors << Issue.new("(root).#{key}", "unknown key; allowed: #{TOP_LEVEL_KEYS.join(', ')}")
      end
    end

    def validate_name
      name = @raw['name']
      if name.nil?
        @errors << Issue.new('name', 'is required once at the top level, e.g. name: myapp')
      elsif !name.is_a?(String) || name.strip.empty? || name !~ NAME_RE
        @errors << Issue.new('name', "invalid name #{name.inspect} (letters, digits, \"+\", \"_\", \"-\", \".\")")
      end
    end

    def validate_version
      v = @raw['version']
      return if v.nil?

      unless v.is_a?(String) && !v.strip.empty?
        @errors << Issue.new('version',
                             "must be a string scheme: calver / git-tag / env:VAR or a literal, got #{v.inspect}")
      end
    end

    def check_section_types
      %w[build package deps run install].each do |key|
        next unless @raw.key?(key) && !@raw[key].is_a?(Hash)

        @errors << Issue.new(key, 'must be a mapping')
      end
    end

    def build_section
      base = section('build') or return nil

      { 'name' => top_name, 'version' => top_version }.merge(base)
    end

    def package_section
      base = section('package') or return nil

      { 'name' => top_name }.merge(base)
    end

    def deps_section
      section('deps')
    end

    def section(key)
      s = @raw.is_a?(Hash) ? @raw[key] : nil
      s.is_a?(Hash) && !s.empty? ? s : nil
    end

    def top_name
      @raw.is_a?(Hash) ? @raw['name'] : nil
    end

    def top_version
      v = @raw.is_a?(Hash) ? @raw['version'] : nil
      v.is_a?(String) && !v.strip.empty? ? v.strip : nil
    end
  end
end
