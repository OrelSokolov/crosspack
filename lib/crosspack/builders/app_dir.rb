# frozen_string_literal: true

require 'fileutils'

module Crosspack
  module Builders
    # Stages a macOS .app bundle directory (MyApp.app/Contents/...). A real
    # DMG requires hdiutil (macOS only); from Linux this directory layout is
    # the honest maximum — it can be zipped or wrapped into a DMG on a Mac
    # as-is.
    class AppDir
      # files: { source_path => basename inside Contents/MacOS }
      # executables: basenames to chmod 0755 (the first one is the bundle's
      #   CFBundleExecutable, falling back to the package name)
      # icon: path to the bundle icon, copied into Contents/Resources
      def self.build(name:, version:, summary:, files:, executables: [],
                     display_name: nil, icon: nil, identifier: nil,
                     min_macos: '11.0', output:)
        app_dir = File.join(output, "#{name}.app")
        FileUtils.rm_rf(app_dir)
        macos_dir = File.join(app_dir, 'Contents', 'MacOS')
        resources_dir = File.join(app_dir, 'Contents', 'Resources')
        FileUtils.mkdir_p(macos_dir)
        FileUtils.mkdir_p(resources_dir)

        missing = files.reject { |src, _dst| File.file?(src) }
        unless missing.empty?
          details = missing.map { |src, dst| "  ✗ #{src} (for #{dst})" }.join("\n")
          raise BuildError,
                "Source files for packing not found:\n#{details}\n" \
                'Build the application for the target platform first.'
        end

        files.each do |src, dst|
          target = File.join(macos_dir, dst)
          FileUtils.cp(src, target)
          FileUtils.chmod(executables.include?(dst) ? 0o755 : 0o644, target)
        end

        icon_file = nil
        if icon
          raise BuildError, "icon: file not found #{icon}" unless File.file?(icon)

          icon_file = File.basename(icon)
          FileUtils.cp(icon, File.join(resources_dir, icon_file))
        end

        write_info_plist(File.join(app_dir, 'Contents', 'Info.plist'),
                         name: name, version: version, summary: summary,
                         executable: executables.first || name,
                         display_name: display_name || name,
                         icon_file: icon_file, identifier: identifier,
                         min_macos: min_macos)

        File.write(File.join(output, 'BUILD-DMG.txt'), <<~TXT)
          DMG not built: hdiutil only exists on macOS.
          On a Mac:  hdiutil create -volname #{name} -srcfolder #{name}.app -ov -format UDZO #{name}-#{version}.dmg
          Or archive the bundle:  zip -r #{name}-#{version}.zip #{name}.app
        TXT
        app_dir
      end

      def self.write_info_plist(path, name:, version:, summary:, executable:,
                                display_name:, icon_file: nil, identifier: nil,
                                min_macos: '11.0')
        bundle_id = identifier || "org.crosspack.#{name}"
        # Without the extension .icns is assumed; other formats (png) must
        # be named in full.
        icon_ref = icon_file.nil? ? nil : icon_file.sub(/\.icns\z/i, '')
        File.write(path, <<~PLIST)
          <?xml version="1.0" encoding="UTF-8"?>
          <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
          <plist version="1.0">
          <dict>
            <key>CFBundleName</key>
            <string>#{escape(name)}</string>
            <key>CFBundleDisplayName</key>
            <string>#{escape(display_name)}</string>
            <key>CFBundleExecutable</key>
            <string>#{escape(executable)}</string>
            <key>CFBundleIdentifier</key>
            <string>#{escape(bundle_id)}</string>
            <key>CFBundlePackageType</key>
            <string>APPL</string>
            <key>CFBundleShortVersionString</key>
            <string>#{escape(version)}</string>
            <key>CFBundleVersion</key>
            <string>#{escape(version)}</string>
            <key>CFBundleInfoDictionaryVersion</key>
            <string>6.0</string>
            <key>LSMinimumSystemVersion</key>
            <string>#{escape(min_macos)}</string>
            <key>NSPrincipalClass</key>
            <string>NSApplication</string>
            <key>NSSupportsAutomaticTermination</key>
            <true/>
            <key>NSSupportsSuddenTermination</key>
            <false/>
            <key>NSMicrophoneUsageDescription</key>
            <string>#{escape(summary)}</string>
          #{plist_icon_entry(icon_ref)}
          </dict>
          </plist>
        PLIST
      end

      def self.plist_icon_entry(icon_ref)
        return '' if icon_ref.nil?

        "    <key>CFBundleIconFile</key>\n    <string>#{escape(icon_ref)}</string>"
      end

      # Escapes XML entities so manifest values never break the plist.
      def self.escape(text)
        text.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
      end
    end
  end
end
