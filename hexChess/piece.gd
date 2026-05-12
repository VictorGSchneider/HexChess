# piece.gd
# Sistema de pecas do HexChess - Godot 4.x

class_name Piece
extends Node2D

enum PieceType {
	PAWN, ROOK, KNIGHT, BISHOP, QUEEN, KING,
	ARCHBISHOP, CHANCELLOR,
	SENTINEL, SPY, PORTAL,
}

enum PieceColor { WHITE, BLACK }

@export var type: PieceType = PieceType.PAWN:
	set(value):
		type = value
		_refresh_visual()
@export var color: PieceColor = PieceColor.WHITE:
	set(value):
		color = value
		_refresh_visual()

@onready var sprite: Sprite2D = $Sprite

## Escala aplicada aos sprites (PNGs sao 500x500, queremos ~65px num hex de raio 40)
@export var sprite_scale: float = 0.13

var coord: Vector2i = Vector2i.ZERO
var board: Node2D = null
var has_moved: bool = false
var is_revealed: bool = false           # Espiao
var portal_pair_coord: Vector2i = Vector2i(-999, -999)  # Portal
var is_blocking: bool = false           # Sentinela

# Texturas das pecas. Use null quando o sprite ainda nao existe — usamos
# fallback com modulate quando faltar a versao preta da peca.
const TEXTURES_WHITE = {
	PieceType.PAWN:   preload("res://pieces/chess-pawn-white.png"),
	PieceType.ROOK:   preload("res://pieces/chess-rook-white.png"),
	PieceType.KNIGHT: preload("res://pieces/chess-knight-white.png"),
	PieceType.BISHOP: preload("res://pieces/chess-bishop-white.png"),
	PieceType.QUEEN:  preload("res://pieces/chess-queen-white.png"),
	PieceType.KING:   preload("res://pieces/chess-king-white.png"),
}
const TEXTURES_BLACK = {
	PieceType.PAWN:   preload("res://pieces/chess-pawn-black.png"),
	PieceType.ROOK:   preload("res://pieces/chess-rook-black.png"),
	PieceType.KNIGHT: preload("res://pieces/chess-knight-black.png"),
	# chess-bishop-black.png ainda nao foi adicionado — fallback para o branco
	PieceType.BISHOP: preload("res://pieces/chess-bishop-white.png"),
	PieceType.QUEEN:  preload("res://pieces/chess-queen-black.png"),
	PieceType.KING:   preload("res://pieces/chess-king-black.png"),
}

func _ready():
	_refresh_visual()

func _refresh_visual():
	if sprite == null:
		return
	var src = TEXTURES_WHITE if color == PieceColor.WHITE else TEXTURES_BLACK
	var tex = src.get(type, null)
	sprite.texture = tex
	sprite.visible = tex != null
	sprite.scale = Vector2(sprite_scale, sprite_scale)
	# Pretas sem sprite proprio (atualmente: bispo) entram em fallback escuro
	var is_black_fallback = color == PieceColor.BLACK and type == PieceType.BISHOP
	sprite.modulate = Color(0.15, 0.13, 0.12) if is_black_fallback else Color.WHITE

func setup(p_type: PieceType, p_color: PieceColor, p_coord: Vector2i, p_board: Node2D) -> void:
	type = p_type
	color = p_color
	coord = p_coord
	board = p_board

# Ortogonais - compartilham aresta
const DIR_ORTHO = [
	Vector2i(+1, 0), Vector2i(-1, 0),
	Vector2i(+1, -1), Vector2i(-1, +1),
	Vector2i(0, -1), Vector2i(0, +1),
]
# Diagonais - compartilham vertice
const DIR_DIAG = [
	Vector2i(+2, -1), Vector2i(-2, +1),
	Vector2i(+1, -2), Vector2i(-1, +2),
	Vector2i(+1, +1), Vector2i(-1, -1),
]
# Cavalo - 12 saltos no hex
const KNIGHT_JUMPS = [
	Vector2i(+3, -1), Vector2i(+3, -2),
	Vector2i(+1, -3), Vector2i(+2, -3),
	Vector2i(-1, -2), Vector2i(-2, -1),
	Vector2i(-3, +1), Vector2i(-3, +2),
	Vector2i(-1, +3), Vector2i(-2, +3),
	Vector2i(+1, +2), Vector2i(+2, +1),
]

func get_valid_moves() -> Array[Vector2i]:
	if board == null: return []
	match type:
		PieceType.PAWN: return _pawn()
		PieceType.ROOK: return _rook()
		PieceType.KNIGHT: return _knight()
		PieceType.BISHOP: return _bishop()
		PieceType.QUEEN: return _queen()
		PieceType.KING: return _king()
		PieceType.ARCHBISHOP: return _archbishop()
		PieceType.CHANCELLOR: return _chancellor()
		PieceType.SENTINEL: return _sentinel()
		PieceType.SPY: return _spy()
		PieceType.PORTAL: return _portal()
	return []

# === CLASSICAS ===

func _pawn() -> Array[Vector2i]:
	var moves: Array[Vector2i] = []
	var adv = Vector2i(0,-1) if color == PieceColor.WHITE else Vector2i(0,+1)
	var t1 = coord + adv
	if board.is_valid_tile(t1) and _at(t1) == null:
		moves.append(t1)
		if not has_moved:
			var t2 = t1 + adv
			if board.is_valid_tile(t2) and _at(t2) == null:
				moves.append(t2)
	var caps = [Vector2i(+1,-1), Vector2i(-1,0)] if color == PieceColor.WHITE \
		else [Vector2i(-1,+1), Vector2i(+1,0)]
	for d in caps:
		var t = coord + d
		if board.is_valid_tile(t):
			var p = _at(t)
			if p != null and p.color != self.color:
				moves.append(t)
	return moves

func _rook() -> Array[Vector2i]:
	var m: Array[Vector2i] = []
	for d in DIR_ORTHO: m.append_array(_slide(d))
	return m

func _knight() -> Array[Vector2i]:
	var m: Array[Vector2i] = []
	for j in KNIGHT_JUMPS:
		var t = coord + j
		if board.is_valid_tile(t):
			var p = _at(t)
			if p == null or p.color != self.color: m.append(t)
	return m

func _bishop() -> Array[Vector2i]:
	var m: Array[Vector2i] = []
	for d in DIR_DIAG: m.append_array(_slide(d))
	return m

func _queen() -> Array[Vector2i]:
	var m: Array[Vector2i] = []
	for d in DIR_ORTHO: m.append_array(_slide(d))
	for d in DIR_DIAG: m.append_array(_slide(d))
	return m

func _king() -> Array[Vector2i]:
	var m: Array[Vector2i] = []
	for d in DIR_ORTHO + DIR_DIAG:
		var t = coord + d
		if board.is_valid_tile(t):
			var p = _at(t)
			if p == null or p.color != self.color: m.append(t)
	return m

# === HIBRIDAS ===

func _archbishop() -> Array[Vector2i]:
	# Bispo + Cavalo
	var m: Array[Vector2i] = []
	for d in DIR_DIAG: m.append_array(_slide(d))
	for j in KNIGHT_JUMPS:
		var t = coord + j
		if board.is_valid_tile(t):
			var p = _at(t)
			if (p == null or p.color != self.color) and not m.has(t): m.append(t)
	return m

func _chancellor() -> Array[Vector2i]:
	# Torre + Cavalo
	var m: Array[Vector2i] = []
	for d in DIR_ORTHO: m.append_array(_slide(d))
	for j in KNIGHT_JUMPS:
		var t = coord + j
		if board.is_valid_tile(t):
			var p = _at(t)
			if (p == null or p.color != self.color) and not m.has(t): m.append(t)
	return m

# === INEDITAS ===

func _sentinel() -> Array[Vector2i]:
	# Move 1-2 ortogonal. Toggle bloqueio: 6 vizinhos bloqueados pra inimigos
	var m: Array[Vector2i] = []
	if is_blocking:
		m.append(coord)  # desativar
		return m
	for d in DIR_ORTHO:
		var t1 = coord + d
		if board.is_valid_tile(t1):
			var p1 = _at(t1)
			if p1 == null:
				m.append(t1)
				var t2 = t1 + d
				if board.is_valid_tile(t2):
					var p2 = _at(t2)
					if p2 == null or p2.color != self.color: m.append(t2)
			elif p1.color != self.color: m.append(t1)
	m.append(coord)  # ativar bloqueio
	return m

func get_sentinel_blocked_tiles() -> Array[Vector2i]:
	if not is_blocking: return []
	var b: Array[Vector2i] = []
	for d in DIR_ORTHO:
		var t = coord + d
		if board.is_valid_tile(t): b.append(t)
	return b

func _spy() -> Array[Vector2i]:
	# Oculto: 1 casa qualquer dir, sem captura, invisivel
	# Revelado: 1-2 ortho + 1 diag, com captura, permanente
	var m: Array[Vector2i] = []
	if not is_revealed:
		for d in DIR_ORTHO + DIR_DIAG:
			var t = coord + d
			if board.is_valid_tile(t) and _at(t) == null: m.append(t)
		m.append(coord)  # revelar
	else:
		for d in DIR_ORTHO:
			var t1 = coord + d
			if board.is_valid_tile(t1):
				var p1 = _at(t1)
				if p1 == null:
					m.append(t1)
					var t2 = t1 + d
					if board.is_valid_tile(t2):
						var p2 = _at(t2)
						if p2 == null or p2.color != self.color: m.append(t2)
				elif p1.color != self.color: m.append(t1)
		for d in DIR_DIAG:
			var t = coord + d
			if board.is_valid_tile(t):
				var p = _at(t)
				if p == null or p.color != self.color: m.append(t)
	return m

func _portal() -> Array[Vector2i]:
	# Move 1 ortogonal sem captura. Cria portal no tile atual.
	# Aliados adjacentes podem teleportar entre portais pares.
	var m: Array[Vector2i] = []
	for d in DIR_ORTHO:
		var t = coord + d
		if board.is_valid_tile(t) and _at(t) == null: m.append(t)
	m.append(coord)
	return m

func get_portal_teleport_targets(ally_coord: Vector2i) -> Array[Vector2i]:
	var tgts: Array[Vector2i] = []
	var adj = false
	for d in DIR_ORTHO:
		if coord + d == ally_coord: adj = true; break
	if not adj or portal_pair_coord == Vector2i(-999,-999): return tgts
	for d in DIR_ORTHO:
		var t = portal_pair_coord + d
		if board.is_valid_tile(t) and _at(t) == null: tgts.append(t)
	return tgts

# === UTILITARIOS ===

func _slide(dir: Vector2i) -> Array[Vector2i]:
	var m: Array[Vector2i] = []
	var c = coord + dir
	while board.is_valid_tile(c):
		var p = _at(c)
		if p == null: m.append(c)
		elif p.color != self.color: m.append(c); break
		else: break
		c = c + dir
	return m

func _at(c: Vector2i):
	if not board.tiles.has(c): return null
	return board.tiles[c].get("piece", null)

func get_display_name() -> String:
	var n = {
		PieceType.PAWN:"Peao", PieceType.ROOK:"Torre", PieceType.KNIGHT:"Cavalo",
		PieceType.BISHOP:"Bispo", PieceType.QUEEN:"Dama", PieceType.KING:"Rei",
		PieceType.ARCHBISHOP:"Arcebispo", PieceType.CHANCELLOR:"Chanceler",
		PieceType.SENTINEL:"Sentinela", PieceType.SPY:"Espiao", PieceType.PORTAL:"Portal",
	}
	return n.get(type, "???")

func get_material_value() -> int:
	var v = {
		PieceType.PAWN:100, PieceType.KNIGHT:300, PieceType.BISHOP:350,
		PieceType.ROOK:500, PieceType.QUEEN:900, PieceType.KING:99999,
		PieceType.ARCHBISHOP:700, PieceType.CHANCELLOR:850,
		PieceType.SENTINEL:400, PieceType.SPY:350, PieceType.PORTAL:250,
	}
	return v.get(type, 0)
