class Runstir < Formula
  desc "Reproducible mobile development runtime"
  homepage "https://github.com/minjunkim-dev/mobile-runtime"
  url "https://github.com/minjunkim-dev/mobile-runtime/releases/download/v0.1.0-alpha.2/runstir-0.1.0-alpha.2-macos-arm64.tar.gz"
  version "0.1.0-alpha.2"
  sha256 "17aed50bd7c844bebef598340bd161fbefb6fd6da439e59d847f8eee97324628"
  license "Apache-2.0"

  depends_on arch: :arm64
  depends_on macos: :sonoma

  def install
    libexec.install Dir["*"]
    bin.install_symlink libexec/"mobile"
  end

  def caveats
    <<~EOS
      In your trusted React Native project, run:
        mobile doctor --json
        mobile doctor --platform android --json
      Prepare the project-specific Node, Ruby, JDK, Xcode and Android SDK versions.
      Runstir reports missing setup; it does not install tools or accept licenses.
    EOS
  end

  test do
    assert_match "doctor", shell_output("#{bin}/mobile --help")
    assert_equal "0.1.0", shell_output("#{bin}/mobile --version").strip
    assert_path_exists libexec/"mobile_Core.bundle"
    assert_path_exists libexec/"mobile_AndroidKit.bundle"
    metadata = JSON.parse((libexec/"BUILD.json").read)
    assert_equal version.to_s, metadata.fetch("releaseVersion")
  end
end
