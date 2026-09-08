# frozen_string_literal: true

module Crossbuild
  # Computes the build version from the `version:` field of build.yaml.
  # Supported specs:
  #   calver    — YYYY.MM.DD-<seconds since local midnight>, e.g. 2026.08.31-33837
  #   git-tag   — latest `git describe --tags --abbrev=0`, fallback 0.0.0-dev
  #   env:VAR   — take VAR from the environment (error when unset)
  #   <other>   — any other non-empty string is used verbatim as a literal
  # nil/absent defaults to calver.
  class VersionScheme
    class Error < StandardError; end

    CALVER = 'calver'.freeze
    GIT_TAG = 'git-tag'.freeze
    ENV_PREFIX = 'env:'.freeze

    def initialize(spec)
      @spec = spec.nil? || spec.to_s.strip.empty? ? CALVER : spec.to_s.strip
    end

    def compute(root: Dir.pwd, now: Time.now)
      case @spec
      when CALVER
        format('%s-%d', now.strftime('%Y.%m.%d'), now.hour * 3600 + now.min * 60 + now.sec)
      when GIT_TAG
        git_tag(root)
      when /\A#{ENV_PREFIX}(\S+)\z/
        env_version(Regexp.last_match(1))
      else
        @spec
      end
    end

    private

    def git_tag(root)
      tag = Dir.chdir(root) { `git describe --tags --abbrev=0 2>/dev/null`.strip }
      tag.empty? ? '0.0.0-dev' : tag
    rescue Errno::ENOENT
      '0.0.0-dev'
    end

    def env_version(var)
      value = ENV[var].to_s.strip
      raise Error, "version env var #{var} is not set (version: env:#{var} in build.yaml)" if value.empty?

      value
    end
  end
end
