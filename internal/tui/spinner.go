package tui

import (
	"context"
	"errors"
	"fmt"

	"github.com/charmbracelet/bubbles/spinner"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// ErrInterrupted is returned when the user presses Ctrl+C during a spinner.
var ErrInterrupted = errors.New("interrupted")

type SpinnerModel struct {
	spinner  spinner.Model
	message  string
	done     bool
	canceled bool
	err      error
	action   func() error
	cancel   context.CancelFunc
}

type spinnerDoneMsg struct{ err error }

func NewSpinner(message string, action func() error, cancel context.CancelFunc) SpinnerModel {
	s := spinner.New()
	s.Spinner = spinner.Dot
	s.Style = lipgloss.NewStyle().Foreground(lipgloss.Color("#00D4AA"))
	return SpinnerModel{
		spinner: s,
		message: message,
		action:  action,
		cancel:  cancel,
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
			m.canceled = true
			if m.cancel != nil {
				m.cancel()
			}
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
	if m.canceled {
		return fmt.Sprintf("  %s %s (cancelled)\n", Error.Render("✘"), m.message)
	}
	if m.done {
		if m.err != nil {
			return fmt.Sprintf("  %s %s\n", Error.Render("✘"), m.message)
		}
		return fmt.Sprintf("  %s %s\n", Success.Render("✔"), m.message)
	}
	return fmt.Sprintf("  %s %s\n", m.spinner.View(), m.message)
}

func (m SpinnerModel) Err() error {
	if m.canceled {
		return ErrInterrupted
	}
	return m.err
}

// RunWithSpinner runs action behind a spinner. Returns ErrInterrupted on Ctrl+C.
// The provided context is cancelled when the user presses Ctrl+C, which kills
// any subprocess started with that context.
func RunWithSpinner(ctx context.Context, message string, action func(ctx context.Context) error) error {
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()

	model := NewSpinner(message, func() error {
		return action(ctx)
	}, cancel)
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
