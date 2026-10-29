class_name SimEventLog
extends RefCounted

## Small ring buffer of causal events. Phase 0 writes deaths and first-time
## notices; Phase 1 grows this into the full causal log the inspector and the
## player read. Entries record the same facts memory will record, so a later
## log line can never claim a cause the simulation does not have.

const CAPACITY := 256

var entries: Array = []
var total_written := 0


func push(at_time: float, kind: String, text: String, creature_id: int = -1) -> void:
	var entry := {
		"time": at_time,
		"kind": kind,
		"text": text,
		"creature": creature_id,
	}
	entries.append(entry)
	if entries.size() > CAPACITY:
		entries.remove_at(0)
	total_written += 1


func recent(n: int) -> Array:
	var start := maxi(0, entries.size() - n)
	var out: Array = []
	for i in range(start, entries.size()):
		out.append(entries[i])
	return out


func last_of_kind(kind: String) -> Dictionary:
	for i in range(entries.size() - 1, -1, -1):
		if String(entries[i]["kind"]) == kind:
			return entries[i]
	return {}
