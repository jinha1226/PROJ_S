extends RefCounted
## Selected unmodified tiles from crawl/tiles CC0 export, not game source art.
const PATH:="res://assets/dcss-cc0/items/"
const FILES:={
	"WEAPON_SHORT_SWORD":"item__weapon__short_sword1.png",
	"WEAPON_THRUSTING_SWORD":"item__weapon__rapier1.png",
	"WEAPON_HAND_AXE":"item__weapon__hand_axe1.png",
	"WEAPON_MACE":"item__weapon__mace1.png",
	"WEAPON_SPEAR":"item__weapon__spear1.png",
	"WEAPON_BOW":"item__weapon__ranged__shortbow1.png",
	"WEAPON_CROSSBOW":"item__weapon__ranged__arbalest1.png",
	"WEAPON_DCSS_CLUB":"item__weapon__club.png",
	"WEAPON_DCSS_WHIP":"item__weapon__bullwhip.png",
	"WEAPON_DCSS_FLAIL":"item__weapon__flail1.png",
	"WEAPON_DCSS_DAGGER":"item__weapon__dagger.png",
	"WEAPON_DCSS_FALCHION":"item__weapon__falchion1.png",
	"WEAPON_DCSS_LONG_SWORD":"item__weapon__long_sword1.png",
	"WEAPON_DCSS_SCIMITAR":"item__weapon__scimitar1.png",
	"WEAPON_DCSS_WAR_AXE":"UNUSED__weapons__war_axe4.png",
	"WEAPON_DCSS_TRIDENT":"item__weapon__spear2.png",
	"WEAPON_DCSS_STAFF":"item__staff__staff00.png",
	"WEAPON_DCSS_QUARTERSTAFF":"item__weapon__quarterstaff.png",
	"WEAPON_DCSS_ORCBOW":"item__weapon__ranged__longbow1.png",
	"ARMOR_PADDED":"item__armour__robe2.png",
	"ARMOR_LEATHER":"item__armour__leather_armour1.png",
	"ARMOR_CLOTH_ROBE":"item__armour__robe1.png",
	"ARMOR_CHAIN":"item__armour__ring_mail1.png",
	"ARMOR_PLATE":"item__armour__plate1.png",
	"SHIELD_WOOD":"item__armour__shields__buckler1.png",
	"FOOD_RATION":"item__food__bread_ration.png",
	"MAGIC_STONE":"item__misc__misc_crystal.png",
	"ESSENCE_UNSPECIFIED":"item__food__chunk.png",
	"STONE":"item__weapon__ranged__rock.png",
	"TOWN_GOLD":"item__gold__07.png",
	"DROPPED_ITEM":"item__misc__misc_box.png",
	"MATERIAL_UNSPECIFIED":"item__weapon__ranged__rock.png",
	"ACCESSORY_BRASS_CHARM":"item__amulet__face1_gold.png",
	"ACCESSORY_UNSPECIFIED":"item__amulet__face1_gold.png",
	"SCROLL_UNSPECIFIED":"item__scroll__scroll.png",
	"POTION_UNSPECIFIED":"item__potion__ruby.png",
	"MYSTERY_POTION_0":"item__potion__ruby.png",
	"MYSTERY_POTION_1":"item__potion__brilliant_blue.png",
	"MYSTERY_POTION_2":"item__potion__cyan.png",
	"MYSTERY_POTION_3":"item__potion__yellow.png",
	"MYSTERY_POTION_4":"item__potion__magenta.png",
	"MYSTERY_POTION_5":"item__potion__brown.png",
	"MYSTERY_POTION_6":"item__potion__white.png",
	"MYSTERY_POTION_7":"item__potion__black.png",
	"MYSTERY_POTION_8":"item__potion__orange.png",
	"MYSTERY_SCROLL_0":"item__scroll__scroll.png",
	"MYSTERY_SCROLL_1":"item__scroll__scroll-blue.png",
	"MYSTERY_SCROLL_2":"item__scroll__scroll-red.png",
	"MYSTERY_SCROLL_3":"item__scroll__scroll-green.png",
	"MYSTERY_SCROLL_4":"item__scroll__scroll-yellow.png",
	"MYSTERY_SCROLL_5":"item__scroll__scroll-purple.png",
	"MYSTERY_SCROLL_6":"item__scroll__scroll-cyan.png",
	"MYSTERY_SCROLL_7":"item__scroll__scroll-brown.png",
	"MYSTERY_SCROLL_8":"item__scroll__scroll-grey.png",
	"MYSTERY_SCROLL_9":"item__scroll__scroll.png",
	"MYSTERY_SCROLL_10":"item__scroll__scroll-blue.png",
}
static var cache:Dictionary={}
static func texture_for_id(value:String)->Texture2D:
	var key:=value.strip_edges().to_upper()
	if key.begins_with("ESSENCE_") or key.begins_with("ORGAN_") or key.begins_with("FOOD_MONSTER_"):key="ESSENCE_UNSPECIFIED"
	elif key.begins_with("FOOD_"):key="FOOD_RATION"
	elif key.begins_with("MAGIC_STONE"):key="MAGIC_STONE"
	elif key.begins_with("POTION_"):key="POTION_UNSPECIFIED"
	elif key.begins_with("SCROLL_"):key="SCROLL_UNSPECIFIED"
	elif key.begins_with("ACCESSORY_") and not FILES.has(key):key="ACCESSORY_UNSPECIFIED"
	elif key.begins_with("MAT_") or key.begins_with("MATERIAL_"):key="MATERIAL_UNSPECIFIED"
	if not FILES.has(key):
		for base in FILES:
			if str(base).begins_with("WEAPON_") and key.begins_with(str(base)+"_"):key=base;break
	if not FILES.has(key):return null
	var file:String=FILES[key]
	if not cache.has(file):cache[file]=load(PATH+file)
	return cache[file]
