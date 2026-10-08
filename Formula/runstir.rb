class Runstir < Formula
  desc "Reproducible mobile development runtime"
  homepage "https://github.com/minjunkim-dev/mobile-runtime"
  url "https://github.com/minjunkim-dev/mobile-runtime/releases/download/v0.1.0-alpha.4/runstir-0.1.0-alpha.4-macos-arm64.tar.gz"
  version "0.1.0-alpha.4"
  sha256 "4aa0acf7d864507c524b69e554aab615c3a89b5b27519ad71355366ac98aa22c"
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
