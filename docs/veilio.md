# Veilio cask

Veilio is a Tauri desktop AI assistant for meetings, local Whisper
transcription, screenshots, voice input, and screen-share-safe overlays.

The tap uses the official Apple Silicon DMG published by the project website:

~~~sh
brew install --cask EndorFlem/medovukha/veilio
~~~

The binary cask is deliberate. The official DMG is signed and notarized by the
developer, while the public source repository currently has no stable release
tags or release assets. A source build also requires Node.js, Rust, full Xcode,
and Tauri's native build toolchain.

The weekly managed-cask workflow parses the official website for a versioned
`Veilio_<version>_aarch64.dmg` link, verifies that it comes from the official
Veilio CDN, downloads it, calculates SHA256, and updates `Casks/veilio.rb`.
Once the tap commit lands, normal `brew upgrade` handles the update.

The current website links an Apple Silicon DMG. The page text mentions Intel,
but no Intel macOS DMG link is currently published, so this cask is arm64-only.
