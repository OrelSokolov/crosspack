# frozen_string_literal: true

module Crossbuild
  # Human-readable build matrix: which entries exist, which can run on this
  # host, what they run and where their artifacts land.
  class Matrix
    def initialize(manifest, host_os: Platform.os, host_arch: Platform.arch)
      @manifest = manifest
      @host_os = host_os
      @host_arch = host_arch
    end

    def render
      host = "#{@host_os}/#{Platform.display_arch(@host_arch)}"
      lines = ["build.yaml matrix — host: #{host}"]
      @manifest.entries.each { |e| lines << render_entry(e) }
      buildable = @manifest.buildable_entries(@host_os, @host_arch)
      lines << if buildable.empty?
                 "\nNothing can build on this host. crossbuild build runs only matching entries."
               else
                 "\n#{buildable.size} of #{@manifest.entries.size} entries build here: #{buildable.map(&:id).join(', ')}"
               end
      lines.join("\n")
    end

    private

    def render_entry(entry)
      if entry.buildable_on?(@host_os, @host_arch)
        marker = '✓'
        note = 'buildable here'
      else
        marker = '·'
        note = "needs #{entry.platform}"
      end
      parts = ["  #{marker} #{entry.id.ljust(18)} #{note}"]
      parts << if entry.steps.empty?
                 'no steps (distribute only)'
               else
                 "#{entry.steps.size} step#{'s' unless entry.steps.size == 1}"
               end
      parts << artifact_note(entry) if entry.artifacts
      parts.join('  ')
    end

    def artifact_note(entry)
      from = entry.artifacts.from
      to = entry.artifacts.to.join(', ')
      "#{from} -> #{to}"
    end
  end
end
