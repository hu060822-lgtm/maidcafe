class_name PortraitRecipe
extends RefCounted
## Options and defaults for the Portrait Maker. A recipe is a plain
## Dictionary saved as godot/art/characters/<id>/maker.json.

const DEFAULT_OUTFIT := {"style": "classic", "main": "#2e2a3a", "accent": "#ffffff", "ribbon": "#e0607a"}

const DEFAULT := {
	"status": "proposal",
	"skin": "#ffe9df",
	"hair_color": "#8a5a3c",
	"hair_back": "long",
	"bangs": "straight",
	"side_locks": true,
	"ahoge": false,
	"eye_color": "#7a4a2a",
	"eye_shape": "round",
	"scale": 1.0,
	"accessories": ["headdress"],
	"outfits": {
		"maid": {"style": "classic", "main": "#2e2a3a", "accent": "#ffffff", "ribbon": "#e0607a"},
		"casual": {"style": "cardigan", "main": "#f0c8a0", "accent": "#7a8ab0", "ribbon": "#e0607a"},
	},
}

## id -> label shown in the workshop
const HAIR_BACK := {"long": "長髮", "bob": "鮑伯頭", "short": "短髮", "ponytail": "馬尾", "twin-tails": "雙馬尾", "bun": "丸子頭", "braid": "側辮"}
const BANGS := {"straight": "齊瀏海", "parted": "中分", "side": "斜瀏海", "wispy": "空氣瀏海"}
const EYES := {"round": "圓眼", "gentle": "下垂眼", "sharp": "上挑眼", "sleepy": "半睜眼"}
const ACCESSORIES := {"headdress": "女僕頭飾", "ribbon": "蝴蝶結", "hairclip": "髮夾", "flower": "花飾", "glasses": "眼鏡"}
const OUTFIT_STYLES := {
	"classic": "經典女僕裝（長袖）", "frill": "荷葉邊女僕裝（短袖）", "long": "素雅女僕裝",
	"cardigan": "針織外套", "hoodie": "帽 T", "blouse": "襯衫與高腰裙", "sailor": "水手服", "sporty": "運動外套",
}

const EYE_SHAPES := {
	"round": {"rx": 42.0, "ry": 48.0, "tilt": 0.0},
	"gentle": {"rx": 43.0, "ry": 43.0, "tilt": 9.0},
	"sharp": {"rx": 46.0, "ry": 37.0, "tilt": -11.0},
	"sleepy": {"rx": 43.0, "ry": 31.0, "tilt": 4.0},
}

## How each art_spec expression id is drawn.
const EXPRESSIONS := {
	"neutral": {"open": 1.0, "brow_in": 0.0, "brow_out": 0.0, "mouth": "neutral", "blush": 0.25},
	"smile": {"open": 0.94, "brow_in": -2.0, "brow_out": 0.0, "mouth": "smile", "blush": 0.4},
	"laugh": {"open": 0.0, "mode": "closed_happy", "brow_in": -5.0, "brow_out": -2.0, "mouth": "laugh", "blush": 0.5},
	"surprised": {"open": 1.14, "iris": 0.8, "brow_in": -13.0, "brow_out": -11.0, "mouth": "o", "blush": 0.2},
	"embarrassed": {"open": 0.86, "look_x": 7.0, "brow_in": -7.0, "brow_out": 5.0, "mouth": "wavy", "blush": 1.0},
	"sad": {"open": 0.8, "look_y": 3.0, "brow_in": -11.0, "brow_out": 7.0, "mouth": "sad", "blush": 0.15, "extras": ["tears"]},
	"angry": {"open": 0.8, "brow_in": 11.0, "brow_out": -8.0, "mouth": "angry", "blush": 0.3, "extras": ["anger"]},
	"tired": {"open": 0.52, "look_y": 3.0, "brow_in": -4.0, "brow_out": 6.0, "mouth": "tired", "blush": 0.1, "extras": ["sweat"]},
	"troubled": {"open": 0.9, "brow_in": -9.0, "brow_out": 6.0, "mouth": "wavy", "blush": 0.3, "extras": ["sweat"]},
	"thinking": {"open": 0.95, "look_y": -5.0, "look_x": 5.0, "brow_in": -3.0, "brow_out": -6.0, "mouth": "flat", "blush": 0.2},
	"serious": {"open": 0.86, "brow_in": 6.0, "brow_out": -3.0, "mouth": "flat", "blush": 0.1},
	"apologetic": {"open": 0.0, "mode": "closed_down", "brow_in": -12.0, "brow_out": 6.0, "mouth": "sad", "blush": 0.3, "extras": ["sweat"]},
}

## Region (design-space rect) that changes between expressions; used to cut face patches.
const FACE_RECT := Rect2(340, 190, 372, 316)


static func normalized(r: Dictionary) -> Dictionary:
	var out: Dictionary = DEFAULT.duplicate(true)
	for k in r:
		if k == "outfits" and typeof(r[k]) == TYPE_DICTIONARY:
			for o in r[k]:
				var base: Dictionary = out["outfits"].get(o, DEFAULT_OUTFIT).duplicate(true)
				for f in r[k][o]:
					base[f] = r[k][o][f]
				out["outfits"][o] = base
		else:
			out[k] = r[k]
	out["scale"] = clampf(float(out["scale"]), 0.8, 1.1)
	return out


## The face-patch rectangle in canvas pixels for a recipe (accounts for its scale).
static func face_rect(r: Dictionary) -> Rect2i:
	var sc := float(normalized(r)["scale"])
	var p := Vector2(PortraitPainter.CX + (FACE_RECT.position.x - PortraitPainter.CX) * sc, PortraitPainter.H + (FACE_RECT.position.y - PortraitPainter.H) * sc)
	return Rect2i(p.floor(), (FACE_RECT.size * sc).ceil())
