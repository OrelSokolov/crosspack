# frozen_string_literal: true

module Crossbuild
  # Host platform detection, normalized to the os/arch vocabulary build.yaml
  # uses: linux/amd64, darwin/arm64, windows/amd64.
  module Platform
    OS_BY_RUBY = {
      linux: /linux/,
      darwin: /darwin/,
      windows: /mingw|mswin|cygwin/i
    }.freeze

    class Error < StandardError; end

    def self.os
      OS_BY_RUBY.each { |os, re| return os if RUBY_PLATFORM =~ re }
      raise Error, "unknown host OS from RUBY_PLATFORM=#{RUBY_PLATFORM.inspect}"
    end

    # :x86_64 or :arm64 — the same symbols Crosspack::Target uses.
    def self.arch
      cpu = RbConfig::CONFIG['host_cpu'].to_s
      return :arm64 if cpu.match?(/arm64|aarch64/i)
      return :x86_64 if cpu.match?(/x86_64|amd64|x64/i)

      raise Error, "unknown host CPU from host_cpu=#{cpu.inspect}"
    end

    # "linux/amd64" — the display form used in matrix listings; arch is
    # spelled deb-style (amd64/arm64) to match wails -platform strings.
    def self.to_s
      "#{os}/#{display_arch(arch)}"
    end

    # x86_64 -> "amd64", arm64 -> "arm64" (wails/darwin spelling).
    def self.display_arch(arch)
      arch == :x86_64 ? 'amd64' : arch.to_s
    end
  end
end
