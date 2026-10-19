# Medovukha

Personal Homebrew tap for packages built or maintained by EndorFlem.
VoiceInk is the source-built cask in this repository.

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
- compiles VoiceInk with Sparkle's updater code and metadata disabled;
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

VoiceInk host requirements:

- Apple Silicon;
- macOS Sequoia or newer;
- full Xcode with its macOS SDK and Swift toolchain;
- Xcode's Metal Toolchain component;
- Command Line Tools, including Git and Make;
- Homebrew CMake.

If Xcode reports a missing Metal Toolchain, install the component once:

~~~sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -downloadComponent MetalToolchain
~~~

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

The local build passes xcodebuild's skipMacroValidation flag only for this
pinned VoiceInk build. This avoids changing Xcode's macro-validation policy
globally; the trade-off is that the source and all SwiftPM revisions in the
build must be trusted.

## Updates

Once installed from the tap, the normal update command is:

~~~sh
brew upgrade
~~~

The scheduled GitHub Action runs once a week on Monday at 03:17 UTC. It
checks the latest commits on Beingpax/VoiceInk main, calculates the archive's
SHA256 value, and updates the VoiceInk cask. A changed version is then picked
up by ordinary brew upgrade, which rebuilds the local app.

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
├── Formula/telegram-mcp-source.rb
├── docs/telegram-mcp.md
├── scripts/update-voiceink-cask.rb
├── scripts/update-telegram-mcp-formula.rb
├── .github/workflows/update-voiceink-cask.yml
├── .github/workflows/update-telegram-mcp.yml
├── .gitignore
└── README.md
~~~

update-voiceink-cask.yml needs repository Contents: Read and write permission
for the workflow token. If branch protection disallows direct workflow pushes,
change the final step to create a pull request instead.
