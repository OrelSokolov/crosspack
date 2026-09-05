# frozen_string_literal: true

require 'yaml'

module Crosspack
  # Packaging manifest (package.yaml): declares WHAT and HOW to pack —
  # payload, executables, symlinks, desktop entry, icon. Compilation is not
  # crosspack's business; artifacts are picked from `sources` as-is.
  class PackageManifest
    REQUIRED = %w[name maintainer description sources prefix payload].freeze
    OPTIONAL = %w[summary license section lib_dir executables links desktop icon].freeze

    attr_reader :path, :data, :errors, :warnings

    def self.load(path)
      unless File.file?(path)
        raise InvalidManifestError,
              "Packaging manifest not found: #{path}\n" \
              'Create package.yaml next to the Rakefile (see crosspack/README.md).'
      end
      begin
        raw = YAML.safe_load(File.read(path), permitted_classes: [], aliases: false)
      rescue Psych::SyntaxError => e
        raise InvalidManifestError,
              "#{path}: YAML syntax error on line #{e.line}: #{e.problem}"
      end
      new(path, raw)
    end

    def initialize(path, raw)
      @path = path
      @data = raw.is_a?(Hash) ? raw : {}
      @raw = raw
      @errors = []
      @warnings = []
      validate
    end

    def valid?
      @errors.empty?
    end

    def validate!
      return self if valid?

      lines = ["#{path}: package.yaml schema is invalid (#{@errors.size} errors):"]
      @errors.each { |e| lines << "  ✗ #{e}" }
      lines << 'Packing aborted: fix the listed nodes and retry.'
      raise InvalidManifestError, lines.join("\n")
    end

    def error_report
      if valid?
        "#{path}: schema is valid."
      else
        ["#{path}: package.yaml schema is invalid (#{@errors.size} errors):",
         *@errors.map { |e| "  ✗ #{e}" }].join("\n")
      end
    end

    # ---- typed accessors (validated values) ----

    def name
      @data['name']
    end

    def maintainer
      @data['maintainer']
    end

    def description
      @data['description'].to_s
    end

    def license
      @data['license'] || 'Proprietary'
    end

    def section
      @data['section'] || 'utils'
    end

    def sources
      @data['sources']
    end

    def prefix
      @data['prefix']
    end

    def payload
      Array(@data['payload'])
    end

    def executables
      Array(@data['executables'])
    end

    def summary
      @data['summary'] || description.lines.map(&:chomp).reject(&:empty?).first || name
    end

    def lib_dir
      @data['lib_dir'] || File.join('lib', name.to_s)
    end

    def links
      @data['links'].is_a?(Hash) ? @data['links'] : {}
    end

    def desktop
      @data['desktop'].is_a?(Hash) ? @data['desktop'] : nil
    end

    def icon
      @data['icon']
    end

    private

    def validate
      unless @raw.is_a?(Hash) && !@raw.empty?
        @errors << Issue.new('(root)', 'file must be a non-empty mapping: name, maintainer, payload, ...')
        return
      end

      REQUIRED.each do |key|
        next unless @data[key].nil?

        @errors << Issue.new(key, 'required field is missing')
      end

      unknown = @data.keys - REQUIRED - OPTIONAL
      unknown.each do |key|
        @errors << Issue.new(key, "unknown field; allowed: #{(REQUIRED + OPTIONAL).sort.join(', ')}")
      end

      validate_string('name', /\A[a-z0-9][a-z0-9+._-]*\z/)
      validate_string('maintainer', nil)
      validate_string('description', nil)
      validate_string('sources', nil)
      validate_string('prefix', /\A[a-z0-9][a-z0-9+._\/-]*\z/)
      validate_payload
      validate_executables
      validate_links
      validate_desktop
    end

    def validate_string(key, re)
      value = @data[key]
      return if value.nil? # already reported via REQUIRED

      if !value.is_a?(String) || value.strip.empty?
        @errors << Issue.new(key, 'must be a non-empty string')
        return
      end
      return unless re && !value.match?(re)

      @errors << Issue.new(key, "invalid value #{value.inspect}")
    end

    def validate_payload
      value = @data['payload']
      return if value.nil? # already reported as missing

      unless value.is_a?(Array) && !value.empty?
        @errors << Issue.new('payload', 'must be a non-empty list of artifact files from sources')
        return
      end
      value.each_with_index do |item, i|
        next if item.is_a?(String) && !item.strip.empty? && !item.start_with?('/')

        @errors << Issue.new("payload[#{i}]", 'file name must be a non-empty relative string (no leading "/")')
      end
    end

    def validate_executables
      value = @data['executables']
      return if value.nil?

      unless value.is_a?(Array)
        @errors << Issue.new('executables', 'must be a list of names from payload')
        return
      end
      value.each do |exe|
        next if payload.include?(exe)

        @errors << Issue.new('executables', "#{exe.inspect} is not in payload — only files from payload can be executable")
      end
    end

    def validate_links
      value = @data['links']
      return if value.nil?

      unless value.is_a?(Hash) && !value.empty?
        @errors << Issue.new('links', 'must be a mapping: relative symlink path -> target')
        return
      end
      value.each do |link, target|
        if link.to_s.start_with?('/')
          @errors << Issue.new("links.#{link}", 'symlink path must be relative to prefix (no leading "/")')
        end
        unless target.is_a?(String) && !target.strip.empty?
          @errors << Issue.new("links.#{link}", 'symlink target must be a non-empty string')
        end
      end
    end

    def validate_desktop
      value = @data['desktop']
      return if value.nil?

      unless value.is_a?(Hash) && !value.empty?
        @errors << Issue.new('desktop', 'must be a mapping: name, comment, categories, exec (optional)')
      end
    end
  end
end
