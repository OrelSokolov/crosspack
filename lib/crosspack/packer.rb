# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'

module Crosspack
  # Single entry point: takes a compiled artifacts directory (per
  # package.yaml), resolves dependencies for the target (per deps.yaml) and
  # produces a native package under output_base/<family>/<version>/<arch>/.
  # The builder is chosen by the target format — deb, rpm or PKGBUILD.
  class Packer
    def self.pack(manifest:, deps:, target:, version:, root: Dir.pwd,
                  output_base: 'crosspacks')
      new(manifest: manifest, deps: deps, target: target, version: version,
          root: root, output_base: output_base).pack
    end

    def initialize(manifest:, deps:, target:, version:, root:, output_base:)
      @pkg_path = manifest
      @deps_path = deps
      @target = target
      @version = version.to_s
      @root = root
      @output_base = output_base
    end

    def pack
      @pkg = PackageManifest.load(@pkg_path)
      @deps = Manifest.load(@deps_path)
      validate_both!
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

    def validate_both!
      errors = []
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
              "No compiled artifacts for target #{@target}: expected them in #{src_dir}.\n" \
              "The builds tree (#{@pkg.sources}) mirrors the output tree: builds/<family>/<version>/<arch>/. " \
              "Currently #{hint}\n" \
              'Build the application for this target first, then pack.'
      end

      lib_dst = File.join(@pkg.prefix, @pkg.lib_dir)
      files = @pkg.payload.to_h { |n| [File.join(src_dir, n), File.join(lib_dst, n)] }

      if @pkg.icon
        icon_src = File.expand_path(@pkg.icon, @root)
        raise BuildError, "icon: file not found #{icon_src}" unless File.file?(icon_src)

        files[icon_src] = File.join(@pkg.prefix, 'share', 'pixmaps', "#{@pkg.name}.png")
      end

      if @pkg.desktop
        files[desktop_entry_path] = File.join(@pkg.prefix, 'share', 'applications', "#{@pkg.name}.desktop")
      end

      symlinks = @pkg.links.to_h { |link, target| [File.join(@pkg.prefix, link), target] }
      executables = @pkg.executables.map { |exe| File.join(lib_dst, exe) }

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
      File.write(path, <<~DESKTOP)
        [Desktop Entry]
        Type=Application
        Name=#{d['name'] || @pkg.name}
        Comment=#{d['comment'] || @pkg.summary}
        Exec=#{d['exec'] || @pkg.name}
        Icon=#{@pkg.name}
        Terminal=false
        Categories=#{d['categories'] || 'Utility;'}
      DESKTOP
      path
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
        description: @pkg.summary,
        arch: @target.package_arch(:rpm),
        output: output
      )
      output
    end

    def pack_pkgbuild
      version, release = split_version
      output = File.join(@target.output_dir(@output_base, :pkgbuild), 'PKGBUILD')
      Builders::Pkgbuild.generate(
        name: @pkg.name,
        version: version,
        release: release,
        pkgdesc: @pkg.summary,
        depends: resolved_depends(:pkgbuild),
        arch: [@target.package_arch(:pkgbuild)],
        # PKGBUILD sources are archive-relative names, not local paths.
        files: @pkg.payload.to_h { |n| [n, File.join(@pkg_data[:lib_dst], n)] },
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
    def pack_windows
      output = File.join(@target.output_dir(@output_base, :winget),
                         "#{@pkg.name}-#{Builders::Wix.msi_version(@version)}.msi")
      files = @pkg.payload.to_h { |n| [File.join(@pkg_data[:src_dir], n), n] }
      Builders::Wix.build(
        name: @pkg.name,
        version: @version,
        manufacturer: @pkg.maintainer,
        summary: @pkg.summary,
        files: files,
        arch: @target.package_arch(:winget),
        output: output
      )
    end

    # macOS: .app bundle staging; DMG itself requires a Mac (hdiutil).
    def pack_macos
      output_dir = @target.output_dir(@output_base, :cask)
      files = @pkg.payload.to_h { |n| [File.join(@pkg_data[:src_dir], n), n] }
      Builders::AppDir.build(
        name: @pkg.name,
        version: @version,
        summary: @pkg.summary,
        files: files,
        executables: @pkg.executables,
        output: output_dir
      )
    end
  end
end
