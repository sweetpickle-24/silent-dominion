class_name StalenessValues
extends RefCounted

const FRESH: StringName = &"fresh"
const AGING: StringName = &"aging"
const STALE: StringName = &"stale"

const FRESH_THRESHOLD_DAYS: int = 1825    # 5 years
const STALE_THRESHOLD_DAYS: int = 18250   # 50 years per playability-resolutions §35.11
