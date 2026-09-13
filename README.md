# crosspack

Cross-platform build **and** pack toolchain for Wails-style desktop apps,
shipped as one gem, one command, one config file and a staged pipeline:

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

The target may be omitted — the stage commands then run for the current
host: `macos`, `windows-11.0` or the distro family + version from
`/etc/os-release` (unknown ids fall back to the first known `ID_LIKE`
token):

```
crosspack deps && crosspack build && crosspack pack
```

## crosspack.yml — one file, three sections

The top level carries the shared facts — `name` (required once) and the
optional `version` scheme — and three sections: `build:` (what and where to
build), `package:` (what and how to pack) and `deps:` (runtime dependencies
resolved to concrete packages per distro). The shared name/version feed the
build section, the name feeds the package section; each section keeps its
own schema.

```yaml
name: myapp
version: calver            # calver | git-tag | env:VAR | any literal string

build:
  output: builds           # default builds; mirrors package `sources`

  deps:                    # build dependencies, per-host verify/install
    imagemagick:
      hosts:               # first selector matching this host wins
        ubuntu:
          verify: dpkg -s imagemagick
          install: sudo apt-get install -y imagemagick
        darwin:
          verify: magick -version
          install: brew install imagemagick
        windows:
          verify: where magick
          install: winget install -e --id ImageMagick.ImageMagick
        "*":               # any command — package manager or a project script
          install: ./scripts/install-imagemagick.sh

  matrix:
    - build: linux/amd64   # os/arch this entry builds on (arch may be "any")
      env:                 # extra env for the steps of this entry
        CGO_ENABLED: "1"
      steps:               # shell commands, run from the project root
        - wails build -platform linux/amd64 -ldflags "-X myapp/internal/app.appVersion={{version}}"
        - cargo build --release -p helper --locked
      artifacts:
        from: build/bin    # what got built
        include: [myapp, helper, "*.onnx", "*.so*"]   # default: ["*"]
        to: [ubuntu-22.04, ubuntu-24.04, debian-12, debian-13]
        mode: symlink      # symlink | copy, default symlink

    - id: windows          # defaults to the build platform string
      build: windows/amd64
      steps:
        - wails build -platform windows/amd64 -ldflags "-X ...={{version}}"
      artifacts:
        from: build/bin
        include: [myapp.exe]
        to: [windows-11.0]

package:
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
  prefix: usr/local           # install prefix inside the package
  lib_dir: lib/myapp          # optional, default lib/<name>

  payload:                    # files from sources -> <prefix>/<lib_dir>/
    - myapp                   # flat form: the same name on every target
    - helper
    - model.onnx

  # Mapping form: per-target file names. The key is the common name (and the
  # default file name); selectors are an exact target (windows-11.0), a
  # family (windows), an os (linux — every distro family) or "*" — exact
  # target wins, then family, then os, then "*". An entry with selectors
  # applies only to targets it covers, so .so libraries and Windows DLLs can
  # share one payload:
  #
  # payload:
  #   myapp:
  #     "*": myapp
  #     windows: myapp.exe
  #   libonnxruntime.so.1:
  #     linux: libonnxruntime.so.1
  #   onnxruntime.dll:
  #     windows: onnxruntime.dll

  executables: [myapp, helper]     # common keys; chmod 755, resolved per target

  links:                     # symlinks relative to prefix
    bin/myapp: ../lib/myapp/myapp

  desktop:                   # optional, .desktop generated
    name: MyApp
    comment: Cross-platform desktop application
    categories: Utility;Audio

  icon: build/appicon.png    # optional, -> <prefix>/share/pixmaps/<name>.png

deps:
  # canonical dependency names resolved to concrete packages per distro
  # family/version; an optional `version:` declares the deps schema version
  webkit2gtk:
    targets:
      debian:
        "12": [libwebkit2gtk-4.1-0, libwebkit2gtk-4.0-37]  # deb: a | b
      fedora: { "*": [webkit2gtk4.1] }
      macos: system      # OS component
      windows: system    # preinstalled (WebView2)
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

### Build dependencies (build.deps)

`build.deps` is the host axis to the top-level `deps:` section's target
axis: the `deps:` section declares what a *package* needs at runtime;
`build.deps` declares what the *build host* must have. Checks differ per
system, so every host rule carries its own commands: `verify` (presence
probe; exit 0 = present; without it the name is looked up in PATH) and
`install` (how to install it; may be omitted for verify-only rules).
Selectors are tried in order: distro id from `/etc/os-release` (`ubuntu`),
then `ID_LIKE` tokens (`debian`), then the os (`linux`, `darwin`,
`windows`), then `"*"`. The deps stage runs verify → install → re-verify
for every dependency; a dependency that is still missing fails the stage.
Commands support the `{{name}}`/`{{os}}`/... placeholders.

### Version schemes

| scheme        | value                                                      |
|---------------|------------------------------------------------------------|
| `calver`      | `YYYY.MM.DD-<secs since local midnight>`, e.g. `2026.08.31-33837` (default) |
| `git-tag`     | latest `git describe --tags --abbrev=0`, fallback `0.0.0-dev` |
| `env:VAR`     | taken from `VAR`; build fails loudly when unset            |
| other string  | used verbatim, e.g. `version: 1.2.3`                       |

The whole file is validated against embedded schemas with actionable,
path-pointing error messages; every stage refuses to run on an invalid
config.

## CLI

```
# staged pipeline
crosspack deps <target> [--check]        # verify/install build deps (--check: report only)
crosspack build <target>|--all [--no-deps] [--version X]
crosspack pack <target> [--version X]    # version defaults to the build stamp

# inspection
crosspack validate                       # crosspack.yml: top level + all sections
crosspack resolve <target>               # Depends line for the target
crosspack matrix                         # deps x target + build matrix tables
crosspack version                        # computed build version
crosspack targets                        # what is in builds/ ready to pack

# options
-f, --file PATH                          # path to crosspack.yml (default: ./crosspack.yml)
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

Crossbuild.build('crosspack.yml', root: Dir.pwd)            # all host entries
Crossbuild.build('crosspack.yml', target: 'ubuntu-24.04')   # the stages' build, library-level

Crosspack.pack(
  config: 'crosspack.yml',
  target: Crosspack::Target.parse('debian-12', arch: 'amd64'),
  version: nil,        # nil -> the version stamped by the build stage
  root: Dir.pwd, output_base: 'crosspacks'
)
```

`Crosspack::Config.load('crosspack.yml')` parses and validates the file
once and exposes the sections as manifests. Lower-level pieces are public
too: on the build side `Crossbuild::BuildManifest`, `VersionScheme`,
`Runner`, `Distributor`, `Matrix`, `Builder`, `DepInstaller`, `Platform`;
on the pack side `Crosspack::PackageManifest`, `Manifest`, `Resolver`,
`Matrix`, `Target`, `Builds`, `Builders::*`.

Deb needs `dpkg-deb` (present on any Debian/Ubuntu), rpm needs
`rpmbuild` (`sudo apt install rpm`), PKGBUILD generation needs nothing.
The WiX builder generates `.wxs` sources (run the WiX Toolset yourself to
get an MSI), the macOS builder stages the `.app` bundle (signing,
notarization and .dmg creation are out of scope). Requires Ruby >= 3.2.

## Tests

```
cd crosspack && rake test
```
