class OpenAgPatcher < Formula
  include Language::Python::Virtualenv

  desc "Interactive Antigravity patcher for macOS, Linux and Windows"
  homepage "https://github.com/trustybird/AvenCores-open-antigravity-patcher"
  # Managed by scripts/update-antigravity-packages.rb.
  patcher_upstream_revision = "b59258fbc2f4c397e3b752c5a9033b5185bd9641"
  url "https://github.com/trustybird/AvenCores-open-antigravity-patcher/archive/#{patcher_upstream_revision}.tar.gz"
  version "1.3.8"
  sha256 "fd71ba277f8f5910b01b8a8c3942d024680b7842138124c9b9c80e726addd05f"
  license "GPL-3.0-only"

  livecheck do
    skip "Version is managed by the Antigravity package updater."
  end

  depends_on "python@3.14"

  resource "packaging" do
    url "https://files.pythonhosted.org/packages/20/12/38679034af332785aac8774540895e234f4d07f7545804097de4b666afd8/packaging-25.0-py3-none-any.whl"
    sha256 "29572ef2b1f17581046b3a2227d5c611fb25ec70ca1ba8554b24b0e69331a484"
  end

  def install
    venv = virtualenv_create(libexec, "python3.14")
    venv.pip_install resource("packaging")
    libexec.install "source"

    (bin/"open-ag-patcher").write <<~SH
      #!/bin/bash
      exec "#{opt_libexec}/bin/python" "#{opt_libexec}/source/main.py" "$@"
    SH
    chmod 0755, bin/"open-ag-patcher"
  end

  def caveats
    <<~EOS
      Run open-ag-patcher to open the interactive patch and restore menu.
      Installing this formula does not apply patches to Antigravity.
    EOS
  end
end
