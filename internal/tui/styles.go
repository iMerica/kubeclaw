package tui

import "github.com/charmbracelet/lipgloss"

var (
	Primary = lipgloss.NewStyle().Foreground(lipgloss.Color("#00D4AA"))
	Success = lipgloss.NewStyle().Foreground(lipgloss.Color("#00CC66"))
	Warning = lipgloss.NewStyle().Foreground(lipgloss.Color("#FFAA00"))
	Error   = lipgloss.NewStyle().Foreground(lipgloss.Color("#FF4444"))
	Accent  = lipgloss.NewStyle().Foreground(lipgloss.Color("#AA66FF"))
	Muted   = lipgloss.NewStyle().Foreground(lipgloss.Color("#666666"))
	Bold    = lipgloss.NewStyle().Bold(true)
	White   = lipgloss.NewStyle().Foreground(lipgloss.Color("#FFFFFF"))

	Panel = lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(lipgloss.Color("#00D4AA")).
		Padding(1, 2)

	ErrorPanel = lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(lipgloss.Color("#FF4444")).
			Padding(1, 2)

	WarningPanel = lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(lipgloss.Color("#FFAA00")).
			Padding(1, 2)

	SectionHeader = lipgloss.NewStyle().
			Bold(true).
			Foreground(lipgloss.Color("#FFFFFF")).
			PaddingLeft(1)

	HR = lipgloss.NewStyle().
		Foreground(lipgloss.Color("#00D4AA"))
)

func RenderHR(width int) string {
	line := ""
	for i := 0; i < width; i++ {
		line += "━"
	}
	return HR.Render(line)
}

func RenderSection(title string, width int) string {
	header := Primary.Render("┃") + " " + SectionHeader.Render(title)
	return "\n" + header + "\n" + RenderHR(width)
}
