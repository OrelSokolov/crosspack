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
      # executables: basenames to chmod 0755
      def self.build(name:, version:, summary:, files:, executables: [],
                     identifier: nil, output:)
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

        write_info_plist(File.join(app_dir, 'Contents', 'Info.plist'),
                         name: name, version: version, summary: summary,
                         identifier: identifier)

        File.write(File.join(output, 'BUILD-DMG.txt'), <<~TXT)
          DMG not built: hdiutil only exists on macOS.
          On a Mac:  hdiutil create -volname #{name} -srcfolder #{name}.app -ov -format UDZO #{name}-#{version}.dmg
          Or archive the bundle:  zip -r #{name}-#{version}.zip #{name}.app
        TXT
        app_dir
      end

      def self.write_info_plist(path, name:, version:, summary:, identifier: nil)
        bundle_id = identifier || "org.crosspack.#{name}"
        File.write(path, <<~PLIST)
          <?xml version="1.0" encoding="UTF-8"?>
          <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
          <plist version="1.0">
          <dict>
            <key>CFBundleName</key>
            <string>#{name}</string>
            <key>CFBundleDisplayName</key>
            <string>#{name}</string>
            <key>CFBundleExecutable</key>
            <string>#{name}</string>
            <key>CFBundleIdentifier</key>
            <string>#{bundle_id}</string>
            <key>CFBundlePackageType</key>
            <string>APPL</string>
            <key>CFBundleShortVersionString</key>
            <string>#{version}</string>
            <key>CFBundleVersion</key>
            <string>#{version}</string>
            <key>CFBundleInfoDictionaryVersion</key>
            <string>6.0</string>
            <key>LSMinimumSystemVersion</key>
            <string>11.0</string>
            <key>NSPrincipalClass</key>
            <string>NSApplication</string>
            <key>NSSupportsAutomaticTermination</key>
            <true/>
            <key>NSSupportsSuddenTermination</key>
            <false/>
            <key>NSMicrophoneUsageDescription</key>
            <string>#{summary}</string>
          </dict>
          </plist>
        PLIST
      end
    end
  end
end
