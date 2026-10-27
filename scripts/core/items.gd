class_name Items
## Static item database: weapons, consumables, ammo, rarities.

const RARITY_NAMES := ["Обычное", "Необычное", "Редкое", "Эпическое", "Легендарное"]
const RARITY_COLORS := [
	Color(0.72, 0.74, 0.78), Color(0.35, 0.85, 0.3), Color(0.25, 0.6, 1.0),
	Color(0.72, 0.35, 1.0), Color(1.0, 0.68, 0.15),
]
const RARITY_DMG := [1.0, 1.05, 1.1, 1.16, 1.22]
const RARITY_RELOAD := [1.0, 0.95, 0.9, 0.85, 0.8]

const AMMO_NAMES := {"light": "Лёгкие патроны", "medium": "Средние патроны", "heavy": "Тяжёлые патроны", "shells": "Дробь"}
const AMMO_COLORS := {"light": Color(0.5, 0.85, 1.0), "medium": Color(0.6, 1.0, 0.5), "heavy": Color(1.0, 0.45, 0.4), "shells": Color(1.0, 0.85, 0.3)}

const WEAPONS := {
	"ar": {
		"name": "Штурмовая винтовка", "ammo": "medium", "damage": 30.0, "head": 1.5,
		"rate": 5.5, "mag": 30, "reload": 2.3, "spread_hip": 2.8, "spread_ads": 0.6,
		"bloom": 0.45, "pellets": 1, "falloff_start": 50.0, "falloff_end": 150.0, "falloff_min": 0.7,
		"auto": true, "zoom": 50.0, "range": 300.0, "rarity_min": 0,
	},
	"smg": {
		"name": "Пистолет-пулемёт", "ammo": "light", "damage": 17.0, "head": 1.5,
		"rate": 12.0, "mag": 30, "reload": 2.0, "spread_hip": 3.2, "spread_ads": 1.8,
		"bloom": 0.25, "pellets": 1, "falloff_start": 20.0, "falloff_end": 60.0, "falloff_min": 0.55,
		"auto": true, "zoom": 62.0, "range": 160.0, "rarity_min": 0,
	},
	"pump": {
		"name": "Помповый дробовик", "ammo": "shells", "damage": 9.5, "head": 2.0,
		"rate": 1.1, "mag": 5, "reload": 4.4, "spread_hip": 5.5, "spread_ads": 4.2,
		"bloom": 0.0, "pellets": 10, "falloff_start": 6.0, "falloff_end": 24.0, "falloff_min": 0.15,
		"auto": false, "zoom": 64.0, "range": 45.0, "rarity_min": 0,
	},
	"sniper": {
		"name": "Снайперская винтовка", "ammo": "heavy", "damage": 105.0, "head": 2.5,
		"rate": 0.33, "mag": 1, "reload": 2.6, "spread_hip": 7.0, "spread_ads": 0.0,
		"bloom": 0.0, "pellets": 1, "falloff_start": 400.0, "falloff_end": 500.0, "falloff_min": 1.0,
		"auto": false, "zoom": 16.0, "range": 600.0, "rarity_min": 2,
	},
	"pistol": {
		"name": "Пистолет", "ammo": "light", "damage": 24.0, "head": 2.0,
		"rate": 6.5, "mag": 16, "reload": 1.4, "spread_hip": 2.2, "spread_ads": 0.9,
		"bloom": 0.6, "pellets": 1, "falloff_start": 25.0, "falloff_end": 70.0, "falloff_min": 0.6,
		"auto": false, "zoom": 62.0, "range": 150.0, "rarity_min": 0,
	},
}

const CONSUMABLES := {
	"bandage": {"name": "Бинты", "time": 3.5, "hp": 15, "hp_cap": 75, "shield": 0, "shield_cap": 0, "stack": 15, "per_pickup": 5},
	"medkit": {"name": "Аптечка", "time": 9.0, "hp": 100, "hp_cap": 100, "shield": 0, "shield_cap": 0, "stack": 3, "per_pickup": 1},
	"mini_shield": {"name": "Малый щит", "time": 2.0, "hp": 0, "hp_cap": 0, "shield": 25, "shield_cap": 50, "stack": 6, "per_pickup": 3},
	"big_shield": {"name": "Большой щит", "time": 5.0, "hp": 0, "hp_cap": 0, "shield": 50, "shield_cap": 100, "stack": 3, "per_pickup": 1},
}

const CONSUMABLE_COLORS := {
	"bandage": Color(0.95, 0.95, 0.95), "medkit": Color(1.0, 0.3, 0.3),
	"mini_shield": Color(0.3, 0.75, 1.0), "big_shield": Color(0.2, 0.45, 1.0),
}

const MAT_NAMES := {"wood": "Дерево", "stone": "Камень", "metal": "Металл"}
const MAT_MAX := 999
const BUILD_COST := 10


static func weapon_item(id: String, rarity: int) -> Dictionary:
	var w: Dictionary = WEAPONS[id]
	return {"kind": "weapon", "id": id, "rarity": maxi(rarity, int(w["rarity_min"])), "clip": int(w["mag"])}


static func consumable_item(id: String, count := -1) -> Dictionary:
	var c: Dictionary = CONSUMABLES[id]
	return {"kind": "consumable", "id": id, "count": int(c["per_pickup"]) if count < 0 else count}


static func display_name(item: Dictionary) -> String:
	match item.get("kind", ""):
		"weapon":
			return String(WEAPONS[item["id"]]["name"])
		"consumable":
			var c: Dictionary = CONSUMABLES[item["id"]]
			return "%s ×%d" % [c["name"], item["count"]]
		"ammo":
			return "%s ×%d" % [AMMO_NAMES[item["id"]], item["count"]]
		"mat":
			return "%s ×%d" % [MAT_NAMES[item["id"]], item["count"]]
	return "?"


static func item_color(item: Dictionary) -> Color:
	match item.get("kind", ""):
		"weapon":
			return RARITY_COLORS[int(item["rarity"])]
		"consumable":
			return CONSUMABLE_COLORS[item["id"]]
		"ammo":
			return AMMO_COLORS[item["id"]]
		"mat":
			return Color(0.85, 0.7, 0.5) if item["id"] == "wood" else (Color(0.7, 0.7, 0.72) if item["id"] == "stone" else Color(0.6, 0.75, 0.85))
	return Color.WHITE


## Weapon desirability used by bots and auto-swap logic.
static func weapon_score(item: Dictionary) -> float:
	if item.is_empty() or item.get("kind", "") != "weapon":
		return 0.0
	var base := {"ar": 10.0, "pump": 10.5, "smg": 8.0, "sniper": 7.0, "pistol": 5.0}
	return float(base.get(item["id"], 5.0)) + float(item["rarity"]) * 1.6


static func random_rarity(rng: RandomNumberGenerator, bonus := 0) -> int:
	var r := rng.randf() * 100.0
	var rarity := 0
	if r > 97.0: rarity = 4
	elif r > 88.0: rarity = 3
	elif r > 68.0: rarity = 2
	elif r > 40.0: rarity = 1
	return mini(4, rarity + bonus)


static func random_weapon(rng: RandomNumberGenerator, bonus := 0) -> Dictionary:
	var ids := ["ar", "ar", "ar", "smg", "smg", "pump", "pump", "pump", "pistol", "pistol", "sniper"]
	return weapon_item(ids[rng.randi() % ids.size()], random_rarity(rng, bonus))


static func random_consumable(rng: RandomNumberGenerator) -> Dictionary:
	var ids := ["bandage", "bandage", "medkit", "mini_shield", "mini_shield", "mini_shield", "big_shield"]
	return consumable_item(ids[rng.randi() % ids.size()])


static func ammo_item(kind: String, count := -1) -> Dictionary:
	var amounts := {"light": 30, "medium": 30, "heavy": 6, "shells": 8}
	return {"kind": "ammo", "id": kind, "count": int(amounts[kind]) if count < 0 else count}
