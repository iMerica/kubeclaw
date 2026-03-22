package tui

import (
	"fmt"

	"github.com/charmbracelet/bubbles/spinner"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

type SpinnerModel struct {
	spinner spinner.Model
	message string
	done    bool
	err     error
	action  func() error
}

type spinnerDoneMsg struct{ err error }

func NewSpinner(message string, action func() error) SpinnerModel {
	s := spinner.New()
	s.Spinner = spinner.Dot
	s.Style = lipgloss.NewStyle().Foreground(lipgloss.Color("#00D4AA"))
	return SpinnerModel{
		spinner: s,
		message: message,
		action:  action,
	}
}

func (m SpinnerModel) Init() tea.Cmd {
	return tea.Batch(m.spinner.Tick, m.runAction())
}

func (m SpinnerModel) runAction() tea.Cmd {
	return func() tea.Msg {
		err := m.action()
		return spinnerDoneMsg{err: err}
	}
}

func (m SpinnerModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case spinnerDoneMsg:
		m.done = true
		m.err = msg.err
		return m, tea.Quit
	case tea.KeyMsg:
		if msg.String() == "ctrl+c" {
			return m, tea.Quit
		}
	case spinner.TickMsg:
		var cmd tea.Cmd
		m.spinner, cmd = m.spinner.Update(msg)
		return m, cmd
	}
	return m, nil
}

func (m SpinnerModel) View() string {
	if m.done {
		if m.err != nil {
			return fmt.Sprintf("  %s %s\n", Error.Render("✘"), m.message)
		}
		return fmt.Sprintf("  %s %s\n", Success.Render("✔"), m.message)
	}
	return fmt.Sprintf("  %s %s\n", m.spinner.View(), m.message)
}

func (m SpinnerModel) Err() error {
	return m.err
}

func RunWithSpinner(message string, action func() error) error {
	model := NewSpinner(message, action)
	p := tea.NewProgram(model)
	finalModel, err := p.Run()
	if err != nil {
		return fmt.Errorf("spinner program error: %w", err)
	}
	if m, ok := finalModel.(SpinnerModel); ok {
		return m.Err()
	}
	return nil
}
