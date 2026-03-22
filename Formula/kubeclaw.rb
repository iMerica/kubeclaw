# typed: false
# frozen_string_literal: true

class Kubeclaw < Formula
  desc "CLI for managing KubeClaw Helm chart installations on Kubernetes"
  homepage "https://kubeclaw.ai"
  url "https://github.com/iMerica/kubeclaw/archive/refs/tags/v0.1.8-cli.0.tar.gz"
  sha256 "ccc447621419633e4173f7e26722da48a5c96043a7855fb57c1fc6b6f0012318"
  license "Apache-2.0"
  version "0.1.8-cli.0"

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
