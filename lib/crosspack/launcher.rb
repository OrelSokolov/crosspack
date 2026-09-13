# frozen_string_literal: true

module Crosspack
  # Host-only launch commands: `crosspack run` (build the host target, then
  # launch the application's main binary) and `crosspack install` (launch the
  # package packed for this host). Both resolve the current host target, so
  # they take no target argument and are meaningless on any other system.
  #
  # Commands may be overridden per host in crosspack.yml (run:/install:
  # sections, selectors like the deps: rules of build:); placeholders:
  # {{path}} plus the usual facts ({{name}}, {{version}}, {{os}}, {{arch}}).
  # Defaults when nothing is configured:
  #   run:     darwin + .app bundle -> `open {{path}}`, otherwise {{path}}
  #   install: deb/rpm -> xdg-open, msi -> msiexec /i, dmg/.app -> open
  class Launcher
    class Error < BuildError; end

    # Builds the host target first (the same stage `crosspack build` runs),
    # then launches the first package.executables binary from builds/.
    # Returns the launched process's exit code.
    def self.run(config, root: Dir.pwd, args: [], output_base: nil, version: nil,
                 deps: true, host_string: nil, host_os: Crossbuild::Platform.os,
                 host_arch: Crossbuild::Platform.arch, selectors: Crossbuild::Platform.selectors)
      config = Config.coerce(config, root: root)
      target = host_target('run', host_string, host_arch)
      pkg = validated_package(config)
      build_manifest = config.build_manifest
      build_manifest.validate!

      Crossbuild::Builder.new(build_manifest, root: root, output_base: output_base,
                                            version: version, deps: deps,
                                            host_os: host_os, host_arch: host_arch)
                         .run(target: target.to_s)

      exe = pkg.executables_for(target).first
      if exe.nil?
        raise Error,
              'run: the package: section does not name the binary to launch — ' \
              "add executables: [#{pkg.name}] to it (the first entry is what `crosspack run` launches)"
      end

      path = File.join(File.expand_path(target.output_dir(pkg.sources, target.format), root), exe)
      unless File.exist?(path)
        raise Error,
              "run: expected the built binary at #{path}, but it is not there — " \
              'does the build step really produce it? Check package.executables against the build output'
      end

      command = config.run_manifest.command_for(selectors) || default_run_command(path, host_os)
      execute(command, path: path, pkg: pkg, target: target, root: root, args: args)
    end

    # Finds the package packed for this host in crosspacks/ and launches it
    # with the system installer. Returns the launched process's exit code.
    def self.install(config, root: Dir.pwd, args: [], output_base: 'crosspacks',
                     host_string: nil, host_os: Crossbuild::Platform.os,
                     host_arch: Crossbuild::Platform.arch, selectors: Crossbuild::Platform.selectors)
      config = Config.coerce(config, root: root)
      target = host_target('install', host_string, host_arch)
      pkg = validated_package(config)

      command = config.install_manifest.command_for(selectors)
      raise Error, pkgbuild_hint(target, root, output_base) if command.nil? && target.format == :pkgbuild

      # {{path}} resolves to the package file (for arch: the PKGBUILD dir).
      path = target.format == :pkgbuild ? packed_dir(target, root, output_base)
                                        : package_file(target, pkg, root, output_base)
      command ||= default_install_command(target.format)

      execute(command, path: path, pkg: pkg, target: target, root: root, args: args)
    end

    # -- defaults ------------------------------------------------------------

    # A macOS .app bundle must be opened, not exec'd; plain binaries and
    # Windows exes run directly.
    def self.default_run_command(path, host_os)
      host_os == :darwin && File.directory?(path) ? 'open {{path}}' : '{{path}}'
    end

    def self.default_install_command(format)
      case format
      when :deb, :rpm   then 'xdg-open {{path}}'
      when :winget      then 'msiexec /i {{path}}'
      when :cask        then 'open {{path}}'
      else
        raise Error, "install: no default installer command for format #{format.inspect} — " \
                     'add an install: section with hosts: rules to crosspack.yml'
      end
    end

    # -- internals -----------------------------------------------------------

    class << self
      private

      # "this host's target" — the same detection the stage commands use.
      def host_target(command, host_string, host_arch)
        raw = host_string || Target.host_string
        if raw.nil?
          raise Error,
                "Could not detect this host's target — crosspack #{command} runs only on this host " \
                '(families: ubuntu-24.04, debian-12, fedora-41, arch, macos, windows-11.0)'
        end

        Target.parse(raw, arch: host_arch)
      end

      def validated_package(config)
        pkg = config.package_manifest
        pkg.validate!
        pkg
      end

      def packed_dir(target, root, output_base)
        File.expand_path(target.output_dir(output_base, target.format), root)
      end

      # The packed tree must exist before any installer runs — even with a
      # custom command (its {{path}} resolves into this directory).
      def check_packed_dir(target, root, output_base)
        dir = packed_dir(target, root, output_base)
        return if File.directory?(dir)

        raise Error,
              "Pack stage not done for target #{target}: expected a packed package in #{dir}.\n" \
              "Run: crosspack pack #{target}"
      end

      # The single package file this host's installer should receive.
      def package_file(target, pkg, root, output_base)
        check_packed_dir(target, root, output_base)
        dir = packed_dir(target, root, output_base)
        file =
          case target.format
          when :deb    then newest(dir, '*.deb')
          when :rpm    then newest(dir, '*.rpm')
          when :winget then newest(dir, '*.msi')
          when :cask   then newest(dir, '*.dmg') || app_bundle(dir, pkg.name)
          end

        if file.nil?
          raise winget_sources_hint(dir) if target.format == :winget && Dir[File.join(dir, '*.wxs')].any?

          raise Error,
                "No package for target #{target} in #{dir} — the pack stage produced nothing this " \
                "command recognizes.\nRun: crosspack pack #{target}"
        end
        file
      end

      def newest(dir, pattern)
        Dir[File.join(dir, pattern)].max_by { |f| File.mtime(f) }
      end

      def app_bundle(dir, name)
        app = File.join(dir, "#{name}.app")
        File.directory?(app) ? app : nil
      end

      def winget_sources_hint(dir)
        'install: the pack stage produced only WiX sources (.wxs) — build the MSI first, ' \
          "see #{File.join(dir, 'BUILD-MSI.txt')}"
      end

      def pkgbuild_hint(target, root, output_base)
        "install: packing for #{target} generates a PKGBUILD, not a built package — " \
          "install it yourself:\n  cd #{packed_dir(target, root, output_base)} && makepkg -si\n" \
          'or add an install: section with hosts: rules to crosspack.yml'
      end

      # Expands the {{...}} placeholders, appends extra CLI args and runs the
      # command from the project root, passing the child's exit code through.
      def execute(command, path:, pkg:, target:, root:, args:)
        vars = {
          name: pkg.name,
          version: Builds.version_for(target, File.expand_path(pkg.sources, root)).to_s,
          os: target.family.to_s,
          arch: Crossbuild::Platform.display_arch(target.arch == :any ? :x86_64 : target.arch),
          platform: target.to_s,
          path: path
        }
        command = Crossbuild::Runner.new(root: root, vars: vars).interpolate(command)
        command = "#{command} #{args.join(' ')}" unless args.empty?

        puts "▶ #{command}"
        result = system(command, chdir: root)
        raise Error, "launch failed (command not found): #{command}" if result.nil?

        $?.exitstatus || 0
      end
    end
  end
end
