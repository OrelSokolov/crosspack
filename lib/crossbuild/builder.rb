# frozen_string_literal: true

module Crossbuild
  # Runs one or all host-buildable matrix entries: computes the version, runs
  # the steps, distributes the artifacts into the builds/ tree.
  class Builder
    Result = Struct.new(:version, :entries, keyword_init: true)

    attr_reader :manifest

    def initialize(manifest, root: Dir.pwd, output_base: nil, version: nil, deps: true,
                   host_os: Platform.os, host_arch: Platform.arch)
      @manifest = manifest
      @root = root
      @output_base = output_base || manifest.output
      @version_override = version
      @deps = deps
      @host_os = host_os
      @host_arch = host_arch
    end

    # entry_id: nil — every entry buildable on this host; otherwise the exact
    # entry id (which must exist, but may target another host — the user
    # asked for it explicitly).
    # target: a raw target string (e.g. "ubuntu-24.04") — builds the single
    # matrix entry distributing to it and fans artifacts out to that target
    # only; the entry must be buildable on this host (no cross-compilation).
    def run(entry_id: nil, target: nil)
      manifest.validate!
      ensure_deps
      version = @version_override || VersionScheme.new(manifest.version).compute(root: @root)
      entries = target ? entries_for_target(target) : select_entries(entry_id)

      entries.each do |entry|
        puts "\n==> #{manifest.name} [#{entry.id}] version #{version}"
        run_entry(entry, version, only: target)
      end
      Result.new(version: version, entries: entries)
    end

    private

    # deps: false (--no-deps) skips the pre-build check/install pass.
    def ensure_deps
      return if !@deps || manifest.deps.empty?

      puts '⧗ build deps'
      DepInstaller.new(manifest, root: @root).ensure_all
    end

    def entries_for_target(raw)
      entry = manifest.entry_for_target(raw)
      host = "#{@host_os}/#{Platform.display_arch(@host_arch)}"
      unless entry.buildable_on?(@host_os, @host_arch)
        raise Error,
              "the entry for #{raw.inspect} (#{entry.id}) builds on #{entry.platform}, " \
              "this host is #{host} — cross-compilation is not supported"
      end

      [entry]
    end

    def select_entries(entry_id)
      if entry_id
        entry = manifest.find_entry(entry_id)
        raise Error, "unknown matrix entry #{entry_id.inspect}; available: #{manifest.entries.map(&:id).join(', ')}" unless entry

        [entry]
      else
        buildable = manifest.buildable_entries(@host_os, @host_arch)
        raise Error, "nothing to build on #{@host_os}/#{Platform.display_arch(@host_arch)} " \
                     "(matrix entries: #{manifest.entries.map(&:id).join(', ')})" if buildable.empty?

        buildable
      end
    end

    def run_entry(entry, version, only: nil)
      arch = entry.arch == :any ? @host_arch : entry.arch
      vars = {
        name: manifest.name,
        version: version,
        platform: "#{entry.os}/#{Platform.display_arch(arch)}",
        os: entry.os.to_s,
        arch: Platform.display_arch(arch),
        id: entry.id
      }

      Runner.new(root: @root, vars: vars, env: entry.env).run(entry.steps) unless entry.steps.empty?

      dirs = Distributor.new(root: @root, output_base: @output_base)
                       .distribute(entry, host_arch: @host_arch, version: version, only: only)
      return if dirs.empty?

      dirs.each { |d| puts "🌳 #{d.sub("#{@root}/", '')}" }
    end
  end
end
