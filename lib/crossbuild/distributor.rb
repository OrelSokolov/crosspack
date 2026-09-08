# frozen_string_literal: true

require 'fileutils'

module Crossbuild
  # Fans the artifacts a matrix entry produced out into the per-target builds
  # tree — builds/<family>[/<version>]/<arch>/ — laid out exactly like the
  # crosspacks/ tree crosspack writes, so crosspack can pack straight from it.
  # Items are symlinked by default (packers copy through symlinks); copy mode
  # is available for trees that get archived or shipped as-is.
  class Distributor
    attr_reader :placed_dirs

    def initialize(root:, output_base:)
      @root = root
      @output_base = output_base
      @placed_dirs = []
    end

    # Returns the list of builds/ directories that received artifacts.
    def distribute(entry, host_arch:)
      spec = entry.artifacts
      return [] unless spec

      from_dir = File.expand_path(spec.from, @root)
      unless File.directory?(from_dir)
        raise Error, "artifacts.from directory not found: #{spec.from} (#{from_dir}) — did the steps run?"
      end

      items = select_items(from_dir, spec.include)
      arch = entry.arch == :any ? host_arch : entry.arch

      spec.to.each do |raw|
        target = Crosspack::Target.parse(raw, arch: arch)
        dst_dir = target.output_dir(File.expand_path(@output_base, @root))
        FileUtils.mkdir_p(dst_dir)
        items.each { |item| place(item, File.join(dst_dir, File.basename(item)), spec.mode) }
        @placed_dirs << dst_dir
      end
      @placed_dirs.uniq
    end

    private

    # Resolve include globs inside from_dir; a missing selection is an error,
    # not a silently empty build.
    def select_items(from_dir, patterns)
      items = []
      patterns.each do |pattern|
        matches = Dir.glob(File.join(from_dir, pattern.to_s))
                     .reject { |p| p.end_with?('.') || p.end_with?('..') }
                     .select { |p| File.exist?(p) }
        if matches.empty?
          raise Error, "artifacts pattern #{pattern.inspect} matched nothing inside #{spec_from_display(from_dir)}"
        end

        items.concat(matches)
      end
      items.uniq.sort
    end

    def spec_from_display(from_dir)
      from_dir.sub("#{@root}/", '')
    end

    def place(src, dst, mode)
      if mode == :copy
        FileUtils.rm_rf(dst)
        FileUtils.cp_r(src, dst)
      else
        FileUtils.rm_f(dst)
        FileUtils.ln_sf(src, dst) # absolute target, like hvoice's link_builds_tree
      end
    end
  end
end
