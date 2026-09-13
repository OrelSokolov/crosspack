# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
