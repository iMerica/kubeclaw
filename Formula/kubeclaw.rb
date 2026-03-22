# typed: false
# frozen_string_literal: true

class Kubeclaw < Formula
  desc "CLI for managing KubeClaw Helm chart installations on Kubernetes"
  homepage "https://kubeclaw.ai"
  url "https://github.com/iMerica/kubeclaw/archive/refs/tags/v0.1.7-cli.0.tar.gz"
  sha256 "1c8357c21d1c18054360da80b28624b9e2e465a596ef4753213d447022fc4826"
  license "Apache-2.0"
  version "0.1.7-cli.0"

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
