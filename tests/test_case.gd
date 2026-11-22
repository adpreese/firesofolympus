extends RefCounted
## Base class for tests. Methods named test_* are run by run_tests.gd.

var failures: PackedStringArray = []


func eq(actual, expected, msg := "") -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [msg, str(expected), str(actual)])


func ok(cond: bool, msg := "assertion failed") -> void:
	if not cond:
		failures.append(msg)
