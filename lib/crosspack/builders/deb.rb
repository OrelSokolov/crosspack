# frozen_string_literal: true

require 'fileutils'
require 'open3'

module Crosspack
  module Builders
    # Stages a package tree and packs it with dpkg-deb. No external Ruby
    # dependencies; mirrors the layout conventions used by the hvoice
    # Rakefile (files under a prefix, launcher symlink in bin).
    class Deb
      def self.build(name:, version:, architecture:, maintainer:, description:,
                     depends:, files:, symlinks: {}, executables: [],
                     section: 'utils', priority: 'optional', output:)
        new(name: name, version: version, architecture: architecture,
            maintainer: maintainer, description: description, depends: depends,
            files: files, symlinks: symlinks, executables: executables,
            section: section, priority: priority, output: output).build
      end

      def initialize(name:, version:, architecture:, maintainer:, description:,
                     depends:, files:, symlinks:, executables:, section:,
                     priority:, output:)
        @name = name
        @version = version
        @architecture = architecture
        @maintainer = maintainer
        @description = description.to_s
        @depends = depends
        @files = files || {}
        @symlinks = symlinks || {}
        @executables = executables || []
        @section = section
        @priority = priority
        @output = output
      end

      def build
        check_tool!
        stage_dir = File.join(File.dirname(@output), ".stage-#{@name}")
        pkg_root = File.join(stage_dir, @name)
        FileUtils.rm_rf(stage_dir)
        FileUtils.mkdir_p(pkg_root)

        stage_files(pkg_root)
        stage_symlinks(pkg_root)
        write_control(File.join(pkg_root, 'DEBIAN'))

        FileUtils.mkdir_p(File.dirname(@output))
        FileUtils.rm_f(@output)
        out, status = Open3.capture2e('dpkg-deb', '--build', '--root-owner-group', pkg_root, @output)
        unless status.success?
          raise BuildError,
                "dpkg-deb failed to build the package #{@output}:\n#{out}\n" \
                'Check the package structure in the staging directory above.'
        end
        FileUtils.rm_rf(stage_dir)
        @output
      end

      private

      def check_tool!
        _, _, status = Open3.capture3('dpkg-deb', '--version')
        return if status.success?

        raise BuildError, 'dpkg-deb not found in PATH. Install it with: sudo apt install dpkg'
      rescue Errno::ENOENT
        raise BuildError, 'dpkg-deb not found in PATH. Install it with: sudo apt install dpkg'
      end

      def stage_files(pkg_root)
        missing = @files.reject { |src, _dst| File.file?(src) }
        unless missing.empty?
          details = missing.map { |src, dst| "  ✗ #{src} (for #{dst})" }.join("\n")
          raise BuildError,
                "Source files for packing not found:\n#{details}\n" \
                'Build the application first (e.g. rake build:ubuntu).'
        end

        @files.each do |src, dst|
          target = File.join(pkg_root, dst)
          FileUtils.mkdir_p(File.dirname(target))
          FileUtils.cp(src, target)
          FileUtils.chmod(executable?(dst) ? 0o755 : 0o644, target)
        end
      end

      def stage_symlinks(pkg_root)
        @symlinks.each do |link, target|
          link_path = File.join(pkg_root, link)
          FileUtils.mkdir_p(File.dirname(link_path))
          FileUtils.ln_sf(target, link_path)
        end
      end

      def executable?(dst)
        @executables.include?(dst)
      end

      def write_control(debian_dir)
        FileUtils.mkdir_p(debian_dir)
        description_lines = @description.lines.map(&:chomp).reject(&:empty?)
        summary = description_lines.shift || @name
        body = description_lines.map { |l| " #{l}" }

        File.write(File.join(debian_dir, 'control'), <<~CONTROL)
          Package: #{@name}
          Version: #{@version}
          Section: #{@section}
          Priority: #{@priority}
          Architecture: #{@architecture}
          Maintainer: #{@maintainer}
          Depends: #{@depends}
          Description: #{summary}
          #{body.join("\n")}
        CONTROL
      end
    end
  end
end
