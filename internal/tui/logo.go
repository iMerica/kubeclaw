package tui

import "fmt"

const logo = `
         ██╗  ██╗██╗   ██╗██████╗ ███████╗ ██████╗██╗      █████╗ ██╗    ██╗
         ██║ ██╔╝██║   ██║██╔══██╗██╔════╝██╔════╝██║     ██╔══██╗██║    ██║
         █████╔╝ ██║   ██║██████╔╝█████╗  ██║     ██║     ███████║██║ █╗ ██║
         ██╔═██╗ ██║   ██║██╔══██╗██╔══╝  ██║     ██║     ██╔══██║██║███╗██║
         ██║  ██╗╚██████╔╝██████╔╝███████╗╚██████╗███████╗██║  ██║╚███╔███╔╝
         ╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚══════╝ ╚═════╝╚══════╝╚═╝  ╚═╝ ╚══╝╚══╝`

func RenderLogo() string {
	rendered := Accent.Render(logo) + "\n"
	rendered += Muted.Render("  Run OpenClaw on Kubernetes with built-in guardrails") + "\n"
	rendered += Primary.Render("  https://kubeclaw.ai") + "\n"
	return rendered
}

func PrintLogo() {
	fmt.Println(RenderLogo())
}
