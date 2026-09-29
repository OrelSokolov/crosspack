# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.8.0] - 2026-09-27

### Added
- Make-style build goals: a matrix entry may declare `goals:` and its `id`
  doubles as a goal name, so a per-binary entry works with no extra syntax.
  `crosspack build` compiles only the `default` goal's entries,
  `crosspack build all` every host-buildable entry, `crosspack build
  <goal>` one goal or binary (`crosspack build helloworld` rebuilds nothing
  else). `crosspack run [goal]` builds just that goal before launching, and
  launches the executable named by a binary goal instead of the first one;
  `crosspack build <package-target>` (e.g. `debian-12`) still works when
  the name is not a goal or entry id. `crosspack matrix` and
  `crosspack validate` list each entry's goals.

[0.8.0]: https://github.com/OrelSokolov/crosspack/releases/tag/v0.8.0

## [0.7.3] - 2026-09-26

### Fixed
- The manifest icon keeps its real extension everywhere: an SVG now installs
  to `share/icons/hicolor/scalable/apps/<name>.svg` (it was forced to
  `share/pixmaps/<name>.png`, where desktops never found it); PNG/XPM keep
  going to pixmaps.
- `.desktop` `Categories` values are terminated with `;` per the spec — a
  manifest value like `Utility;Audio` produced an invalid entry GNOME could
  refuse to show.
- macOS `Info.plist` escapes XML entities (`&`/`<` in the summary no longer
  corrupt the plist), `CFBundleExecutable` is the first `package.executables`
  entry (not the package name) and the bundle icon from `icon:` is copied to
  `Contents/Resources` and referenced via `CFBundleIconFile`.
- RPM `%description` carries the full package description, not just the
  summary line.
- PKGBUILD quotes the `license` value (a license with spaces broke the
  generated bash).
- deb omits an empty `Depends:` field instead of writing an invalid one.
- WiX `Source` paths are XML-escaped (`&` in a path no longer breaks the
  generated `.wxs`).

### Added
- The PKGBUILD now installs the `.desktop` file and the icon — desktop
  integration was deb/rpm-only. Crosspack also builds the source tarball
  (`<name>-<version>.tar.gz`) next to the PKGBUILD with the exact file names
  and layout the install lines expect, so `makepkg` works out of the box —
  and the PKGBUILD carries its real sha256 instead of `SKIP`.
- deb/rpm packages with a `.desktop` file or a themed icon refresh the
  application database and the hicolor icon cache (`postinst`/`postrm`,
  `%post`/`%postun`); the tools are guarded, minimal systems without them
  are fine.
- Windows MSI gets an Add/Remove Programs icon (`ARPPRODUCTICON`): the
  manifest `icon:` when it is an `.ico`, else a sibling `.ico` with the same
  basename (`appicon.png` -> `appicon.ico`) when the build produces one.
- `package.min_macos` sets the .app bundle's `LSMinimumSystemVersion`
  (default stays 11.0).

### Fixed
- `.desktop` `Exec` is now an absolute path — the launcher symlink from
  `links:` (e.g. `/usr/local/bin/h2voice`) or the executable inside
  `lib_dir`; a bare name only resolved when `prefix/bin` happened to be in
  PATH.

[0.7.3]: https://github.com/OrelSokolov/crosspack/releases/tag/v0.7.3

## [0.7.2] - 2026-09-26

### Fixed
- Windows MSI no longer fails to install with error 1324: the payload
  directory is now `INSTALLFOLDER` (WiX v4+ treats any other Id as "author
  did not define it" and injects a phantom `[Manufacturer] [ProductName]`
  directory). The deb-style `Name <email>` maintainer is sanitized to the
  name half before it reaches the MSI Manufacturer property.
- calver versions (e.g. `2026.09.26`) map to a valid MSI ProductVersion
  (`26.9.26`) in the `Package@Version` attribute too, not just the file
  name — a major >= 256 tripped WIX1148.

### Added
- The Windows MSI now has a standard install wizard (`ui:WixUI
  WixUI_InstallDir` with the license dialog): crosspack generates the
  license `.rtf` and builds with `-ext WixToolset.UI.wixext`, installing the
  UI extension itself when missing (`WixToolset.UI.wixext/6.0.1` on WiX 6).
- Start Menu and Desktop shortcuts for the first `package.executables`
  entry; the display name comes from `package.desktop.name` (falling back
  to the package name). Previously the winget target ignored `desktop:`.

[0.7.2]: https://github.com/OrelSokolov/crosspack/releases/tag/v0.7.2

## [0.7.0] - 2026-09-13

### Added
- Host-only commands: `crosspack run` builds for the current host (the same
  stage `crosspack build <host target>` runs) and then launches the main
  binary straight from `builds/` — the first `package.executables` entry,
  not the package. Arguments after `--` are passed to the app
  (`crosspack run -- --dev`); the app's exit code is propagated.
- `crosspack install` launches this host's package with its system
  installer: the newest package in `crosspacks/<host target>/` goes to
  `xdg-open` (deb/rpm), `msiexec /i` (MSI) or `open` (macOS dmg/.app);
  for arch crosspack generates only a PKGBUILD, so it points at
  `makepkg -si`.
- crosspack.yml `run:` / `install:` sections: per-host launch-command
  overrides using the same host selectors as `build.deps` (distro id,
  ID_LIKE, os, `"*"`), with the `{{path}}` placeholder (the built binary
  for run, the package file for install) plus the usual build facts.
  Default without a `run:` section: execute the binary directly (a macOS
  `.app` bundle is `open`ed).

[0.7.0]: https://github.com/OrelSokolov/crosspack/releases/tag/v0.7.0

## [0.6.2] - 2026-09-13

### Added
- Colored CLI output via the new `colorize` runtime dependency: success
  messages green, errors red, validation warnings yellow (the `ok`/`MISSING`
  statuses in the deps report included). Colors apply only to a TTY and
  respect `NO_COLOR`, so piped and logged output stays plain.
- The gem now ships `logo.png` in its files.

## [0.6.1] - 2026-09-13

### Fixed
- `crosspack deps` no longer dumps a Ruby backtrace when the (detected or
  given) target has no matrix entry — it aborts with the plain message, now
  with an actionable hint (pass a declared target or extend artifacts.to).
- `crosspack --version` (bare, also `-v`) prints the gem version instead of
  demanding an argument; `--version X` keeps overriding the build/pack
  version.

[0.6.2]: https://github.com/OrelSokolov/crosspack/releases/tag/v0.6.2
[0.6.1]: https://github.com/OrelSokolov/crosspack/releases/tag/v0.6.1

## [0.6.0] - 2026-09-13

### Added
- Host target default: `crosspack deps` / `build` / `pack` invoked without a
  target run for the current host — `macos`, `windows-11.0` or the distro
  family + version from `/etc/os-release` (unknown distro ids fall back to
  the first known `ID_LIKE` token; unrecognizable hosts ask for an explicit
  target).
- Per-target payload names: `package.payload` entries may now be written as a
  mapping `common key -> {target selector -> real file name}` instead of a
  flat list. The key is the common name (used verbatim on every target
  unless overridden); selectors are an exact target (`windows-11.0`), a
  family (`windows`) or `"*"` (exact target wins, then family, then `"*"`).
  An entry with a selector map applies only to targets it covers, so one
  payload lists `app`/`app.exe`, `.so` libraries and Windows DLLs together —
  each target resolves to the files its build actually produced. The flat
  list form remains valid (same name everywhere). `executables` keeps naming
  common keys and resolves per target at pack time.

[0.6.0]: https://github.com/OrelSokolov/crosspack/releases/tag/v0.6.0

## [0.5.1] - 2026-09-13

### Fixed
- Gem metadata: the summary/description no longer mention the removed
  build.yaml — they describe the single crosspack.yml config.

## [0.5.0] - 2026-09-13

### Breaking
- One config file: `build.yaml`, `package.yaml` and `deps.yaml` are merged
  into a single `crosspack.yml` with `build:` / `package:` / `deps:`
  sections and a shared top-level `name:` (plus optional `version:`, the
  build version scheme). The three old files are no longer read — move each
  file's body under its section, hoist `name`/`version` to the top. No
  migration path is provided (0.4.0 was never published beyond local gem
  builds).
- CLI: `-f/--file` now points at crosspack.yml (default `./crosspack.yml`);
  the `--package` and `--build` flags are gone.
- Library API: `Crosspack.pack` takes `config:` (a Config or a path to
  crosspack.yml); `Crossbuild.build` accepts a Config, a path or a ready
  BuildManifest; the manifest classes no longer read files —
  `Manifest.load` / `PackageManifest.load` / `BuildManifest.load` are gone,
  `Crosspack::Config.load` is the single loader.

### Added
- `Crosspack::Config`: top-level validation (name required once, version
  scheme, unknown keys) with the shared name/version injected into the
  build section and the name into the package section; each section keeps
  its own schema and path-pointing error messages.

## [0.4.0] - 2026-09-13

### Breaking
- The separate `crossbuild` executable is gone: one command, one staged
  pipeline — `crosspack deps <target>` → `crosspack build <target>` →
  `crosspack pack <target>`. The former crossbuild commands moved under
  `crosspack` (validate/matrix/version gained build.yaml coverage; the gem
  now installs only the `crosspack` binary).
- build.yaml `deps:` schema: host rules are now mappings with per-system
  `verify` and `install` commands instead of a global `check:` plus a
  bare command string. The 0.3.0 schema was never released outside the
  local gem build, so no migration path is provided.
- `crosspack pack <target>` takes the target as a positional argument
  (the old `--target` flag is gone) and `--version` is now optional: it
  defaults to the version stamped by the build stage.

### Added
- Stage pipeline with gating: `crosspack build <target>` resolves the
  matrix entry distributing to that target, runs the deps stage first,
  and fans artifacts out into that target's builds/ directory only;
  `crosspack pack <target>` refuses to run before the build stage
  ("Build stage not done for target ... — Run: crosspack build <target>").
- The build stage stamps `.crosspack-build` (version) into every
  `builds/<target>/` directory; `crosspack pack` reads it as the default
  package version.
- deps.yaml schema versioning: an optional top-level `version:` (default
  1). A deps.yaml declaring a newer schema than this crosspack is
  rejected at load time with an upgrade hint; the key is reserved and no
  longer parsed as a canonical dependency name.
- deps: rules may be verify-only (no install command) — presence is
  checked, and a missing dependency reports which `install:` to add.

## [0.3.0] - 2026-09-13

### Added
- build.yaml `deps:` section: build dependencies with per-host install
  commands (e.g. `ubuntu: sudo apt-get install -y imagemagick`, `windows:
  winget install ...`, or any project script). Host selectors resolve in
  order: distro id from `/etc/os-release`, `ID_LIKE` tokens, os, `"*"`.
- `crossbuild deps` command: doctor + install of the deps: dependencies;
  `--check` reports presence only and exits 1 when something is missing.
- `crossbuild build` now verifies/installs deps: dependencies before the
  matrix entries; `--no-deps` skips the pass.
- `crossbuild matrix` lists how each deps: entry resolves on this host.

## [0.2.1] - 2026-09-11

### Fixed
- WiX builder: `wix build` is now invoked with `-arch <arch>` as separate
  argv entries — the previous single `"-arch x64"` argument could never parse.
- WiX builder: a bare `dotnet` on PATH is no longer mistaken for the WiX
  toolset (`dotnet build` cannot build an MSI); only a real `wix` command
  triggers the real MSI build, otherwise the `.wxs` + `BUILD-MSI.txt`
  fallback is emitted.
- WiX builder: manifest values (name, maintainer, summary) are XML-escaped
  in the generated `.wxs`; a maintainer like `Name <email>` previously
  produced invalid XML no WiX build could parse.

## [0.2.0] - 2026-09-08

### Added
- Merged the `crossbuild` gem into `crosspack`: one gem, two commands.
  `crossbuild build` runs `build.yaml` matrix steps on the host and fans
  artifacts out into `builds/<family>[/<version>]/<arch>/`; `crosspack pack`
  packages that tree as before.
- `build.yaml` manifest with schema validation, version schemes
  (`calver` / `git-tag` / `env:VAR` / literal), `{{version}}`-style
  placeholder expansion and `CROSSBUILD_*` environment facts.
- crossbuild CLI: `validate`, `matrix`, `version`, `build`, `targets`.
- Library API: `Crossbuild.build` plus public `BuildManifest`,
  `VersionScheme`, `Runner`, `Distributor`, `Matrix`, `Builder`, `Platform`.

## [0.1.0] - 2026-09-08

### Added
- `package.yaml` / `deps.yaml` manifests with embedded schema validation and
  path-pointing error messages.
- Dependency resolution per distro family/version (`Resolver`), dependency ×
  target matrix rendering (`Matrix`).
- Builders: deb (`dpkg-deb`), rpm (`rpmbuild`), PKGBUILD, WiX sources (`.wxs`),
  macOS app bundle staging.
- CLI: `validate`, `resolve`, `matrix`, `pack`, `targets`.
- Library API: `Crosspack.pack` plus public `PackageManifest`, `Manifest`,
  `Resolver`, `Matrix`, `Target`, `Builders::*`.

[0.2.0]: https://github.com/OrelSokolov/crosspack/releases/tag/v0.2.0
[0.1.0]: https://github.com/OrelSokolov/crosspack/releases/tag/v0.1.0
