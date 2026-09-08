# frozen_string_literal: true

require 'yaml'

module Crossbuild
  # A single schema problem: full path into build.yaml + human explanation.
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

  class BuildManifest
    OS_LIST = %w[linux darwin windows].freeze
    ARCH_LIST = %w[amd64 x86_64 arm64 aarch64 any].freeze
    ARTIFACT_MODES = %w[symlink copy].freeze
    VERSION_SCHEMES = %w[calver git-tag].freeze
    TOP_LEVEL_KEYS = %w[name version output matrix].freeze
    ENTRY_KEYS = %w[id build env steps artifacts].freeze
    ARTIFACTS_KEYS = %w[from include to mode].freeze
    BUILD_RE = /\A(linux|darwin|windows)\/(#{ARCH_LIST.join('|')})\z/.freeze
    NAME_RE = /\A[a-z0-9][a-z0-9+._-]*\z/i.freeze

    # One matrix entry: where it builds, what it runs, where artifacts go.
    class Entry
      attr_reader :id, :os, :arch, :env, :steps, :artifacts, :index

      def initialize(id:, os:, arch:, env:, steps:, artifacts:, index:)
        @id = id
        @os = os.to_sym
        @arch = arch
        @env = env
        @steps = steps
        @artifacts = artifacts
        @index = index
      end

      # "linux/amd64" display form (arch spelled wails-style).
      def platform
        "#{@os}/#{Platform.display_arch(@arch == :any ? :x86_64 : @arch)}"
      end

      def buildable_on?(host_os, host_arch)
        @os == host_os && (@arch == :any || @arch == host_arch)
      end
    end

    # Where artifacts come from and which builds/ directories they fan out to.
    class Artifacts
      attr_reader :from, :include, :to, :mode

      def initialize(from:, include:, to:, mode:)
        @from = from
        @include = include
        @to = to
        @mode = mode
      end
    end

    attr_reader :path, :name, :version, :output, :entries, :errors, :warnings

    def self.load(path)
      unless File.file?(path)
        raise InvalidManifestError,
              "Build manifest not found: #{path}\n" \
              'Create build.yaml next to the Rakefile (see crossbuild/README.md).'
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
      @raw = raw
      @name = nil
      @version = nil
      @output = 'builds'
      @entries = []
      @errors = []
      @warnings = []
      validate
    end

    def valid?
      @errors.empty?
    end

    # Raises with the full, formatted list of problems.
    def validate!
      return self if valid?

      lines = ["#{path}: build.yaml schema is invalid (#{@errors.size} errors):"]
      @errors.each { |e| lines << "  ✗ #{e}" }
      lines << 'Build aborted: fix the listed nodes and retry.'
      raise InvalidManifestError, lines.join("\n")
    end

    # Report used by CLI/rake abort: errors (if any) plus warnings.
    def error_report
      lines = []
      if valid?
        noun = @entries.size == 1 ? 'entry' : 'entries'
        lines << "#{path}: schema is valid (#{@entries.size} #{noun}: #{@entries.map(&:id).join(', ')})."
      else
        lines << "#{path}: build.yaml schema is invalid (#{@errors.size} errors):"
        @errors.each { |e| lines << "  ✗ #{e}" }
      end
      @warnings.each { |w| lines << "  ⚠ #{w}" }
      lines.join("\n")
    end

    # Entries that may run on the given host; empty when nothing matches.
    def buildable_entries(host_os, host_arch)
      @entries.select { |e| e.buildable_on?(host_os, host_arch) }
    end

    def find_entry(id)
      @entries.find { |e| e.id == id }
    end

    private

    def validate
      unless @raw.is_a?(Hash) && !@raw.empty?
        @errors << Issue.new('(root)', 'file must be a non-empty mapping with at least a name and a matrix')
        return
      end

      check_unknown_keys('(root)', @raw.keys, TOP_LEVEL_KEYS)
      validate_name
      validate_version
      validate_output
      validate_matrix
    end

    def validate_name
      @name = @raw['name'].to_s
      if @raw['name'].nil? || @name.empty?
        @errors << Issue.new('name', 'is required: the application name, e.g. myapp')
      elsif @name !~ NAME_RE
        @errors << Issue.new('name', "invalid name #{@name.inspect} (letters, digits, \"+\", \"_\", \"-\", \".\")")
      end
    end

    def validate_version
      spec = @raw['version']
      if spec.nil?
        @warnings << Issue.new('version', 'not set — defaulting to calver (YYYY.MM.DD-<secs>)')
        @version = 'calver'
        return
      end
      unless spec.is_a?(String) && !spec.strip.empty?
        @errors << Issue.new('version', "must be a string scheme: #{VERSION_SCHEMES.join(' / ')}, env:VAR or a literal")
        return
      end
      @version = spec.strip
      return unless @version.start_with?('env:') && @version.split(':', 2)[1].to_s.strip.empty?

      @errors << Issue.new('version', 'env: requires a variable name, e.g. env:APP_VERSION')
    end

    def validate_output
      out = @raw['output']
      return if out.nil?

      if out.is_a?(String) && !out.strip.empty?
        @output = out.strip
      else
        @errors << Issue.new('output', "must be a non-empty directory name (default: builds), got #{out.inspect}")
      end
    end

    def validate_matrix
      matrix = @raw['matrix']
      unless matrix.is_a?(Array) && !matrix.empty?
        @errors << Issue.new(
          'matrix',
          "must be a non-empty list of entries; expected:\n" \
          "    matrix:\n" \
          "      - build: linux/amd64\n" \
          "        steps: [wails build -platform linux/amd64]\n" \
          "        artifacts: { from: build/bin, to: [debian-12, ubuntu-24.04] }"
        )
        return
      end

      matrix.each_with_index { |entry, i| validate_entry(entry, i) }
      check_duplicate_ids
      check_duplicate_targets
    end

    def validate_entry(entry, index)
      path = "matrix[#{index}]"
      unless entry.is_a?(Hash)
        @errors << Issue.new(path, 'must be a mapping with build/steps/artifacts keys')
        return
      end
      check_unknown_keys(path, entry.keys, ENTRY_KEYS)

      build = parse_build(entry['build'], path)
      return unless build

      os, arch = build
      steps = validate_steps(entry['steps'], path)
      env = validate_env(entry['env'], path)
      artifacts = validate_artifacts(entry['artifacts'], path, arch)
      id = entry['id'].nil? ? "#{os}/#{Platform.display_arch(arch == :any ? :x86_64 : arch)}" : entry['id'].to_s
      if entry['id'] && id.empty?
        @errors << Issue.new("#{path}.id", 'must be a non-empty string')
        return
      end
      if entry['steps'].nil? && artifacts.nil?
        @errors << Issue.new(path, 'entry has no steps and no artifacts — it would do nothing; add steps or an artifacts section')
        return
      end
      @warnings << Issue.new(path, 'entry has no steps — existing artifacts only will be distributed') if entry['steps'].nil? && artifacts
      @entries << Entry.new(id: id, os: os, arch: arch, env: env, steps: steps,
                            artifacts: artifacts, index: index)
    end

    def parse_build(build, path)
      if build.nil?
        @errors << Issue.new("#{path}.build", 'is required: the platform this entry builds on, e.g. linux/amd64')
        return nil
      end
      unless build.is_a?(String) && (m = build.strip.match(BUILD_RE))
        suggestion = suggest(build.to_s, OS_LIST.map { |os| "#{os}/amd64" })
        hint = suggestion ? " (did you mean #{suggestion.inspect}?)" : ''
        @errors << Issue.new(
          "#{path}.build",
          "invalid build platform #{build.inspect}; expected os/arch#{hint} " \
          "(os: #{OS_LIST.join(', ')}; arch: #{ARCH_LIST.join(', ')})"
        )
        return nil
      end
      os = m[1]
      arch = m[2] == 'any' ? :any : Crosspack::Target.normalize_arch(m[2])
      [os, arch]
    end

    def validate_steps(steps, path)
      return [] if steps.nil?

      unless steps.is_a?(Array) && !steps.empty? && steps.all? { |s| s.is_a?(String) && !s.strip.empty? }
        @errors << Issue.new("#{path}.steps", 'must be a non-empty list of shell command strings')
        return []
      end
      steps
    end

    def validate_env(env, path)
      return {} if env.nil?

      unless env.is_a?(Hash) && env.all? { |k, v| k.is_a?(String) && !k.empty? && v.is_a?(String) }
        @errors << Issue.new("#{path}.env", 'must be a mapping of VAR -> string (quote values that look like numbers)')
        return {}
      end
      env
    end

    def validate_artifacts(artifacts, path, arch)
      return nil if artifacts.nil?

      unless artifacts.is_a?(Hash)
        @errors << Issue.new("#{path}.artifacts", 'must be a mapping with from/include/to/mode keys')
        return nil
      end
      check_unknown_keys("#{path}.artifacts", artifacts.keys, ARTIFACTS_KEYS)

      from = artifacts['from']
      if from.nil? || !from.is_a?(String) || from.strip.empty?
        @errors << Issue.new("#{path}.artifacts.from", 'is required: directory the build produces, e.g. build/bin')
        return nil
      end

      include = artifacts['include']
      if include.nil?
        include = ['*']
      elsif !include.is_a?(Array) || include.empty? || !include.all? { |p| p.is_a?(String) && !p.strip.empty? }
        @errors << Issue.new("#{path}.artifacts.include", 'must be a non-empty list of glob patterns, e.g. [myapp, "*.onnx"]')
        include = []
      end

      to = artifacts['to']
      unless to.is_a?(Array) && !to.empty? && to.all? { |t| t.is_a?(String) && !t.strip.empty? }
        @errors << Issue.new("#{path}.artifacts.to", 'must be a non-empty list of crosspack targets, e.g. [debian-12, ubuntu-24.04]')
        to = []
      end
      to.each { |raw| validate_target(raw, "#{path}.artifacts.to") }

      mode = artifacts['mode'] || 'symlink'
      unless ARTIFACT_MODES.include?(mode)
        @errors << Issue.new("#{path}.artifacts.mode", "unknown mode #{mode.inspect}; allowed: #{ARTIFACT_MODES.join(' / ')}")
      end

      Artifacts.new(from: from.strip, include: include, to: to, mode: mode.to_sym)
    end

    def validate_target(raw, path)
      Crosspack::Target.parse(raw)
    rescue Crosspack::Target::Error => e
      @errors << Issue.new("#{path}: #{raw.inspect}", e.message)
    end

    def check_duplicate_ids
      seen = Hash.new(0)
      @entries.each { |e| seen[e.id] += 1 }
      seen.each do |id, count|
        @errors << Issue.new('matrix', "duplicate entry id #{id.inspect} — give one of them an explicit unique id:") if count > 1
      end
    end

    def check_duplicate_targets
      owner = {}
      @entries.each do |e|
        next unless e.artifacts

        e.artifacts.to.each do |t|
          if owner[t]
            @warnings << Issue.new('matrix', "target #{t.inspect} is distributed by both #{owner[t].inspect} and #{e.id.inspect} — the last entry wins")
          else
            owner[t] = e.id
          end
        end
      end
    end

    def check_unknown_keys(path, keys, allowed)
      keys.map(&:to_s).each do |key|
        next if allowed.include?(key)

        suggestion = suggest(key, allowed)
        hint = suggestion ? " (did you mean #{suggestion.inspect}?)" : ''
        @errors << Issue.new("#{path}.#{key}", "unknown key#{hint}; allowed: #{allowed.join(', ')}")
      end
    end

    def suggest(word, candidates)
      best = candidates.min_by { |c| levenshtein(word.to_s, c) }
      levenshtein(word.to_s, best) <= 2 ? best : nil
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
