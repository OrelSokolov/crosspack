# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'

module Crosspack
  # Single entry point: takes a Config (the package: and deps: sections of
  # crosspack.yml), resolves dependencies for the target and produces a
  # native package under output_base/<family>/<version>/<arch>/. The builder
  # is chosen by the target format — deb, rpm or PKGBUILD.
  # version: when omitted, the version stamped by `crosspack build <target>`
  # (.crosspack-build in the target's builds/ directory) is used.
  class Packer
    def self.pack(config:, target:, version: nil, root: Dir.pwd,
                  output_base: 'crosspacks')
      new(config: config, target: target, version: version,
          root: root, output_base: output_base).pack
    end

    def initialize(config:, target:, version:, root:, output_base:)
      @config = config
      @target = target
      @version = version && version.to_s
      @root = root
      @output_base = output_base || 'crosspacks'
    end

    def pack
      @config = Config.coerce(@config, root: @root)
      @pkg = @config.package_manifest
      @deps = @config.deps_manifest
      validate_both!
      resolve_version!
      @pkg_data = build_layout

      case @target.format
      when :deb
        pack_deb
      when :rpm
        pack_rpm
      when :pkgbuild
        pack_pkgbuild
      when :winget
        pack_windows
      when :cask
        pack_macos
      else
        raise BuildError,
              "packing is not defined for target #{@target} (format #{@target.format})"
      end
    end

    private

    # --version wins; otherwise the version recorded by the build stage.
    def resolve_version!
      return unless @version.nil? || @version.strip.empty?

      stamped = Builds.version_for(@target, File.expand_path(@pkg.sources, @root))
      if stamped.nil? || stamped.strip.empty?
        raise BuildError,
              "No version for target #{@target}: no --version given and no build stamp " \
              "(#{Builds::STAMP_NAME}) in #{@pkg.sources}. " \
              "Run: crosspack build #{@target} — or pass --version explicitly."
      end

      @version = stamped
    end

    def validate_both!
      errors = []
      errors << @config.error_report unless @config.valid?
      errors << @pkg.error_report unless @pkg.valid?
      errors << @deps.error_report unless @deps.valid?
      return if errors.empty?

      raise InvalidManifestError, errors.join("\n")
    end

    # Layout shared by every format. The artifacts tree mirrors the output
    # tree exactly — builds/<family>[/<version>]/<arch>/ — so the source
    # directory for a target is computed the same way as its output dir.
    # A Linux binary can never sneak into a Windows package: if the target's
    # build directory is absent, packing fails.
    def build_layout
      src_dir = File.expand_path(@target.output_dir(@pkg.sources, @target.format), @root)
      unless File.directory?(src_dir)
        available = Builds.available(File.expand_path(@pkg.sources, @root))
        hint = available.empty? ? 'no built targets at all.' :
               "available builds: #{available.map { |t| "#{t} (#{t.output_dir(@pkg.sources, t.format)})" }.join(', ')}."
        raise BuildError,
              "Build stage not done for target #{@target}: expected compiled artifacts in #{src_dir}.\n" \
              "The builds tree (#{@pkg.sources}) mirrors the output tree: builds/<family>/<version>/<arch>/. " \
              "Currently #{hint}\n" \
              "Run: crosspack build #{@target}"
      end

      lib_dst = File.join(@pkg.prefix, @pkg.lib_dir)
      files = @pkg.payload_for(@target).to_h { |n| [File.join(src_dir, n), File.join(lib_dst, n)] }

      if @pkg.icon
        files[icon_source] = icon_destination
      end

      if @pkg.desktop
        files[desktop_entry_path] = File.join(@pkg.prefix, 'share', 'applications', "#{@pkg.name}.desktop")
      end

      symlinks = @pkg.links.to_h { |link, target| [File.join(@pkg.prefix, link), target] }
      executables = @pkg.executables_for(@target).map { |exe| File.join(lib_dst, exe) }

      { files: files, symlinks: symlinks, executables: executables,
        src_dir: src_dir, lib_dst: lib_dst }
    end

    # Writes the .desktop file next to other staging artifacts and returns
    # its path (rooted under build/ so repeated runs reuse one location).
    def desktop_entry_path
      dir = File.join(@root, 'build', 'pkg')
      FileUtils.mkdir_p(dir)
      path = File.join(dir, "#{@pkg.name}.desktop")
      d = @pkg.desktop
      # The spec requires each list value terminated with ";"; a manifest
      # value like "Utility;Audio" would otherwise produce an invalid entry.
      categories = d['categories'].to_s.empty? ? 'Utility;' : d['categories'].to_s
      categories += ';' unless categories.end_with?(';')
      File.write(path, <<~DESKTOP)
        [Desktop Entry]
        Type=Application
        Name=#{d['name'] || @pkg.name}
        Comment=#{d['comment'] || @pkg.summary}
        Exec=#{d['exec'] || @pkg.name}
        Icon=#{@pkg.name}
        Terminal=false
        Categories=#{categories}
      DESKTOP
      path
    end

    def icon_source
      src = File.expand_path(@pkg.icon, @root)
      raise BuildError, "icon: file not found #{src}" unless File.file?(src)

      src
    end

    # Desktop icon lookup keeps the real extension: PNG/XPM go to the
    # classic pixmaps dir, SVG needs the hicolor scalable theme dir (a .svg
    # named .png in pixmaps is never found).
    def icon_destination
      ext = File.extname(@pkg.icon).downcase
      if ext == '.svg'
        File.join(@pkg.prefix, 'share', 'icons', 'hicolor', 'scalable', 'apps', "#{@pkg.name}#{ext}")
      else
        File.join(@pkg.prefix, 'share', 'pixmaps', "#{@pkg.name}#{ext}")
      end
    end

    def resolved_depends(format)
      Resolver.new(@deps).depends(@target, format: format)
    end

    def pack_deb
      output = File.join(@target.output_dir(@output_base, :deb),
                         "#{@pkg.name}_#{@version}_#{@target.package_arch(:deb)}.deb")
      Builders::Deb.build(
        name: @pkg.name,
        version: @version,
        architecture: @target.package_arch(:deb),
        maintainer: @pkg.maintainer,
        description: @pkg.description,
        depends: resolved_depends(:deb),
        files: @pkg_data[:files],
        symlinks: @pkg_data[:symlinks],
        executables: @pkg_data[:executables],
        section: @pkg.section,
        output: output
      )
      output
    end

    def pack_rpm
      version, release = split_version
      output = File.join(@target.output_dir(@output_base, :rpm),
                         "#{@pkg.name}-#{version}-#{release}.#{@target.package_arch(:rpm)}.rpm")
      Builders::Rpm.build(
        name: @pkg.name,
        version: version,
        release: release,
        summary: @pkg.summary,
        license: @pkg.license,
        requires: resolved_depends(:rpm),
        files: @pkg_data[:files],
        symlinks: @pkg_data[:symlinks],
        executables: @pkg_data[:executables],
        description: @pkg.description,
        arch: @target.package_arch(:rpm),
        output: output
      )
      output
    end

    def pack_pkgbuild
      version, release = split_version
      output = File.join(@target.output_dir(@output_base, :pkgbuild), 'PKGBUILD')
      # Same desktop integration as deb/rpm: the .desktop file and the icon
      # go to the same destinations; their sources are archive-relative
      # names (the icon under its own file name).
      files = @pkg.payload_for(@target).to_h { |n| [n, File.join(@pkg_data[:lib_dst], n)] }
      if @pkg.desktop
        files["#{@pkg.name}.desktop"] = File.join(@pkg.prefix, 'share', 'applications',
                                                  "#{@pkg.name}.desktop")
      end
      files[File.basename(@pkg.icon)] = icon_destination if @pkg.icon
      Builders::Pkgbuild.generate(
        name: @pkg.name,
        version: version,
        release: release,
        pkgdesc: @pkg.summary,
        maintainer: @pkg.maintainer,
        depends: resolved_depends(:pkgbuild),
        arch: [@target.package_arch(:pkgbuild)],
        # PKGBUILD sources are archive-relative names, not local paths.
        files: files,
        symlinks: @pkg_data[:symlinks],
        executables: @pkg_data[:executables],
        source: ["#{@pkg.name}-#{version}.tar.gz"],
        license: @pkg.license,
        output: output
      )
      output
    end

    def split_version
      parts = @version.split('-', 2)
      parts << '1' if parts.size == 1
      parts
    end

    # Windows: flat payload under Program Files/<name>/ via WiX. Unix symlinks
    # do not apply; everything from `sources` goes in as regular files.
    # desktop:/executables: drive the Start Menu / Desktop shortcuts.
    def pack_windows
      output = File.join(@target.output_dir(@output_base, :winget),
                         "#{@pkg.name}-#{Builders::Wix.msi_version(@version)}.msi")
      files = @pkg.payload_for(@target).to_h { |n| [File.join(@pkg_data[:src_dir], n), n] }
      Builders::Wix.build(
        name: @pkg.name,
        version: @version,
        manufacturer: @pkg.maintainer,
        summary: @pkg.summary,
        license: @pkg.license,
        files: files,
        shortcuts: windows_shortcuts,
        arch: @target.package_arch(:winget),
        output: output
      )
    end

    # Shortcut facts for the MSI: the display name from desktop: (falling
    # back to the package name) and the first executable as the target.
    def windows_shortcuts
      target = @pkg.executables_for(@target).first
      return nil if target.nil?

      { name: (@pkg.desktop && @pkg.desktop['name']) || @pkg.name,
        target: target }
    end

    # macOS: .app bundle staging; DMG itself requires a Mac (hdiutil).
    # desktop.name becomes the display name; the manifest icon lands in
    # Contents/Resources (CFBundleIconFile).
    def pack_macos
      output_dir = @target.output_dir(@output_base, :cask)
      files = @pkg.payload_for(@target).to_h { |n| [File.join(@pkg_data[:src_dir], n), n] }
      Builders::AppDir.build(
        name: @pkg.name,
        display_name: (@pkg.desktop && @pkg.desktop['name']) || @pkg.name,
        version: @version,
        summary: @pkg.summary,
        files: files,
        executables: @pkg.executables_for(@target),
        icon: @pkg.icon && File.expand_path(@pkg.icon, @root),
        output: output_dir
      )
    end
  end
end
