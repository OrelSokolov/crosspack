# frozen_string_literal: true

require 'set'

module Crosspack
  # Renders the dependency x target matrix straight from the manifest.
  # Columns come from the targets declared in deps.yaml itself.
  class Matrix
    def initialize(manifest)
      @manifest = manifest
    end

    def render
      columns = target_columns
      return 'deps.yaml is empty — nothing to show.' if columns.empty?

      header = ['dependency'] + columns.map(&:to_s)
      rows = @manifest.deps.map do |name, body|
        [name] + columns.map { |t| cell(body['targets'], t) }
      end

      widths = header.each_index.map do |i|
        ([header[i].length] + rows.map { |r| r[i].to_s.length }).max
      end
      lines = ([header] + rows).map do |row|
        row.each_with_index.map { |c, i| c.to_s.ljust(widths[i]) }.join('  ')
      end
      lines.join("\n")
    end

    private

    # Every target mentioned in the manifest: family + version pairs,
    # ordered by the canonical family list.
    def target_columns
      cols = []
      Target::FAMILIES.each do |family|
        versions = Set.new
        @manifest.deps.each_value do |body|
          rule = body['targets'][family.to_s]
          next if rule.nil?

          if rule.is_a?(String)
            versions.add(nil)
          else
            rule.each_key { |v| versions.add(v == '*' ? nil : v) }
          end
        end
        versions.to_a.sort_by(&:to_s).each do |v|
          cols << Target.new(family, v)
        end
      end
      cols
    end

    def cell(targets, target)
      rule = targets[target.family.to_s]
      return '—' if rule.nil?

      value = rule.is_a?(String) ? rule : (rule[target.version] || rule['*'])
      return '(no rule)' if value.nil?
      return value unless value.is_a?(Array)

      value.join(' | ')
    end
  end
end
