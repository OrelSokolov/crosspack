# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'tmpdir'

module Crosspack
  module Builders
    # Stages a buildroot and packs it with rpmbuild. The spec is generated
    # with AutoReqProv disabled so dependency names come exclusively from
    # deps.yaml (resolved per target), never from ELF soname scanning.
    class Rpm
      def self.build(name:, version:, release:, summary:, license:, requires:,
                     files:, symlinks: {}, executables: [], description: nil,
                     arch: 'x86_64', output:)
        spec = generate_spec(name: name, version: version, release: release,
                             summary: summary, license: license, requires: requires,
                             description: description, files: files,
                             symlinks: symlinks)
        new(spec: spec, files: files, symlinks: symlinks,
            executables: executables, arch: arch, output: output).build
      end

      # The spec text, separated from #build so tests can check it without
      # having rpmbuild installed.
      def self.generate_spec(name:, version:, release:, summary:, license:,
                             requires:, description: nil, files:, symlinks: {})
        description ||= summary
        requires_line = Array(requires).join(', ')
        entries = spec_entries(files: files, symlinks: symlinks)

        <<~SPEC
          Name: #{name}
          Version: #{version}
          Release: #{release}
          Summary: #{summary}
          License: #{license}
          AutoReqProv: no
          #{requires_line.empty? ? '' : "Requires: #{requires_line}"}
          %description
          #{description}

          %prep

          %build

          %install
          # Files are staged into the buildroot by crosspack.

          %files
          %defattr(-,root,root,-)
          #{entries.join("\n")}
        SPEC
      end

      # %files entries: %dir for every directory so we never claim ownership
      # of shared paths like /usr or /usr/local.
      def self.spec_entries(files:, symlinks:)
        dirs = Set.new
        (files.values + symlinks.keys).each do |dst|
          parts = dst.split(File::SEPARATOR)
          parts.pop
          until parts.empty?
            dirs << parts.join(File::SEPARATOR)
            parts.pop
          end
        end
        # Never claim ownership of directories every system already has.
        skip = ->(d) { d.split(File::SEPARATOR).size == 1 || d == 'usr/local' }
        sorted_dirs = dirs.to_a.sort.reject { |d| skip.call(d) }.map { |d| "%dir /#{d}" }
        file_lines = files.values.map { |dst| "/#{dst}" }
        link_lines = symlinks.keys.map { |dst| "/#{dst}" }
        sorted_dirs + file_lines + link_lines
      end

      def initialize(spec:, files:, symlinks:, executables:, arch:, output:)
        @spec = spec
        @files = files
        @symlinks = symlinks
        @executables = executables
        @arch = arch
        @output = output
      end

      def build
        check_tool!
        missing = @files.reject { |src, _dst| File.file?(src) }
        unless missing.empty?
          details = missing.map { |src, dst| "  ✗ #{src} (for #{dst})" }.join("\n")
          raise BuildError,
                "Source files for packing not found:\n#{details}\n" \
                'Build the application first (e.g. rake build:ubuntu).'
        end

        Dir.mktmpdir('crosspack-rpm') do |topdir|
          buildroot = File.join(topdir, 'buildroot')
          stage(buildroot)

          spec_path = File.join(topdir, "#{File.basename(@output, '.rpm')}.spec")
          File.write(spec_path, @spec)

          %w[BUILD RPMS SOURCES SPECS SRPMS].each { |d| FileUtils.mkdir_p(File.join(topdir, d)) }

          out, status = Open3.capture2e(
            'rpmbuild', '-bb', "--target #{@arch}", "--define _topdir #{topdir}",
            "--buildroot #{buildroot}", spec_path
          )
          unless status.success?
            raise BuildError,
                  "rpmbuild failed to build #{@output}:\n#{out}\n" \
                  'Check the spec and the staging directory above.'
          end

          produced = Dir.glob(File.join(topdir, 'RPMS', '**', '*.rpm')).first
          raise BuildError, "rpmbuild completed but no .rpm found in #{topdir}/RPMS:\n#{out}" unless produced

          FileUtils.mkdir_p(File.dirname(@output))
          FileUtils.cp(produced, @output)
        end
        @output
      end

      private

      def check_tool!
        _, _, status = Open3.capture3('rpmbuild', '--version')
        return if status.success?

        raise BuildError, 'rpmbuild not found in PATH. Install it with: sudo apt install rpm'
      rescue Errno::ENOENT
        raise BuildError, 'rpmbuild not found in PATH. Install it with: sudo apt install rpm'
      end

      def stage(buildroot)
        @files.each do |src, dst|
          target = File.join(buildroot, dst)
          FileUtils.mkdir_p(File.dirname(target))
          FileUtils.cp(src, target)
          FileUtils.chmod(@executables.include?(dst) ? 0o755 : 0o644, target)
        end
        @symlinks.each do |link, target|
          link_path = File.join(buildroot, link)
          FileUtils.mkdir_p(File.dirname(link_path))
          FileUtils.ln_sf(target, link_path)
        end
      end
    end
  end
end
