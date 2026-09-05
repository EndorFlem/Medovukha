# Medovukha

Personal Homebrew tap for packages built or maintained by EndorFlem.
VoiceInk is the first package; other formulae and casks can be added to this
same repository later.

## VoiceInk source build

This tap builds the free VoiceInk source tree from Beingpax/VoiceInk. It does
not use the official paid voiceink cask or its precompiled binary.

The package is intentionally a cask rather than a formula. Homebrew formula
builds run inside Homebrew's sandbox, while VoiceInk's local build resolves
SwiftPM dependencies and invokes Xcode tools that need to manage their own
cache and sandbox. That combination failed with sandbox_apply. A cask
installer script is the supported Homebrew escape hatch for this kind of
installer and runs outside the cask sandbox.

The installer:

- downloads an archive pinned to one exact VoiceInk commit;
- builds the pinned macOS-only Whisper framework;
- runs make local with ad-hoc signing;
- compiles VoiceInk with Sparkle's updater disabled;
- on Swift 6.2.1/Xcode 26.2, pins mlx-swift to 0.31.4 and swift-syntax to
  602.0.0, whose manifests are compatible with that toolchain;
- installs the result as ~/Applications/VoiceInk-local.app;
- keeps build caches and rollback backups under
  ~/Library/Application Support/VoiceInkTap;
- does not remove VoiceInk user data.

## Installation

This repository is named Medovukha, not homebrew-medovukha, so add the
explicit SSH remote:

~~~sh
brew tap EndorFlem/medovukha git@github.com:EndorFlem/Medovukha.git
brew install EndorFlem/medovukha/voiceink-source
~~~

The local checkout used to maintain the tap is:

~~~text
~/.taps/Medovukha/
~~~

Required host tools:

- Apple Silicon;
- macOS Sequoia or newer;
- full Xcode with its macOS SDK and Swift toolchain;
- Command Line Tools, including Git and Make;
- Homebrew CMake.

The installer automatically selects /Applications/Xcode.app when xcode-select
currently points only at Command Line Tools. An explicit developer directory
still works:

~~~sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  brew install EndorFlem/medovukha/voiceink-source
~~~

An Xcode-version warning from Homebrew is separate from the source-build
logic. The tap does not delete Command Line Tools or require the destructive
sudo rm -rf /Library/Developer/CommandLineTools workaround.

For Xcode 26.2 the installer also forces Xcode to use the committed SwiftPM
versions and applies the known mlx-swift 0.31.4 and swift-syntax 602.0.0
compatibility pins. If a future VoiceInk commit changes either dependency to
an unknown incompatible version, the installer stops instead of silently
building a different dependency graph.

## Updates

Once installed from the tap, the normal update command is:

~~~sh
brew upgrade
~~~

The scheduled GitHub Action runs every four hours. It reads the latest commit
on Beingpax/VoiceInk main, downloads that commit archive, calculates its
SHA256, and updates the cask's revision, version, and archive checksum. A
changed version is then visible to ordinary brew upgrade, which runs the
installer again and rebuilds the app locally.

The version format is:

~~~text
YYYY.MM.DD.HHMMSS-<first-eight-commit-hex-digits>
~~~

There is no HEAD formula and no brew upgrade --fetch-HEAD step.

If Homebrew auto-update is disabled in your shell, refresh the tap explicitly:

~~~sh
brew update
brew upgrade
~~~

## Repository layout

~~~text
Medovukha/
├── Casks/voiceink-source.rb
├── scripts/update-voiceink-cask.rb
├── .github/workflows/update-voiceink-cask.yml
├── .github/workflows/test-voiceink-source.yml
├── .gitignore
└── README.md
~~~

update-voiceink-cask.yml needs repository Contents: Read and write permission
for the workflow token. If branch protection disallows direct workflow pushes,
change the final step to create a pull request instead.

## CI build test

The macOS workflow checks Ruby syntax and performs the actual cask install on
macos-15, then verifies the bundle identifier and code signature. It never
launches VoiceInk. The build is intentionally expensive because it compiles
Whisper and VoiceInk from source.
