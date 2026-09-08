extends RefCounted
## Presentation cadence only; canonical turns and command journal remain authoritative.
const INTERVAL := 0.32
var paused := false
var remaining := INTERVAL
const WORLD_UNITS_PER_SECOND:=200.0
var cursor:=-1.0
func reset()->void:
	paused=false;remaining=INTERVAL;cursor=-1.0

func advance(delta:float,world_time:int,blocked:bool)->float:
	if cursor<0:cursor=float(world_time)
	cursor=maxf(cursor,float(world_time))
	if not paused and not blocked:
		# Returning from a suspended browser must not instantly resolve a battle.
		cursor+=clampf(delta,0.0,0.1)*WORLD_UNITS_PER_SECOND
	return cursor
func due(delta:float,engaged:bool,blocked:bool)->bool:
	if not engaged or blocked or paused:
		return false
	remaining-=delta
	if remaining>0:return false
	remaining=INTERVAL
	return true
