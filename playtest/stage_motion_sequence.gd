extends RefCounted
const Diorama=preload("res://playtest/ascii_diorama_projection.gd")
const STEP_MS:=160
static func sample(motion:Dictionary,now:int)->Dictionary:
	var path:Array=motion.get("path",[])
	var elapsed:int=now-int(motion.started_at_ms)
	if path.size()<2:
		return Diorama.actor_motion_sample(motion.from_world,motion.to_world,elapsed,int(motion.duration_ms),bool(motion.get("continuous",false)))
	var index:=clampi(maxi(0,elapsed)/STEP_MS,0,path.size()-2)
	var result:=Diorama.actor_motion_sample(path[index],path[index+1],elapsed-index*STEP_MS,STEP_MS)
	if elapsed<0:result.step_phase="SETTLE";result.stride_sign=0
	return result
