extends SceneTree
const ButtonSkin=preload("res://playtest/stage_button_skin.gd")
const Touch=preload("res://playtest/stage_touch_button.gd")
var failures:Array=[]
var clicks:=0
var holds:=0
func check(ok:bool,label:String):
	if not ok:failures.append(label);printerr("FAIL ",label)
func _init():call_deferred("run")
func touch(b,down:bool,cancelled:bool=false):
	var e:=InputEventScreenTouch.new();e.index=0;e.position=Vector2(20,20)
	e.pressed=down;e.canceled=cancelled;b._gui_input(e)
func run():
	var b=Touch.new();b.size=Vector2(88,84);root.add_child(b)
	b.pressed.connect(func():clicks+=1);b.held.connect(func():holds+=1)
	b.set_skin_accent(false)
	var normal=b.get_theme_stylebox("normal")
	check(normal is StyleBoxTexture,"real textured 9-slice")
	check(normal.texture.get_size()==Vector2(64,64),"shared 64px runtime texture")
	check(normal.get_texture_margin(SIDE_LEFT)==8,"fixed 8px corners")
	check(normal==ButtonSkin.box("normal"),"style resources reused")
	b.set_skin_accent(true)
	check(b.get_theme_stylebox("normal")==ButtonSkin.box("selected"),"cyan selection")
	touch(b,true)
	check(b.get_theme_stylebox("normal")==ButtonSkin.box("pressed"),"finger down feedback")
	touch(b,false)
	check(clicks==1 and b.get_theme_stylebox("normal")==ButtonSkin.box("selected"),"release restores selection and emits once")
	touch(b,true);touch(b,false,true);check(clicks==1,"cancel does not activate")
	touch(b,true)
	var drag:=InputEventScreenDrag.new();drag.index=0;drag.position=Vector2(50,20);b._gui_input(drag)
	check(b.get_theme_stylebox("normal")==ButtonSkin.box("selected"),"drag cancels pressed feedback")
	touch(b,false);check(clicks==1,"drag does not activate")
	b.disabled=true;touch(b,true);touch(b,false);check(clicks==1,"disabled does not activate")
	check(b.get_theme_stylebox("disabled")==ButtonSkin.box("disabled"),"disabled dim frame")
	b.disabled=false;touch(b,true);await create_timer(0.6).timeout;touch(b,false)
	check(holds==1 and clicks==1,"long press remains separate from activation")
	b.queue_free();await process_frame
	print("STAGE_BUTTON_SKIN ","PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)
