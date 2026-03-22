package tui

var (
	BadgePass = Success.Render("[  OK  ]")
	BadgeFail = Error.Render("[ FAIL ]")
	BadgeWarn = Warning.Render("[ WARN ]")
	BadgeSkip = Muted.Render("[ SKIP ]")
)

func Badge(result string) string {
	switch result {
	case "pass":
		return BadgePass
	case "fail":
		return BadgeFail
	case "warn":
		return BadgeWarn
	case "skip":
		return BadgeSkip
	default:
		return BadgeSkip
	}
}
