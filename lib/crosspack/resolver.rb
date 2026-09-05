# frozen_string_literal: true

module Crosspack
  # Result of resolving one canonical dependency for one target.
  # verdict: :packages — concrete names in `names` (ordered alternatives);
  #          :system / :none / :bundled — nothing to install.
  class Resolution
    attr_reader :canonical, :verdict, :names

    def initialize(canonical, verdict, names = [])
      @canonical = canonical
      @verdict = verdict
      @names = names
    end

    def packages?
      @verdict == :packages
    end

    def to_s
      packages? ? @names.join(' | ') : @verdict.to_s
    end
  end

  class ResolveError < StandardError; end

  # Turns (manifest, target) into concrete package dependencies. No network,
  # no search: everything comes from deps.yaml.
  class Resolver
    def initialize(manifest)
      @manifest = manifest
      @manifest.validate!
    end

    # Returns [Resolution] for every canonical name in the manifest.
    def resolve(target)
      family = target.family.to_s
      @manifest.deps.map do |name, body|
        rules = body['targets']
        rule = rules[family]
        if rule.nil?
          available = rules.keys.map(&:to_s).join(', ')
          raise ResolveError,
                "#{name}: deps.yaml has no rules for family #{family} (target #{target}). " \
                "Add the section #{name}: targets: #{family}: ... — currently described: #{available}"
        end

        value = resolve_rule(name, rule, target, family)
        if value.is_a?(Array)
          Resolution.new(name, :packages, value)
        else
          Resolution.new(name, value.to_sym)
        end
      end
    end

    # Dependencies rendered for a package format:
    #   :deb      -> "pkg-a | pkg-b, pkg-c" (Depends: line)
    #   :rpm      -> ["pkg-a", "pkg-c"]     (first alternative wins)
    #   :pkgbuild -> same as rpm
    def depends(target, format: target.format)
      packages = resolve(target).select(&:packages?)
      case format
      when :deb
        packages.map { |r| r.names.join(' | ') }.join(', ')
      when :rpm, :pkgbuild, :cask, :winget
        packages.map { |r| r.names.first }
      else
        raise ArgumentError, "unknown format #{format.inspect} (allowed: :deb, :rpm, :pkgbuild)"
      end
    end

    private

    def resolve_rule(name, rule, target, family)
      return rule if rule.is_a?(String) # whole-family verdict

      key = target.version || '*'
      return rule[key] if rule.key?(key)

      fallback = rule['*']
      return fallback unless fallback.nil?

      versions = rule.keys.map { |v| v == '*' ? '"*" (any)' : v.inspect }.join(', ')
      raise ResolveError,
            "#{name}: no rules for #{family} #{target.version.inspect} and no \"*\" key. " \
            "Versions described in the file: #{versions}. Add targets.#{family}.\"#{target.version}\" " \
            'or a "*" wildcard rule'
    end
  end
end
