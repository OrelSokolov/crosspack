# frozen_string_literal: true

require_relative 'test_helper'

class RunnerTest < Minitest::Test
  def test_runs_steps_in_root_and_expands_placeholders
    Dir.mktmpdir('crossbuild-run') do |dir|
      vars = { name: 'app', version: '1.2.3', platform: 'linux/amd64', os: 'linux', arch: 'amd64', id: 'linux/amd64' }
      runner = Crossbuild::Runner.new(root: dir, vars: vars)
      out = capturing_stdout do
        runner.run(['mkdir -p out', 'echo {{name}}-{{version}} > out/stamp.txt'])
      end
      assert_includes out, 'mkdir -p out'
      assert_equal "app-1.2.3\n", File.read(File.join(dir, 'out', 'stamp.txt'))
    end
  end

  def test_exports_crossbuild_env
    Dir.mktmpdir('crossbuild-run') do |dir|
      vars = { name: 'app', version: '9.9.9', platform: 'linux/amd64', os: 'linux', arch: 'amd64', id: 'linux/amd64' }
      Crossbuild::Runner.new(root: dir, vars: vars).run(['echo $CROSSBUILD_VERSION > v.txt'])
      assert_equal "9.9.9\n", File.read(File.join(dir, 'v.txt'))
    end
  end

  def test_manifest_env_reaches_steps
    Dir.mktmpdir('crossbuild-run') do |dir|
      vars = { name: 'app', version: '1', platform: 'linux/amd64', os: 'linux', arch: 'amd64', id: 'x' }
      runner = Crossbuild::Runner.new(root: dir, vars: vars, env: { 'FLAVOR' => 'spicy' })
      runner.run(['echo $FLAVOR > f.txt'])
      assert_equal "spicy\n", File.read(File.join(dir, 'f.txt'))
    end
  end

  def test_failed_step_raises_with_command
    runner = Crossbuild::Runner.new(root: Dir.pwd, vars: {})
    error = assert_raises(Crossbuild::Runner::BuildError) do
      capturing_stdout { runner.run(['exit 3']) }
    end
    assert_includes error.message, 'exit 3'
    assert_includes error.message, 'step failed'
  end

  def test_unknown_placeholder_raises
    runner = Crossbuild::Runner.new(root: Dir.pwd, vars: { version: '1' })
    error = assert_raises(Crossbuild::Runner::BuildError) { runner.interpolate('echo {{nope}}') }
    assert_includes error.message, '{{nope}}'
  end

  private

  def capturing_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end
end
