# crosspack

Cross-platform build **and** pack toolchain for Wails-style desktop apps,
shipped as one gem with one command and a staged pipeline:

```
crosspack deps <target>     # verify/install the build host's dependencies
crosspack build <target>    # compile the target's matrix entry into builds/
crosspack pack <target>     # package builds/<target> as a native package
```

Every stage is keyed by the same target vocabulary — `debian-12`,
`ubuntu-24.04`, `fedora-41`, `arch`, `macos`, `windows-11.0` — and gated by
the previous one: `build` refuses to start before the deps stage passes, and
`pack` refuses to run before `build` filled `builds/<target>/`. The build
stage also stamps the version into the tree, so `pack` normally needs no
`--version`:

```
crosspack deps ubuntu-24.04
crosspack build ubuntu-24.04
crosspack pack ubuntu-24.04
```

## build.yaml — what and where to build

```yaml
name: myapp
version: calver            # calver | git-tag | env:VAR | any literal string
output: builds             # default builds; mirrors package.yaml `sources`

deps:                      # build dependencies, per-host verify/install
  imagemagick:
    hosts:                 # first selector matching this host wins
      ubuntu:
        verify: dpkg -s imagemagick
        install: sudo apt-get install -y imagemagick
      darwin:
        verify: magick -version
        install: brew install imagemagick
      windows:
        verify: where magick
        install: winget install -e --id ImageMagick.ImageMagick
      "*":                 # any command — package manager or a project script
        install: ./scripts/install-imagemagick.sh

matrix:
  - build: linux/amd64     # os/arch this entry builds on (arch may be "any")
    env:                   # extra env for the steps of this entry
      CGO_ENABLED: "1"
    steps:                 # shell commands, run from the project root
      - wails build -platform linux/amd64 -ldflags "-X myapp/internal/app.appVersion={{version}}"
      - cargo build --release -p helper --locked
    artifacts:
      from: build/bin      # what got built
      include: [myapp, helper, "*.onnx", "*.so*"]   # default: ["*"]
      to: [ubuntu-22.04, ubuntu-24.04, debian-12, debian-13]
      mode: symlink        # symlink | copy, default symlink

  - id: windows            # defaults to the build platform string
    build: windows/amd64
    steps:
      - wails build -platform windows/amd64 -ldflags "-X ...={{version}}"
    artifacts:
      from: build/bin
      include: [myapp.exe]
      to: [windows-11.0]
```

Placeholders `{{version}}`, `{{name}}`, `{{platform}}`, `{{os}}`, `{{arch}}`
and `{{id}}` are expanded by the gem itself (works the same under POSIX
shells and cmd.exe); the same facts are exported as `CROSSBUILD_VERSION`,
`CROSSBUILD_NAME`, ... environment variables. Steps may freely call existing
rake tasks (`rake build:prepare`) or helper scripts.

Artifacts land in the shared layout, e.g.:

```
builds/ubuntu/24.04/amd64/myapp -> build/bin/myapp   (symlink)
builds/windows/11.0/x86_64/myapp.exe
```

### Build dependencies (deps:)

`deps:` is the host axis to `deps.yaml`'s target axis: deps.yaml declares
what a *package* needs at runtime; `deps:` declares what the *build host*
must have. Checks differ per system, so every host rule carries its own
commands: `verify` (presence probe; exit 0 = present; without it the name is
looked up in PATH) and `install` (how to install it; may be omitted for
verify-only rules). Selectors are tried in order: distro id from
`/etc/os-release` (`ubuntu`), then `ID_LIKE` tokens (`debian`), then the os
(`linux`, `darwin`, `windows`), then `"*"`. The deps stage runs verify →
install → re-verify for every dependency; a dependency that is still missing
fails the stage. Commands support the `{{name}}`/`{{os}}`/... placeholders.

### Version schemes

| scheme        | value                                                      |
|---------------|------------------------------------------------------------|
| `calver`      | `YYYY.MM.DD-<secs since local midnight>`, e.g. `2026.08.31-33837` (default) |
| `git-tag`     | latest `git describe --tags --abbrev=0`, fallback `0.0.0-dev` |
| `env:VAR`     | taken from `VAR`; build fails loudly when unset            |
| other string  | used verbatim, e.g. `version: 1.2.3`                       |

## package.yaml + deps.yaml — what and how to pack

**`package.yaml`**:

```yaml
name: myapp
maintainer: Your Name <you@example.com>
summary: MyApp - cross-platform desktop application   # optional
description: |-
  MyApp - cross-platform desktop application.
  Bundles helper binaries and model assets alongside the GUI...
license: Proprietary       # optional, default Proprietary
section: utils             # optional, deb only

sources: builds             # compiled artifacts tree written by the build
                            # stage: builds/<family>/<version>/<arch>/ —
                            # pack without a matching build dir fails honestly
prefix: usr/local          # install prefix inside the package
lib_dir: lib/myapp       # optional, default lib/<name>

payload:                   # files from sources -> <prefix>/<lib_dir>/
  - myapp
  - helper
  - model.onnx

executables: [myapp, helper]     # chmod 755, must be in payload

links:                     # symlinks relative to prefix
  bin/myapp: ../lib/myapp/myapp

desktop:                   # optional, .desktop generated
  name: MyApp
  comment: Cross-platform desktop application
  categories: Utility;Audio

icon: build/appicon.png    # optional, -> <prefix>/share/pixmaps/<name>.png
```

**`deps.yaml`** — canonical dependency names resolved to concrete packages
per distro family/version. An optional top-level `version:` declares the
schema version; a deps.yaml written for a newer crosspack is rejected with
an upgrade hint:

```yaml
version: 1                  # optional, currently 1

webkit2gtk:
  targets:
    debian:
      "12": [libwebkit2gtk-4.1-0, libwebkit2gtk-4.0-37]  # deb: a | b
    fedora: { "*": [webkit2gtk4.1] }
    macos: system      # OS component
    windows: system    # preinstalled (WebView2)
```

All three files are validated against embedded schemas with actionable,
path-pointing error messages; every stage refuses to run on an invalid
manifest.

## CLI

```
# staged pipeline
crosspack deps <target> [--check]        # verify/install build deps (--check: report only)
crosspack build <target>|--all [--no-deps] [--version X]
crosspack pack <target> [--version X]    # version defaults to the build stamp

# inspection
crosspack validate                       # package.yaml, deps.yaml and build.yaml
crosspack resolve <target>               # Depends line for the target
crosspack matrix                         # deps x target + build matrix tables
crosspack version                        # computed build version
crosspack targets                        # what is in builds/ ready to pack
```

`pack` picks the builder from the target and writes to
`crosspacks/<family>/<version>/<arch>/`:

```
crosspacks/ubuntu/26.04/amd64/myapp_2026.08.31-1234_amd64.deb
crosspacks/fedora/41/x86_64/myapp-2026.08.31-1234.x86_64.rpm   (needs rpmbuild)
crosspacks/arch/x86_64/PKGBUILD
```

## Library

```ruby
require 'crosspack'   # pulls in Crossbuild too

Crossbuild.build('build.yaml', root: Dir.pwd)            # all host entries
Crossbuild.build('build.yaml', target: 'ubuntu-24.04')   # the stages' build, library-level

Crosspack.pack(
  manifest: 'package.yaml', deps: 'deps.yaml',
  target: Crosspack::Target.parse('debian-12', arch: 'amd64'),
  version: nil,        # nil -> the version stamped by the build stage
  root: Dir.pwd, output_base: 'crosspacks'
)
```

Lower-level pieces are public too: on the build side `Crossbuild::
BuildManifest`, `VersionScheme`, `Runner`, `Distributor`, `Matrix`,
`Builder`, `DepInstaller`, `Platform`; on the pack side `Crosspack::
PackageManifest`, `Manifest`, `Resolver`, `Matrix`, `Target`, `Builds`,
`Builders::*`.

Deb needs `dpkg-deb` (present on any Debian/Ubuntu), rpm needs
`rpmbuild` (`sudo apt install rpm`), PKGBUILD generation needs nothing.
The WiX builder generates `.wxs` sources (run the WiX Toolset yourself to
get an MSI), the macOS builder stages the `.app` bundle (signing, notarization
and .dmg creation are out of scope). Requires Ruby >= 3.2.

## Tests

```
cd crosspack && rake test
```
