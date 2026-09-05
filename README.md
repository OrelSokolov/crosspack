# crosspack

Cross-platform packer for Wails-style desktop apps: turns a compiled
artifacts directory into native packages (deb / rpm / PKGBUILD) for any
target distro × version × arch, driven by two small manifests.

Compilation is **not** crosspack's business — the app's build tasks produce
`build/bin`, crosspack only packages what is already there.

## Two manifests

**`package.yaml`** — what and how to pack:

```yaml
name: h2voice
maintainer: Oleg Orlov <orelcokolov@gmail.com>
summary: H2Voice - offline speech-to-text note taker   # optional
description: |-
  H2Voice - offline speech-to-text note taker
  Wails desktop app bundling whisper.cpp, Silero VAD models...
license: Proprietary       # optional, default Proprietary
section: sound             # optional, deb only

sources: builds             # compiled artifacts tree, mirrors crosspacks/:
                            # builds/<family>/<version>/<arch>/ — pack without
                            # a matching build directory fails honestly
prefix: usr/local          # install prefix inside the package
lib_dir: lib/h2voice       # optional, default lib/<name>

payload:                   # files from sources -> <prefix>/<lib_dir>/
  - h2voice
  - gigastt
  - silero_vad.onnx

executables: [h2voice, gigastt]     # chmod 755, must be in payload

links:                     # symlinks relative to prefix
  bin/h2voice: ../lib/h2voice/h2voice

desktop:                   # optional, .desktop generated
  name: H2Voice
  comment: Offline speech-to-text notes
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
crosspacks/ubuntu/26.04/amd64/h2voice_2026.08.31-1234_amd64.deb
crosspacks/fedora/41/x86_64/h2voice-2026.08.31-1234.x86_64.rpm   (needs rpmbuild)
crosspacks/arch/x86_64/PKGBUILD
```

## Library

```ruby
require 'crosspack'

Crosspack.pack(
  manifest: 'package.yaml', deps: 'deps.yaml',
  target: Crosspack::Target.parse('debian-12', arch: 'amd64'),
  version: '2026.08.31-1234',
  root: Dir.pwd, output_base: 'crosspacks'
)
```

Lower-level pieces are public too: `PackageManifest`, `Manifest`,
`Resolver`, `Matrix`, `Target`, `Builders::{Deb,Rpm,Pkgbuild}`.

Deb needs `dpkg-deb` (present on any Debian/Ubuntu), rpm needs
`rpmbuild` (`sudo apt install rpm`), PKGBUILD generation needs nothing.

## Tests

```
cd crosspack && rake test
```
