class_name PublicPositionValues
extends RefCounted

# Per actors-and-chain.md "Axis 1 — Public position", 5 tiers.
const INVISIBLE: StringName = &"invisible"
const MINOR: StringName = &"minor"
const NOTABLE: StringName = &"notable"
const HIGH: StringName = &"high"
const MAXIMAL: StringName = &"maximal"

# Exposure cost multiplier per tier — calibration values, T2-1 revises.
const EXPOSURE_MULTIPLIER: Dictionary = {
	&"invisible": 0.5,
	&"minor": 1.0,
	&"notable": 1.5,
	&"high": 3.0,
	&"maximal": 8.0,
}
