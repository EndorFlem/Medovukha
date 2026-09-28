# MonoCode cask

MonoCode is a native desktop GUI for coding agents. This tap uses the
upstream Apple Silicon release DMG, so it does not require Rust, Node.js, or
Xcode on the host.

Install:

~~~sh
brew install --cask EndorFlem/medovukha/monocode
~~~

The upstream agent CLIs must be installed and authenticated separately. MonoCode
uses their existing subscriptions and local login state; it does not provide
agent credentials itself.

Updates are checked weekly by a separate GitHub Action. After the tap receives
a new upstream release, the normal command is:

~~~sh
brew upgrade
~~~

## OMP-compatible source build

The binary cask above is the normal low-dependency install. This tap also has a
source cask that applies a small patch to MonoCode's OMP adapter: it negotiates
OMP RPC v2 and reassembles large chunked model catalogs, so the OMP models can
appear in MonoCode even when the catalog exceeds the RPC v1 frame limit.

The source build requires Apple Silicon, full Xcode, Node.js, and Rust:

~~~sh
brew install --cask EndorFlem/medovukha/monocode-source
~~~

It installs `~/Applications/MonoCode-local.app` and conflicts with the binary
`monocode` cask. The source revision and patch application are pinned; the
weekly updater advances the revision only when the patch still applies cleanly.
After a successful tap update, ordinary `brew upgrade` rebuilds the app.
