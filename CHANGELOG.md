# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
