package tui

import (
	"fmt"

	"github.com/charmbracelet/lipgloss"
	"github.com/charmbracelet/lipgloss/table"
)

func RenderKeyValue(pairs [][]string) string {
	out := ""
	for _, pair := range pairs {
		key := Muted.Render(fmt.Sprintf("  %-24s", pair[0]))
		val := pair[1]
		out += key + " " + val + "\n"
	}
	return out
}

func RenderTable(headers []string, rows [][]string) string {
	t := table.New().
		Border(lipgloss.NormalBorder()).
		BorderStyle(lipgloss.NewStyle().Foreground(lipgloss.Color("#00D4AA"))).
		Headers(headers...).
		Rows(rows...)

	return t.String()
}
