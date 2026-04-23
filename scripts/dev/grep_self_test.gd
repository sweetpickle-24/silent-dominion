extends RefCounted
class_name GrepSelfTest
## §E-grep — ghost-narrator self-test.
##
## Walks every .gd file under res://scripts and res://scenes and
## asserts that no hardcoded "Your factotum" / "Your coordinator"
## / "Your watcher" etc. narrator strings remain. After Phase C,
## every such sender must flow through `OrgRoles.sender_line(...)`
## so the byline names a real OrgMember or a neutral fallback.
##
## Usage from a dev hotkey or a unit test runner:
##     var leaks: Array[Dictionary] = GrepSelfTest.run()
##     for leak in leaks:
##         push_error("%s:%d  %s" % [leak.path, leak.line, leak.text])
##
## Returns an empty array when the codebase is clean.

const SCAN_ROOTS: Array[String] = [
	"res://scripts",
	"res://scenes",
]

# Forbidden literal fragments. Narrator strings only — role tokens
# and neutral fallbacks (which do not begin with "Your ") are fine.
const FORBIDDEN: Array[String] = [
	"\"Your factotum",
	"\"Your archivist",
	"\"Your paymaster",
	"\"Your go-between",
	"\"Your watcher",
	"\"Your secretary",
	"\"Your tutor",
	"\"Your chief of mandates",
	"\"Your counter-intelligence chief",
	"\"Your counter-intelligence",
	"\"Your coordinator",
	"\"Your local coordinator",
	"\"Your predecessor",
	"\"Your correspondent",
	"\"Your man of affairs",
	"\"Your broker",
	"\"Your handler",
	"\"Your roster",
	"\"Your forgery cell",
	"\"Your arson",
	"\"Your intermediary",
	"\"Your closest hand",
]

# Files explicitly allowed to contain narrator strings, because
# they *define* the narrator system or document it.
const WHITELIST_PATHS: Array[String] = [
	"res://scripts/org_roles.gd",
	"res://scripts/dev/grep_self_test.gd",
]


static func run() -> Array:
	var leaks: Array = []
	for root in SCAN_ROOTS:
		_walk(root, leaks)
	return leaks


static func _walk(dir_path: String, leaks: Array) -> void:
	var d: DirAccess = DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	while true:
		var name: String = d.get_next()
		if name.is_empty():
			break
		if name.begins_with("."):
			continue
		var full: String = dir_path.path_join(name)
		if d.current_is_dir():
			_walk(full, leaks)
		elif name.ends_with(".gd"):
			_scan_file(full, leaks)
	d.list_dir_end()


static func _scan_file(path: String, leaks: Array) -> void:
	if WHITELIST_PATHS.has(path):
		return
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var line_no: int = 0
	while not f.eof_reached():
		var line: String = f.get_line()
		line_no += 1
		for needle in FORBIDDEN:
			if line.find(needle) >= 0:
				leaks.append({
					"path":  path,
					"line":  line_no,
					"text":  line.strip_edges(),
					"hit":   needle,
				})
	f.close()
