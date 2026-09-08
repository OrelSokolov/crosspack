# crosspack

Cross-platform build **and** pack toolchain for Wails-style desktop apps,
shipped as one gem with two cooperating commands:

- **`crossbuild`** — runs the build steps of a project from a small
  `build.yaml` matrix and fans the produced artifacts out into the
  per-target tree `builds/<family>[/<version>]/<arch>/`.
- **`crosspack`** — turns that compiled tree into native packages
  (deb / rpm / PKGBUILD / WiX / app bundle) for any target
  distro × version × arch, driven by two small manifests.

The two commands share the same target vocabulary (`Crosspack::Target`),
so the build tree and the pack tree never drift apart. Build and pack
stay cleanly separated: `crossbuild` never packages, `crosspack` never
compiles — feed the output of one straight into the other:

```
crossbuild build                          # builds/ tree
crosspack pack --target debian-12 --version 2026.08.31-33837
```

## crossbuild: build.yaml

```yaml
name: myapp
version: calver            # calver | git-tag | env:VAR | any literal string
output: builds             # default builds; mirrors package.yaml `sources`

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

### Version schemes

| scheme        | value                                                      |
|---------------|------------------------------------------------------------|
| `calver`      | `YYYY.MM.DD-<secs since local midnight>`, e.g. `2026.08.31-33837` (default) |
| `git-tag`     | latest `git describe --tags --abbrev=0`, fallback `0.0.0-dev` |
| `env:VAR`     | taken from `VAR`; build fails loudly when unset            |
| other string  | used verbatim, e.g. `version: 1.2.3`                       |

### crossbuild CLI

```
crossbuild validate                       # build.yaml against the schema
crossbuild matrix                         # entries × host buildability table
crossbuild version                        # computed version
crossbuild build [--target linux/amd64]   # all host-buildable entries, or one
crossbuild targets                        # what is in builds/ ready to pack
```

`build` refuses invalid manifests with path-pointing errors, runs only the
entries whose `build:` platform matches the host, then distributes.

## crosspack: two manifests

**`package.yaml`** — what and how to pack:

```yaml
name: myapp
maintainer: Your Name <you@example.com>
summary: MyApp - cross-platform desktop application   # optional
description: |-
  MyApp - cross-platform desktop application.
  Bundles helper binaries and model assets alongside the GUI...
license: Proprietary       # optional, default Proprietary
section: utils             # optional, deb only

sources: builds             # compiled artifacts tree written by crossbuild:
                            # builds/<family>/<version>/<arch>/ — pack without
                            # a matching build directory fails honestly
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
per distro family/version (see the file itself for the full schema):

```yaml
webkit2gtk:
  targets:
    debian:
      "12": [libwebkit2gtk-4.1-0, libwebkit2gtk-4.0-37]  # deb: a | b
    fedora: { "*": [webkit2gtk4.1] }
    macos: system      # OS component
    windows: system    # preinstalled (WebView2)
```

Both files are validated against embedded schemas with actionable,
path-pointing error messages; every builder refuses to run on an invalid
manifest.

## CLI

```
crosspack validate                       # both package.yaml and deps.yaml
crosspack resolve --target debian-12     # Depends line for the target
crosspack matrix                         # dependency x target table
crosspack pack --target debian-12 --version 2026.08.31-1234 [--root .]
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
Crossbuild.build('build.yaml', entry_id: 'windows')      # one entry explicitly

Crosspack.pack(
  manifest: 'package.yaml', deps: 'deps.yaml',
  target: Crosspack::Target.parse('debian-12', arch: 'amd64'),
  version: '2026.08.31-1234',
  root: Dir.pwd, output_base: 'crosspacks'
)
```

Lower-level pieces are public too: on the build side `Crossbuild::
BuildManifest`, `VersionScheme`, `Runner`, `Distributor`, `Matrix`,
`Builder`, `Platform`; on the pack side `Crosspack::PackageManifest`,
`Manifest`, `Resolver`, `Matrix`, `Target`, `Builders::*`.

Deb needs `dpkg-deb` (present on any Debian/Ubuntu), rpm needs
`rpmbuild` (`sudo apt install rpm`), PKGBUILD generation needs nothing.
The WiX builder generates `.wxs` sources (run the WiX Toolset yourself to
get an MSI), the macOS builder stages the `.app` bundle (signing, notarization
and .dmg creation are out of scope). Requires Ruby >= 3.2.

## Tests

```
cd crosspack && rake test
```
