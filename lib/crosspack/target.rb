# frozen_string_literal: true

module Crosspack
  # A build target: distro family + optional version + CPU architecture.
  # Parsed from strings like "debian-12", "ubuntu-24.04", "fedora-41", "arch".
  class Target
    FAMILIES = %i[debian ubuntu fedora almalinux rocky opensuse arch macos windows].freeze
    VERSIONLESS_FAMILIES = %i[arch].freeze
    # Version is allowed but not required (macos-15, windows-11.0, or bare).
    OPTIONAL_VERSION_FAMILIES = %i[macos windows].freeze
    FORMAT_BY_FAMILY = {
      debian: :deb, ubuntu: :deb,
      fedora: :rpm, almalinux: :rpm, rocky: :rpm, opensuse: :rpm,
      arch: :pkgbuild, macos: :cask, windows: :winget
    }.freeze

    class Error < StandardError; end

    attr_reader :family, :version, :arch

    # Normalizes common architecture spellings: amd64/x64 -> x86_64,
    # aarch64 -> arm64.
    ARCH_ALIASES = {
      amd64: :x86_64, 'x64': :x86_64, x86_64: :x86_64, x86: nil,
      arm64: :arm64, aarch64: :arm64, armhf: nil
    }.freeze

    def self.normalize_arch(value)
      norm = value.to_s.strip.downcase.sub(/\Ax86-64\z/, 'x86_64').to_sym
      ARCH_ALIASES.fetch(norm, norm)
    end

    def self.parse(str, arch: :x86_64)
      s = str.to_s.strip
      raise Error, 'target string is empty' if s.empty?

      family, version = s.split('-', 2)
      family_sym = family.to_sym
      unless FAMILIES.include?(family_sym)
        raise Error, "unknown distro family #{family.inspect}; allowed: #{FAMILIES.join(', ')}"
      end

      norm_arch = normalize_arch(arch)
      raise Error, "unsupported architecture #{arch.inspect} (supported: x86_64/amd64, arm64/aarch64)" if norm_arch.nil?

      if VERSIONLESS_FAMILIES.include?(family_sym) && version
        raise Error, "family #{family} does not use a version (remove \"-#{version}\")"
      end
      version_required = !VERSIONLESS_FAMILIES.include?(family_sym) &&
                         !OPTIONAL_VERSION_FAMILIES.include?(family_sym)
      if version_required && version.to_s.strip.empty?
        raise Error, "specify a version for family #{family}, e.g. #{family}-12"
      end

      new(family_sym, version, norm_arch)
    end

    def initialize(family, version = nil, arch = :x86_64)
      @family = family.to_sym
      @version = version && version.to_s
      @arch = arch
    end

    def format
      FORMAT_BY_FAMILY.fetch(@family)
    end

    # Per-format architecture spelling: deb uses amd64/arm64, rpm and
    # PKGBUILD use x86_64/aarch64.
    def package_arch(format = self.format)
      return 'amd64' if format == :deb && @arch == :x86_64
      return 'arm64' if format == :deb && @arch == :arm64
      return 'aarch64' if @arch == :arm64

      'x86_64'
    end

    def to_s
      @version ? "#{@family}-#{@version}" : @family.to_s
    end
    alias inspect to_s

    # Output layout for build artifacts: base/<family>[/<version>]/<arch>,
    # e.g. crosspacks/ubuntu/24.04/amd64, crosspacks/windows/11.0/x86_64.
    # Families without a version (arch, or bare macos/windows) skip the segment.
    def output_dir(base, format = self.format)
      parts = [base.to_s, @family.to_s]
      parts << @version if @version
      parts << package_arch(format)
      File.join(*parts)
    end
  end
end
