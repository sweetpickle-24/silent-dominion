class_name GameDate
extends Resource
## A calendar date in the Silent Dominion world.
##
## Years are stored as positive integers representing BCE, because the
## whole game sits centuries before year zero. Month names use the Roman
## calendar for flavour (Quintilis/Sextilis, not Iulius/Augustus — those
## renamings happen much later than 500 BCE).

const MONTH_NAMES: Array[String] = [
	"Ianuarius", "Februarius", "Martius", "Aprilis",
	"Maius", "Iunius", "Quintilis", "Sextilis",
	"September", "October", "November", "December",
]

@export var year: int = 500
@export_range(1, 12) var month: int = 1
@export_range(1, 30) var day: int = 1


static func make(p_year: int, p_month: int, p_day: int) -> GameDate:
	var d: GameDate = GameDate.new()
	d.year = p_year
	d.month = p_month
	d.day = p_day
	return d


## The current in-world date, ready for letter stamps. Handles the
## sign-flip between GameClock (negative BCE, positive CE) and GameDate
## (positive BCE, negative CE) so every caller stops recreating the
## bug. Always use this instead of `GameDate.make(GameClock.year, ...)`.
static func today() -> GameDate:
	return GameDate.make(-GameClock.year, GameClock.month, GameClock.day)


func format_long() -> String:
	var idx: int = clampi(month, 1, 12) - 1
	# `year` is stored as positive-BCE (opposite convention from
	# GameClock.year which is negative-BCE, positive-CE). So a
	# positive `year` is BCE, a negative or zero `year` has crossed
	# into the common era.
	if year > 0:
		return "%d %s, %d BCE" % [day, MONTH_NAMES[idx], year]
	return "%d %s, %d CE" % [day, MONTH_NAMES[idx], max(1, -year)]


func format_short() -> String:
	if year > 0:
		return "%02d.%02d.%d BCE" % [day, month, year]
	return "%02d.%02d.%d CE" % [day, month, max(1, -year)]
