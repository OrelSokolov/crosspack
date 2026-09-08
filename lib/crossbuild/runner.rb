# frozen_string_literal: true

module Crossbuild
  # Runs the shell steps of a matrix entry from the project root. Commands may
  # reference build facts via {{version}}, {{name}}, {{platform}}, {{os}},
  # {{arch}} and {{id}} placeholders — expanded by the gem itself so the same
  # build.yaml works under POSIX shells and cmd.exe. The same facts are also
  # exported as CROSSBUILD_* environment variables.
  class Runner
    class BuildError < Error; end

    PLACEHOLDER_RE = /\{\{\s*([a-z_]+)\s*\}\}/i.freeze

    attr_reader :vars

    def initialize(root:, vars: {}, env: {})
      @root = root
      @vars = vars
      @env = env
    end

    def run(steps)
      steps.each { |step| run_step(step) }
    end

    def interpolate(command)
      command.gsub(PLACEHOLDER_RE) do
        key = Regexp.last_match(1).downcase.to_sym
        value = @vars[key]
        raise BuildError, "unknown placeholder {{#{key}}} in step: #{command}" if value.nil?

        value.to_s
      end
    end

    private

    def run_step(step)
      command = interpolate(step)
      puts "▶ #{command}"
      env = process_env
      success = system(env, command, chdir: @root)
      return if success

      status = $?.nil? ? 'unknown status' : "exit #{$?.exitstatus || $?.to_i}"
      raise BuildError, "step failed (#{status}): #{command}"
    end

    def process_env
      crossbuild_env = {
        'CROSSBUILD_NAME' => @vars[:name].to_s,
        'CROSSBUILD_VERSION' => @vars[:version].to_s,
        'CROSSBUILD_PLATFORM' => @vars[:platform].to_s,
        'CROSSBUILD_OS' => @vars[:os].to_s,
        'CROSSBUILD_ARCH' => @vars[:arch].to_s,
        'CROSSBUILD_ID' => @vars[:id].to_s
      }
      # Manifest env wins over CROSSBUILD_* bookkeeping vars, both over inherit.
      ENV.to_h.merge(crossbuild_env).merge(@env)
    end
  end
end
