class_name MonthValues
extends RefCounted

const NAMES: PackedStringArray = [
	"January", "February", "March", "April", "May", "June",
	"July", "August", "September", "October", "November", "December",
]

# Days per month (no leap years — 365-day calendar per C2).
const DAYS_PER_MONTH: PackedInt32Array = [
	31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31,
]
