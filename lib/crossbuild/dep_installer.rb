# frozen_string_literal: true

module Crossbuild
  # Verifies and installs the build dependencies declared in the deps:
  # rules of the build: section of crosspack.yml. Host selectors (distro
  # id, ID_LIKE tokens, os, "*" — see Platform.selectors) are matched
  # against each dependency's hosts: rules; the first hit wins. Every rule
  # carries its own commands:
  # `verify` decides presence (exit 0 = installed; default: PATH lookup of
  # the dependency name), `install` says how to install it on that host.
  class DepInstaller
    class DepError < Error; end

    # Outcome of one dependency: resolved selector + install command, and
    # whether the dependency is present after ensure_all/check_all ran.
    Status = Struct.new(:dep, :selector, :command, :installed, keyword_init: true)

    attr_reader :statuses

    def initialize(manifest, root:, selectors: Platform.selectors, os: Platform.os)
      @manifest = manifest
      @root = root
      @selectors = selectors
      @os = os
      @runner = Runner.new(root: root, vars: {
        name: manifest.name,
        version: manifest.version,
        os: os.to_s,
        arch: Platform.display_arch(Platform.arch),
        platform: Platform.to_s,
        id: Platform.to_s
      })
    end

    # Verify every dependency; install the missing ones via their host rule
    # and re-verify. Raises DepError when something stays missing.
    def ensure_all
      @statuses = @manifest.deps.map { |dep| ensure_dep(dep) }
      @statuses
    end

    # Report-only pass for `crosspack deps <target> --check`: never installs.
    def check_all
      @statuses = @manifest.deps.map do |dep|
        selector, rule = resolve(dep)
        Status.new(dep: dep.name, selector: selector, command: display_command(rule),
                   installed: present?(dep, rule))
      end
    end

    # One line per dependency for the CLI doctor output.
    def report
      return '  (no deps declared)' if @manifest.deps.empty?

      (@statuses || check_all).map do |s|
        state = format('%-8s', s.installed ? 'ok' : 'MISSING')
        state = Crosspack::Colors.public_send(s.installed ? :green : :red, state)
        format('  %-20s %-8s %-8s %s',
               s.dep, state, s.selector, s.command)
      end.join("\n")
    end

    private

    def ensure_dep(dep)
      selector, rule = resolve(dep)
      if present?(dep, rule)
        return Status.new(dep: dep.name, selector: selector,
                          command: display_command(rule), installed: true)
      end

      install(dep, selector, rule)
      unless present?(dep, rule)
        detail = rule['verify'] ? "the verify `#{rule['verify']}` still fails" : "#{dep.name} is still not on PATH"
        raise DepError,
              "#{dep.name}: #{detail} after `#{rule['install']}`. " \
              'Fix the install command or the verify probe.'
      end
      Status.new(dep: dep.name, selector: selector, command: display_command(rule), installed: true)
    end

    def resolve(dep)
      @selectors.each do |selector|
        return [selector, dep.hosts[selector]] if dep.hosts.key?(selector)
      end
      raise DepError,
            "#{dep.name}: no rule for this host (selectors tried: #{@selectors.join(', ')}; " \
            "described: #{dep.hosts.keys.join(', ')}) — add one of those or a \"*\" wildcard to deps.#{dep.name}.hosts"
    end

    def present?(dep, rule)
      verify = rule['verify']
      return on_path?(dep.name) if verify.nil?

      system(@runner.interpolate(verify), chdir: @root, out: File::NULL, err: File::NULL)
    end

    def install(dep, selector, rule)
      command = rule['install']
      if command.nil?
        raise DepError,
              "#{dep.name}: verification failed on #{selector} and the rule has no install command — " \
              "add deps.#{dep.name}.hosts.#{selector}.install"
      end

      command = @runner.interpolate(command)
      puts "▶ #{command}   (#{dep.name} @ #{selector})"
      return if system(command, chdir: @root)

      status = $?.nil? ? 'unknown status' : "exit #{$?.exitstatus || $?.to_i}"
      raise DepError, "#{dep.name}: install command failed (#{status}): #{command}"
    end

    def display_command(rule)
      rule['install'] || "(verify only: #{rule['verify']})"
    end

    # Pure-Ruby PATH probe (portable: no `command -v` / `where` shell dance;
    # `system` skips the shell for metacharacter-free strings, where shell
    # builtins do not resolve). On Windows PATHEXT extensions are honored.
    def on_path?(name)
      exts = @os == :windows ? ENV['PATHEXT'].to_s.split(File::PATH_SEPARATOR) : ['']
      ENV['PATH'].to_s.split(File::PATH_SEPARATOR).any? do |dir|
        base = File.join(dir.strip.empty? ? '.' : dir, name)
        exts.any? { |ext| File.executable?("#{base}#{ext}") }
      end
    end
  end
end
