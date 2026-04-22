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

enum Speed { PAUSED, DAY, MONTH }

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
	# "1 January 500 BCE"
	var bce_year: int = -year
	var idx: int = clampi(month, 1, MONTHS_PER_YEAR) - 1
	return "%d %s %d BCE" % [day, MONTH_NAMES[idx], bce_year]


## Absolute day index since 1 January of year 0. Used by the Scheduler to
## compare "fire this task at day X" against the current day without
## caring about month/year rollover. Monotonically increasing.
func absolute_day() -> int:
	return absolute_day_of(year, month, day)


static func absolute_day_of(p_year: int, p_month: int, p_day: int) -> int:
	var m: int = clampi(p_month, 1, MONTHS_PER_YEAR)
	var d: int = clampi(p_day, 1, DAYS_PER_MONTH)
	return p_year * DAYS_PER_YEAR + (m - 1) * DAYS_PER_MONTH + (d - 1)


## Convert an absolute-day index back into (year, month, day). Returns a
## Dictionary { "year", "month", "day" }.
static func date_from_absolute(abs_day: int) -> Dictionary:
	var y: int = int(floor(float(abs_day) / float(DAYS_PER_YEAR)))
	var remainder: int = abs_day - y * DAYS_PER_YEAR
	var m: int = int(floor(float(remainder) / float(DAYS_PER_MONTH))) + 1
	var d: int = remainder - (m - 1) * DAYS_PER_MONTH + 1
	return { "year": y, "month": m, "day": d }


static func format_absolute(abs_day: int) -> String:
	var dt: Dictionary = date_from_absolute(abs_day)
	var bce_year: int = -int(dt["year"])
	var idx: int = clampi(int(dt["month"]), 1, MONTHS_PER_YEAR) - 1
	return "%d %s %d BCE" % [int(dt["day"]), MONTH_NAMES[idx], bce_year]


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
