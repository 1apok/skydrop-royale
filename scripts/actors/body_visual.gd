class_name BodyVisual
extends Node3D
## Procedural stylized character model with code-driven animation.

const SKINS := [Color(0.98, 0.82, 0.68), Color(0.88, 0.67, 0.5), Color(0.7, 0.5, 0.36), Color(0.5, 0.34, 0.24), Color(0.95, 0.76, 0.62)]
const OUTFITS := [
	[Color(0.9, 0.3, 0.25), Color(0.2, 0.22, 0.3)],
	[Color(0.2, 0.55, 0.95), Color(0.85, 0.85, 0.88)],
	[Color(0.25, 0.7, 0.35), Color(0.35, 0.28, 0.2)],
	[Color(0.95, 0.75, 0.2), Color(0.18, 0.18, 0.2)],
	[Color(0.6, 0.3, 0.85), Color(0.25, 0.25, 0.35)],
	[Color(0.95, 0.5, 0.15), Color(0.25, 0.3, 0.25)],
	[Color(0.15, 0.15, 0.17), Color(0.75, 0.15, 0.2)],
	[Color(0.92, 0.92, 0.95), Color(0.3, 0.45, 0.7)],
	[Color(0.95, 0.45, 0.65), Color(0.2, 0.2, 0.28)],
	[Color(0.1, 0.6, 0.6), Color(0.9, 0.85, 0.7)],
	[Color(0.45, 0.5, 0.3), Color(0.38, 0.32, 0.22)],
]
const HAIR := [Color(0.12, 0.09, 0.07), Color(0.45, 0.28, 0.14), Color(0.92, 0.8, 0.45), Color(0.75, 0.25, 0.12), Color(0.3, 0.75, 0.95), Color(0.95, 0.4, 0.75), Color(0.9, 0.9, 0.92)]

var hips: Node3D
var torso: Node3D
var head: Node3D
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var hand_r: Node3D
var weapon_node: MeshInstance3D
var pickaxe_node: MeshInstance3D
var glider_node: MeshInstance3D
var accent := Color.WHITE
var _phase := 0.0
var _swing := 0.0
var _recoil := 0.0
var _mat: StandardMaterial3D


func build(seed_value: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	var skin: Color = SKINS[r.randi() % SKINS.size()]
	var outfit: Array = OUTFITS[r.randi() % OUTFITS.size()]
	var top: Color = outfit[0]
	var bottom: Color = outfit[1]
	var hair: Color = HAIR[r.randi() % HAIR.size()]
	var shoe := Color(0.15, 0.15, 0.17) if r.randf() < 0.6 else Color(0.95, 0.95, 0.95)
	accent = top
	_mat = MeshKit.material_vc(0.75)

	hips = Node3D.new()
	hips.position = Vector3(0, 0.92, 0)
	add_child(hips)
	# Torso + backpack.
	torso = Node3D.new()
	hips.add_child(torso)
	var st := MeshKit.begin()
	MeshKit.box(st, Vector3(0, 0.08, 0), Vector3(0.42, 0.22, 0.26), bottom)
	MeshKit.box(st, Vector3(0, 0.36, 0), Vector3(0.48, 0.42, 0.3), top)
	MeshKit.box(st, Vector3(0, 0.36, 0.17), Vector3(0.36, 0.38, 0.06), top.darkened(0.15))
	MeshKit.box(st, Vector3(0, 0.38, 0.25), Vector3(0.32, 0.36, 0.16), top.darkened(0.35))
	MeshKit.box(st, Vector3(0, 0.2, 0.0), Vector3(0.44, 0.05, 0.28), Color(0.2, 0.18, 0.15))
	_add_mesh(torso, st)
	# Head.
	head = Node3D.new()
	head.position = Vector3(0, 0.62, 0)
	torso.add_child(head)
	st = MeshKit.begin()
	MeshKit.box(st, Vector3(0, 0.05, 0), Vector3(0.12, 0.1, 0.12), skin.darkened(0.08))
	MeshKit.blob(st, Vector3(0, 0.22, 0), Vector3(0.17, 0.19, 0.17), skin, r, 0.0, 6, 10, 0.0)
	MeshKit.box(st, Vector3(-0.065, 0.24, -0.155), Vector3(0.04, 0.05, 0.02), Color(0.08, 0.08, 0.1))
	MeshKit.box(st, Vector3(0.065, 0.24, -0.155), Vector3(0.04, 0.05, 0.02), Color(0.08, 0.08, 0.1))
	MeshKit.box(st, Vector3(0, 0.15, -0.16), Vector3(0.07, 0.015, 0.01), skin.darkened(0.35))
	match r.randi() % 5:
		0: # cap
			MeshKit.blob(st, Vector3(0, 0.3, 0.0), Vector3(0.18, 0.12, 0.18), top, r, 0.0, 4, 10, 0.0)
			MeshKit.box(st, Vector3(0, 0.32, -0.18), Vector3(0.26, 0.03, 0.14), top.darkened(0.2))
		1: # helmet
			MeshKit.blob(st, Vector3(0, 0.27, 0.0), Vector3(0.2, 0.17, 0.2), Color(0.3, 0.33, 0.28), r, 0.0, 5, 10, 0.0)
			MeshKit.box(st, Vector3(0, 0.25, -0.17), Vector3(0.26, 0.06, 0.04), Color(0.2, 0.7, 0.9))
		2: # spiky hair
			MeshKit.blob(st, Vector3(0, 0.3, 0.02), Vector3(0.18, 0.12, 0.18), hair, r, 0.35, 4, 9, 0.05)
		3: # beanie
			MeshKit.blob(st, Vector3(0, 0.31, 0.0), Vector3(0.185, 0.13, 0.185), bottom.lightened(0.3), r, 0.0, 4, 10, 0.0)
			MeshKit.blob(st, Vector3(0, 0.45, 0.0), Vector3(0.05, 0.05, 0.05), Color.WHITE, r, 0.0, 3, 6, 0.0)
		_: # long hair
			MeshKit.blob(st, Vector3(0, 0.27, 0.04), Vector3(0.19, 0.17, 0.2), hair, r, 0.08, 5, 10, 0.03)
			MeshKit.box(st, Vector3(0, 0.12, 0.13), Vector3(0.3, 0.26, 0.08), hair)
	_add_mesh(head, st)
	# Arms.
	arm_l = _limb(torso, Vector3(-0.31, 0.52, 0), 0.6, 0.075, top, skin)
	arm_r = _limb(torso, Vector3(0.31, 0.52, 0), 0.6, 0.075, top, skin)
	hand_r = Node3D.new()
	hand_r.position = Vector3(0, -0.6, 0)
	arm_r.add_child(hand_r)
	# Legs.
	leg_l = _limb(hips, Vector3(-0.12, 0.0, 0), 0.9, 0.095, bottom, shoe, true)
	leg_r = _limb(hips, Vector3(0.12, 0.0, 0), 0.9, 0.095, bottom, shoe, true)
	# Weapon and pickaxe holders.
	weapon_node = MeshInstance3D.new()
	weapon_node.material_override = Models.vc_material()
	weapon_node.rotation = Vector3(-PI * 0.5, 0, 0)
	weapon_node.position = Vector3(0, -0.02, 0)
	hand_r.add_child(weapon_node)
	pickaxe_node = MeshInstance3D.new()
	var pst := MeshKit.begin()
	MeshKit.box(pst, Vector3(0, 0, -0.35), Vector3(0.05, 0.05, 0.9), Color(0.35, 0.25, 0.18))
	MeshKit.box(pst, Vector3(0, 0.12, -0.78), Vector3(0.07, 0.38, 0.12), accent.lightened(0.2))
	MeshKit.box(pst, Vector3(0, -0.06, -0.78), Vector3(0.05, 0.14, 0.09), Color(0.7, 0.72, 0.75))
	pickaxe_node.mesh = MeshKit.finish(pst)
	pickaxe_node.material_override = Models.vc_material()
	pickaxe_node.rotation = Vector3(-PI * 0.5, 0, 0)
	hand_r.add_child(pickaxe_node)
	glider_node = MeshInstance3D.new()
	glider_node.mesh = Models.glider_mesh(accent)
	glider_node.material_override = _mat
	glider_node.position = Vector3(0, 3.4, 0)
	glider_node.visible = false
	add_child(glider_node)


func _limb(parent: Node3D, pos: Vector3, length: float, radius: float, col: Color, end_col: Color, is_leg := false) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pos
	parent.add_child(pivot)
	var st := MeshKit.begin()
	MeshKit.box(st, Vector3(0, -length * 0.3, 0), Vector3(radius * 2.2, length * 0.6, radius * 2.2), col)
	MeshKit.box(st, Vector3(0, -length * 0.78, 0), Vector3(radius * 1.9, length * 0.4, radius * 1.9), col.darkened(0.08) if is_leg else end_col)
	if is_leg:
		MeshKit.box(st, Vector3(0, -length + 0.05, -0.05), Vector3(radius * 2.3, 0.1, radius * 3.2), end_col)
	else:
		MeshKit.box(st, Vector3(0, -length + 0.02, 0), Vector3(radius * 1.8, 0.1, radius * 1.8), end_col)
	_add_mesh(pivot, st)
	return pivot


func _add_mesh(parent: Node3D, st: SurfaceTool) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.finish(st)
	mi.material_override = _mat
	mi.visibility_range_end = 300.0
	parent.add_child(mi)


func set_weapon(item: Dictionary) -> void:
	if item.is_empty():
		weapon_node.visible = false
		pickaxe_node.visible = true
	elif item.get("kind", "") == "weapon":
		weapon_node.mesh = Models.weapon_mesh(item["id"], int(item["rarity"]))
		weapon_node.visible = true
		pickaxe_node.visible = false
	else:
		weapon_node.mesh = Models.consumable_mesh(item["id"])
		weapon_node.visible = true
		pickaxe_node.visible = false


func swing() -> void:
	_swing = 1.0


func recoil(amount := 1.0) -> void:
	_recoil = minf(_recoil + amount, 1.5)


## state: "ground", "air", "freefall", "glide", "build", "heal"
func animate(delta: float, state: String, speed: float, pitch: float, holding_gun: bool, crouched: bool) -> void:
	_phase += delta * (4.0 + speed * 1.6)
	_swing = maxf(0.0, _swing - delta * 3.5)
	_recoil = maxf(0.0, _recoil - delta * 8.0)
	glider_node.visible = state == "glide"
	var k := clampf(delta * 14.0, 0.0, 1.0)
	var target_hips_y := 0.92
	var body_pitch := 0.0
	var ll := 0.0
	var lr := 0.0
	var al := Vector3.ZERO
	var ar := Vector3.ZERO
	match state:
		"freefall":
			body_pitch = -1.2
			ll = 0.35
			lr = 0.15
			al = Vector3(0.2, 0, -1.3)
			ar = Vector3(0.2, 0, 1.3)
		"glide":
			body_pitch = -0.1
			ll = 0.2 + sin(_phase * 0.5) * 0.1
			lr = 0.1 - sin(_phase * 0.5) * 0.1
			al = Vector3(0, 0, -2.6)
			ar = Vector3(0, 0, 2.6)
		"air":
			ll = 0.5
			lr = -0.2
			al = Vector3(-0.4, 0, -0.5)
			ar = Vector3(-0.4, 0, 0.5)
		_:
			var amp := clampf(speed / 6.0, 0.0, 1.2) * 0.75
			ll = sin(_phase) * amp
			lr = -sin(_phase) * amp
			al = Vector3(-sin(_phase) * amp * 0.8, 0, -0.08)
			ar = Vector3(sin(_phase) * amp * 0.8, 0, 0.08)
			target_hips_y = 0.92 + absf(cos(_phase)) * amp * 0.05
			if crouched:
				target_hips_y = 0.62
				ll = -0.9 + ll * 0.3
				lr = -0.9 + lr * 0.3
				body_pitch = -0.25
	if holding_gun and state in ["ground", "air", "build"]:
		ar = Vector3(-PI * 0.5 + pitch + _recoil * 0.15, -0.05, 0.0)
		al = Vector3(-PI * 0.5 + pitch + 0.05, 0.55, 0.0)
	elif state == "heal":
		ar = Vector3(-1.2, 0, 0.3)
		al = Vector3(-1.1, 0, -0.3)
	elif _swing > 0.0 and state in ["ground", "air"]:
		var s := sin((1.0 - _swing) * PI)
		ar = Vector3(-2.4 + s * 2.2, 0, 0.1)
	if crouched and state == "ground":
		pass
	hips.position.y = lerpf(hips.position.y, target_hips_y, k)
	hips.rotation.x = lerp_angle(hips.rotation.x, body_pitch, k)
	torso.rotation.x = lerp_angle(torso.rotation.x, (pitch * 0.3 if holding_gun else 0.0), k)
	leg_l.rotation.x = lerp_angle(leg_l.rotation.x, ll, k)
	leg_r.rotation.x = lerp_angle(leg_r.rotation.x, lr, k)
	arm_l.rotation = Vector3(lerp_angle(arm_l.rotation.x, al.x, k), lerp_angle(arm_l.rotation.y, al.y, k), lerp_angle(arm_l.rotation.z, al.z, k))
	arm_r.rotation = Vector3(lerp_angle(arm_r.rotation.x, ar.x, k), lerp_angle(arm_r.rotation.y, ar.y, k), lerp_angle(arm_r.rotation.z, ar.z, k))
	head.rotation.x = lerp_angle(head.rotation.x, clampf(pitch * 0.5, -0.5, 0.5), k)
