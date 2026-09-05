# `Medovukha`: VoiceInk source formula

This tap builds the free, local VoiceInk source tree from `Beingpax/VoiceInk`.
It never uses the official `voiceink` cask or its precompiled commercial
binary.

This repository is hosted as:

```text
github.com/EndorFlem/Medovukha
```

`Medovukha` is a general personal tap, not a repository for only VoiceInk.
Other formulae and casks can be added next to this one.

## User workflow

Because the GitHub repository does not use Homebrew's conventional
`homebrew-*` name, register it with an explicit remote URL:

```sh
brew tap EndorFlem/medovukha git@github.com:EndorFlem/Medovukha.git
brew install EndorFlem/medovukha/voiceink-source
```

The one-argument form `brew tap EndorFlem/medovukha` would look for a
repository named `homebrew-medovukha`, so do not use it for this repository.

The formula installs the app bundle inside its Homebrew prefix and installs a
launcher on `PATH`:

```sh
voiceink-source
voiceink-source --path
voiceink-source --version
```

The app lives at:

```text
$(brew --prefix voiceink-source)/libexec/VoiceInk.app
```

The formula does not copy anything to `/Applications`. That keeps Homebrew in
control of the versioned bundle and avoids colliding with the paid
`/Applications/VoiceInk.app` cask.

## Updating

The normal update path is:

```sh
brew upgrade
```

Homebrew first refreshes the tap metadata during a normal upgrade. The
scheduled workflow updates the formula when `Beingpax/VoiceInk` gets a new
commit on `main`.

The formula version has this shape. The time component keeps two commits from
the same day ordered for Homebrew's version comparison.

```text
YYYY.MM.DD.HHMMSS-<first-eight-hex-digits-of-commit>
```

The source archive URL and SHA256 are pinned to the same full commit. A new
commit therefore becomes a new Homebrew version and `brew upgrade` rebuilds
the formula.

If `HOMEBREW_NO_AUTO_UPDATE` is set in the shell, run `brew update` before
`brew upgrade`; otherwise no manual tap update is needed.

## Repository layout

The local checkout is kept at:

```text
~/.taps/Medovukha/
```

```text
Medovukha/
├── Formula/voiceink-source.rb
├── scripts/update-voiceink-formula.rb
├── .github/workflows/update-voiceink-formula.yml
├── .github/workflows/test-voiceink-source.yml
├── .gitignore
└── README.md
```

## Formula build

`Formula/voiceink-source.rb`:

- downloads a GitHub archive pinned to `VOICEINK_UPSTREAM_REVISION`;
- builds a pinned Whisper resource instead of cloning `whisper.cpp` from a
  moving branch during the formula build;
- sets `LOCAL_BUILD` through the upstream `make local` target;
- forces ad-hoc signing so an Apple Developer certificate is not required;
- points `HOME` at the Homebrew build directory only while `make local` is
  running, keeping Whisper and build output out of the user's home directory;
- disables the Sparkle updater in the local build at compile time, so the
  source build cannot replace itself with the commercial release;
- installs `VoiceInk.app` under `libexec` and a stable `voiceink-source`
  launcher under `bin`;
- fails if the upstream updater source moves and the safety patch no longer
  matches.

The current upstream project requires Xcode with Command Line Tools, CMake,
macOS 15 or later, and Apple Silicon. Homebrew provides the Git and CMake
build dependencies, but it cannot provide Xcode or Apple's signing tools.

The Whisper resource is pinned separately from the VoiceInk commit. If a
future VoiceInk commit needs a newer Whisper API, update that resource and
its SHA256 deliberately, then let the macOS build workflow prove the result.

## Scheduled formula updater

`.github/workflows/update-voiceink-formula.yml` runs every four hours and can
also be started with `workflow_dispatch`. It:

1. reads the current `main` commit from `Beingpax/VoiceInk`;
2. reads `VOICEINK_UPSTREAM_REVISION` from the formula;
3. downloads the commit archive and calculates its SHA256;
4. fetches the commit date;
5. updates the revision, version, and SHA256;
6. commits and pushes only when the revision changed.

The workflow needs repository `Contents: Read and write` permission. Branch
protection rules must also allow the workflow token to push, or the final
push step must be changed to open a pull request instead.

## Build test

`.github/workflows/test-voiceink-source.yml` runs on `macos-15` when the
formula changes, once per day, or through `workflow_dispatch`. It runs the
actual Homebrew formula install, `brew test`, bundle metadata checks, and
code-signature verification. It never launches VoiceInk.

The same checks can be run manually after publishing the tap:

```sh
brew style --formula Formula/voiceink-source.rb
brew install --build-from-source --formula --verbose ./Formula/voiceink-source.rb
brew test --verbose voiceink-source
```

The Homebrew build and test can take several minutes because `make local`
also builds the Whisper framework.
