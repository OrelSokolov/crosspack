# frozen_string_literal: true

module Crosspack
  # Scans a builds tree laid out exactly like the output tree —
  # builds/<family>[/<version>]/<arch>/ — and reports which targets have
  # compiled artifacts ready for packing. A missing directory simply means
  # "nothing to pack for that target".
  module Builds
    ARCH_DIR_RE = /\A(amd64|x86_64|x64|arm64|aarch64)\z/i.freeze

    # Returns [Target] for every target directory found under root.
    def self.available(root)
      return [] unless File.directory?(root)

      Dir.glob(File.join(root, '*')).sort.flat_map do |family_dir|
        family = File.basename(family_dir).to_sym
        next [] unless Target::FAMILIES.include?(family)

        scan_family(family_dir, family)
      end
    end

    # Human-readable listing: "ubuntu/25.10/amd64 — builds/ubuntu/25.10/amd64".
    def self.report(root)
      targets = available(root)
      return "No compiled artifacts: the #{root} tree is empty or missing." if targets.empty?

      lines = ["Available builds in #{root}:"]
      targets.each { |t| lines << "  #{t}  (#{t.output_dir(root, t.format)})" }
      lines.join("\n")
    end

    private

    def self.scan_family(dir, family)
      results = []
      Dir.glob(File.join(dir, '*')).select { |e| File.directory?(e) }.each do |entry|
        base = File.basename(entry)
        if versionless_segment?(family, base)
          # The entry is an arch directory directly under the family
          # (e.g. builds/arch/x86_64, builds/macos/arm64).
          add_target(results, family, nil, base)
        else
          Dir.glob(File.join(entry, '*')).select { |d| File.directory?(d) }.each do |arch_dir|
            add_target(results, family, base, File.basename(arch_dir))
          end
        end
      end
      results
    end

    def self.versionless_segment?(family, base)
      Target::VERSIONLESS_FAMILIES.include?(family) || base.match?(ARCH_DIR_RE)
    end

    def self.add_target(results, family, version, arch_name)
      arch = Target.normalize_arch(arch_name)
      results << Target.new(family, version, arch) unless arch.nil?
    end
  end
end
