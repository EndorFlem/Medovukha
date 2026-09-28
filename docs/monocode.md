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
