extends Node
## Global in-game clock. Autoloaded as `GameClock`.
##
## Tracks a simple BCE calendar (30-day months, 12-month years) starting
## at 1 January 500 BCE. Years are stored negatively so arithmetic works
## naturally: advancing time increments `year`, so -500 becomes -499
## (i.e. 500 BCE → 499 BCE).
##
## The clock runs autonomously once a speed is set. It does not drive the
## simulation directly — systems subscribe to `day_passed`, `month_passed`,
## or `year_passed` and do their own work.

signal day_passed(year: int, month: int, day: int)
signal month_passed(year: int, month: int)
signal year_passed(year: int)
signal speed_changed(speed: int)

enum Speed { PAUSED, DAY, MONTH, YEAR, DECADE }

const DAYS_PER_MONTH: int = 30
const MONTHS_PER_YEAR: int = 12
const DAYS_PER_YEAR: int = DAYS_PER_MONTH * MONTHS_PER_YEAR

const MONTH_NAMES: Array[String] = [
	"January", "February", "March", "April",
	"May", "June", "July", "August",
	"September", "October", "November", "December",
]

# Days of game time that advance per real-time second at each speed.
const SPEED_DAYS_PER_SECOND: Dictionary = {
	Speed.PAUSED: 0.0,
	Speed.DAY:    1.0,
	Speed.MONTH:  float(DAYS_PER_MONTH),                  # 1s = 1 month
	Speed.YEAR:   float(DAYS_PER_YEAR),                   # 1s = 1 year
	Speed.DECADE: float(DAYS_PER_YEAR) * 10.0,            # 1s = 1 decade
}

var year: int = -500
var month: int = 1
var day: int = 1
var speed: Speed = Speed.PAUSED

# Fractional day accumulator. When this passes 1.0 we advance a day.
var _day_accumulator: float = 0.0


func _process(delta: float) -> void:
	if speed == Speed.PAUSED:
		return

	_day_accumulator += delta * SPEED_DAYS_PER_SECOND[speed]

	# At high speeds (decade = 3600 days/sec) many days can pass per frame,
	# so we loop until the accumulator is drained.
	while _day_accumulator >= 1.0:
		_day_accumulator -= 1.0
		_advance_one_day()


# --- Public API ---------------------------------------------------------------

func set_speed(new_speed: Speed) -> void:
	if new_speed == speed:
		return
	speed = new_speed
	# Drop any partial day when the player pauses/changes gears so the next
	# tick starts from a clean boundary; keeps ticks feeling deliberate.
	_day_accumulator = 0.0
	speed_changed.emit(speed)


func format_date() -> String:
	# "January 500 BCE"
	var bce_year: int = -year
	var idx: int = clampi(month, 1, MONTHS_PER_YEAR) - 1
	return "%s %d BCE" % [MONTH_NAMES[idx], bce_year]


func format_date_full() -> String:
	# "1 January 500 BCE"
	var bce_year: int = -year
	var idx: int = clampi(month, 1, MONTHS_PER_YEAR) - 1
	return "%d %s %d BCE" % [day, MONTH_NAMES[idx], bce_year]


# --- Internal -----------------------------------------------------------------

func _advance_one_day() -> void:
	day += 1
	var month_rolled: bool = false
	var year_rolled: bool = false

	if day > DAYS_PER_MONTH:
		day = 1
		month += 1
		month_rolled = true

		if month > MONTHS_PER_YEAR:
			month = 1
			year += 1
			year_rolled = true

	day_passed.emit(year, month, day)
	if month_rolled:
		month_passed.emit(year, month)
	if year_rolled:
		year_passed.emit(year)
