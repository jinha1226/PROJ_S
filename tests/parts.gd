extends SceneTree
## Monster signature parts: catalog shape, basic parts (PUSH/GUARD) as catalog
## entries, passives, enemy telegraphs, town-only equipping, drops and snapshots.
const Session = preload("res://expedition/session.gd")
const Abilities = preload("res://expedition/abilities.gd")
const Rules = preload("res://expedition/tactic_rules.gd")
const Fixture = preload("res://tests/floor_fixture.gd")
var failures := 0
var checks := 0

func check(ok: bool, reason: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(reason)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	catalog()
	basic_parts()
	print("Parts: %d checks, %d failures" % [checks,failures]); quit(1 if failures else 0)

## Every definition carries the part fields and a rule the schema accepts.
func catalog() -> void:
	for id in Abilities.DEFINITIONS:
		var def: Dictionary = Abilities.DEFINITIONS[id]
		for key in ["species","passive","enemy","allies_hit","tile_wet"]:
			check(def.has(key),"%s has field %s" % [id,key])
		check(def.effect in ["DAMAGE","SHIELD","HEAL","LUNGE","PUSH","GUARD"],"%s effect known" % id)
		check(def.target in ["ENEMY","SELF","ALLY"],"%s target known" % id)
		check(int(def.enemy.get("prep",-1)) >= 0 and int(def.enemy.get("prep",-1)) <= 2,"%s prep in 0..2" % id)
		check(Rules.catalog().has(id),"%s in the derived rule catalog" % id)
		check(Rules.valid(Abilities.default_rule(id)),"%s default rule valid" % id)
	check(not Abilities.DEFINITIONS.has("drop") and not "drop" in Abilities.DEFINITIONS.PUSH,"drop field removed")
	check(Rules.skill("GUARD").targets == ["ALLY"] and Rules.skill("GUARD").conditions == ["ALLY_LETHAL"],"guard advertises ally/lethal")
	check(Rules.skill("PUSH").targets == ["NEAREST","LOWEST_HP"] and "CHARGING" in Rules.skill("PUSH").conditions,"push advertises enemy targets")
	check(Rules.skill("IRON_HIDE").targets == ["SELF"] and Rules.skill("IRON_HIDE").conditions == ["ALWAYS","HP","STATUS","DANGER"],"self skills advertise self conditions")
	check(Rules.skill("NOPE").is_empty(),"unknown skill is empty")
	check(Rules.defaults().is_empty(),"no rules before equipping")
	check(Abilities.default_rule("GUARD").target == "ALLY" and Abilities.default_rule("GUARD").when == "ALLY_LETHAL","guard default rule")
	check(Abilities.default_rule("PUSH").target == "NEAREST" and Abilities.default_rule("PUSH").when == "CHARGING","push default rule")
	check(Abilities.badge("PUSH") == Abilities.DEFINITIONS.PUSH.short and Abilities.badge("ATTACK") == "공격","badges from catalog and basics")

## 밀치기·엄호 run through the catalog path and need a slot.
func basic_parts() -> void:
	var s = Session.new(731,true,true,true,3); s.depart()
	var c := Fixture.arena(s,8)
	var hero: Dictionary = s.party[0]; var ally: Dictionary = s.party[1]
	var foe: Dictionary = s.enemies[0]
	foe.hp = 30; foe.max_hp = 30; foe.role = "MELEE"; foe.alert = true; foe.charging = false; foe.cast_recovery = 0
	foe.pos = c+Vector2i(1,0); ally.pos = c+Vector2i(0,1)
	s.floor_state.observe(s); s.selected = 0
	# Companions keep no actions so their turns cannot disturb the case.
	for actor in s.party: actor.ap = 0
	hero.ap = 3
	check(hero.equipped_abilities == ["",""] and hero.rules.is_empty(),"floor party starts with empty slots and no rules")
	check(not s.act("PUSH",foe.pos),"push needs a slot")
	check(not s.act("GUARD",ally.pos),"guard needs a slot")
	check(not s.Tactics.choose(s,hero).kind in ["PUSH","GUARD"],"tactics offer no unequipped basics")
	hero.equipped_abilities = ["PUSH","GUARD"]
	hero.rules = [Abilities.default_rule("PUSH"),Abilities.default_rule("GUARD")]
	var before: Vector2i = foe.pos
	check(s.act("PUSH",foe.pos) and foe.pos == before+Vector2i(1,0) and hero.ap == 2,"push moves the foe one cell and costs an action")
	check(s.act("GUARD",ally.pos) and hero.guarded and ally.protected_by == hero.id,"guard covers the adjacent ally")
	check(not s.act("GUARD",foe.pos) and not s.act("GUARD",hero.pos),"guard rejects foes and self")
	var legacy = Session.new(731,true,true)
	check(legacy.party[0].equipped_abilities == ["PUSH","GUARD"] and legacy.party[0].rules.size() == 2,"non-floor modes start with the basics equipped")
