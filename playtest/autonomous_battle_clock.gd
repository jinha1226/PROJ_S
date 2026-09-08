extends RefCounted
## Presentation cadence only; canonical turns and command journal remain authoritative.
const INTERVAL := 0.32
var paused := false
var remaining := INTERVAL
func reset()->void:
	paused=false;remaining=INTERVAL
func due(delta:float,engaged:bool,blocked:bool)->bool:
	if not engaged or blocked or paused:
		remaining=INTERVAL
		return false
	remaining-=delta
	if remaining>0:return false
	remaining=INTERVAL
	return true
