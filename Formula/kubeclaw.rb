# typed: false
# frozen_string_literal: true

class Kubeclaw < Formula
  desc "CLI for managing KubeClaw Helm chart installations on Kubernetes"
  homepage "https://kubeclaw.ai"
  url "https://github.com/iMerica/kubeclaw/archive/refs/tags/v0.1.10-cli.0.tar.gz"
  sha256 "62c6ca7f767b4f37e0ced0d13bd58e2f1ae4de07be64aba9730c5a0b6ff76dce"
  license "Apache-2.0"
  version "0.1.10-cli.0"

  depends_on "go" => :build

  def install
    ldflags = %W[
      -s -w
      -X github.com/iMerica/kubeclaw/internal/config.Version=#{version}
      -X github.com/iMerica/kubeclaw/internal/config.Commit=homebrew
    ]
    system "go", "build", *std_go_args(ldflags:), "./cmd/kubeclaw"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/kubeclaw version")
  end
end
