# frozen_string_literal: true

module Crosspack
  # Packaging manifest (the package: section of crosspack.yml): declares
  # WHAT and HOW to pack — payload, executables, symlinks, desktop entry,
  # icon. Compilation is not crosspack's business; artifacts are picked from
  # `sources` as-is.
  #
  # Payload entries may carry per-target file names: the key is the common
  # name (used verbatim everywhere unless a selector map says otherwise),
  # and each selector (exact target "windows-11.0", family "windows" or "*")
  # maps to the real file name that target's build produces. An entry with a
  # selector map applies only to targets it covers — a Windows build dir has
  # no .so libraries and vice versa.
  class PackageManifest
    REQUIRED = %w[maintainer description sources prefix payload].freeze
    OPTIONAL = %w[name summary license section lib_dir executables links desktop icon].freeze

    # Payload selectors may name an os in addition to a family: every distro
    # family packs a linux target, so "linux:" covers deb/rpm/PKGBUILD
    # without enumerating them (macos and windows are their own families).
    OS_BY_FAMILY = Hash.new('linux').merge(macos: 'macos', windows: 'windows').freeze

    # One payload file: its common key plus the per-target name overrides.
    PayloadFile = Struct.new(:key, :names, keyword_init: true)

    attr_reader :path, :data, :errors, :warnings

    def initialize(path, raw)
      @path = path
      @data = raw.is_a?(Hash) ? raw : {}
      @raw = raw
      @errors = []
      @warnings = []
      @payload_entries = []
      validate
    end

    def valid?
      @errors.empty?
    end

    def validate!
      return self if valid?

      lines = ["#{path}: the package: section is invalid (#{@errors.size} errors):"]
      @errors.each { |e| lines << "  ✗ #{e}" }
      lines << 'Packing aborted: fix the listed nodes and retry.'
      raise InvalidManifestError, lines.join("\n")
    end

    def error_report
      if valid?
        "#{path}: the package: section is valid."
      else
        ["#{path}: the package: section is invalid (#{@errors.size} errors):",
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

    # Common keys of the payload entries (the executables list and links
    # reference these); use payload_for(target) for the real file names.
    def payload
      @payload_entries.map(&:key)
    end

    # Real file names the given target's package carries. Every entry
    # resolves through its selector map — exact target string, then family,
    # then "*"; entries without a map use their key on every target; entries
    # whose selectors do not cover the target are skipped.
    def payload_for(target)
      @payload_entries.filter_map { |entry| resolve_entry(entry, target) }
    end

    def executables
      Array(@data['executables'])
    end

    # Executable file names for the target. The executables list names
    # common payload keys; they resolve to the target's real file names.
    def executables_for(target)
      executables.map do |key|
        entry = @payload_entries.find { |e| e.key == key }
        resolved = entry && resolve_entry(entry, target)
        if resolved.nil?
          raise InvalidManifestError,
                "executables: #{key.inspect} resolves to no file for target #{target} — " \
                'its payload entry has no name for that target'
        end

        resolved
      end
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
        @errors << Issue.new('(root)',
                             'the package: section of crosspack.yml is missing or empty — ' \
                             'the pack stage needs it (maintainer, description, payload, ...)')
        return
      end

      if @data['name'].nil?
        @errors << Issue.new('name', 'is required at the top level of crosspack.yml, e.g. name: myapp')
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

      @payload_entries =
        if value.is_a?(Array)
          validate_payload_list(value)
        elsif value.is_a?(Hash)
          validate_payload_map(value)
        else
          @errors << Issue.new('payload', 'must be a non-empty list of artifact files or a mapping: key -> {target -> real file name}')
          []
        end
      return unless @payload_entries.empty?

      @errors << Issue.new('payload', 'must name at least one artifact file from sources')
    end

    # Legacy/simple form: a flat list — every name applies to every target.
    def validate_payload_list(value)
      value.each_with_index.with_object([]) do |(item, i), entries|
        if item.is_a?(String) && !item.strip.empty? && !item.start_with?('/')
          entries << PayloadFile.new(key: item, names: {})
        else
          @errors << Issue.new("payload[#{i}]", 'file name must be a non-empty relative string (no leading "/")')
        end
      end
    end

    # Mapping form: common key -> null (key everywhere) or a selector map
    # (exact target / family / "*") of real file names per target.
    def validate_payload_map(value)
      value.each_with_object([]) do |(key, names), entries|
        if !key.is_a?(String) || key.strip.empty? || key.start_with?('/')
          @errors << Issue.new("payload.#{key.inspect}", 'must be a non-empty relative file name (no leading "/")')
          next
        end
        if names.nil? || names == {}
          entries << PayloadFile.new(key: key, names: {})
          next
        end
        unless names.is_a?(Hash)
          @errors << Issue.new("payload.#{key}", 'must be null or a mapping of target selector -> real file name')
          next
        end

        resolved = {}
        entry_valid = true
        names.each do |selector, name|
          unless valid_selector?(selector)
            @errors << Issue.new("payload.#{key}.#{selector}",
                                 "unknown target selector (allowed: \"*\", an os (linux) or a family " \
                                 "(#{Target::FAMILIES.join(', ')}), optionally with a version, e.g. windows-11.0)")
            entry_valid = false
            next
          end
          if !name.is_a?(String) || name.strip.empty? || name.start_with?('/')
            @errors << Issue.new("payload.#{key}.#{selector}", 'file name must be a non-empty relative string (no leading "/")')
            entry_valid = false
            next
          end
          resolved[selector] = name
        end
        entries << PayloadFile.new(key: key, names: resolved) if entry_valid
      end
    end

    def valid_selector?(selector)
      return true if selector == '*'
      return true if selector == 'linux' # the one os selector (macos/windows are families)

      Target.parse(selector.to_s)
      true
    rescue Target::Error
      false
    end

    # Exact target string ("windows-11.0") wins over the family ("windows"),
    # then the os ("linux"), then "*"; an entry without a map carries its
    # key on every target.
    def resolve_entry(entry, target)
      return entry.key if entry.names.empty?

      entry.names[target.to_s] ||
        entry.names[target.family.to_s] ||
        entry.names[OS_BY_FAMILY[target.family]] ||
        entry.names['*']
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
