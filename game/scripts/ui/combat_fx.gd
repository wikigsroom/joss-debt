extends RefCounted
## Generated keyframes + deterministic presentation particles; no gameplay RNG.
const SOURCE = "res://assets/fx/combat-revision/"

static func line(r, from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var geometry = r.world.geometry
	if not r.fx_safe_draw and (not geometry.contains_floor(from,width*.5) or not geometry.contains_floor(to,width*.5)):
		# Convex arena: trim against every radius-offset inward wall plane.
		var start = 0.0
		var end = 1.0
		var delta = to-from
		if geometry.floor_planes.size() != geometry.floor_polygon.size(): geometry.cache_floor_planes()
		for plane in geometry.floor_planes:
			var distance = from.x * plane.x + from.y * plane.y - plane.z - width * .5
			var rate = delta.x * plane.x + delta.y * plane.y
			if absf(rate)<.00001:
				if distance<0: return
			elif rate>0: start=maxf(start,-distance/rate)
			else: end=minf(end,-distance/rate)
			if start>=end: return
		to=from+delta*end
		from+=delta*start
	r.draw_line(from,to,color,width,true)

static func arc(r, point: Vector2, radius: float, start: float, end: float, count: int, color: Color, width: float) -> void:
	if r.fx_safe_draw or r.world.geometry.contains_floor(point,radius+width*.5):
		r.draw_arc(point,radius,start,end,count,color,width,true)
		return
	for i in count:
		var from = point+Vector2.RIGHT.rotated(lerpf(start,end,float(i)/count))*radius
		var to = point+Vector2.RIGHT.rotated(lerpf(start,end,float(i+1)/count))*radius
		line(r,from,to,color,width)

static func disk(r, point: Vector2, radius: float, color: Color) -> void:
	if r.fx_safe_draw or r.world.geometry.contains_floor(point,radius):
		r.draw_circle(point,radius,color)
		return
	var circle = PackedVector2Array()
	for i in 64: circle.append(point+Vector2.RIGHT.rotated(i*TAU/64)*radius)
	for piece in Geometry2D.intersect_polygons(circle,r.world.geometry.floor_polygon):
		var clipped = convex_piece(piece)
		if not clipped.is_empty(): r.draw_colored_polygon(clipped,color)

static func convex_piece(piece: PackedVector2Array) -> PackedVector2Array:
	# Both inputs are convex. Drop duplicate/collinear clipper vertices and
	# zero-area wall-edge slivers before the native canvas triangulates them.
	var hull = Geometry2D.convex_hull(piece)
	if hull.size()<4: return PackedVector2Array()
	hull.remove_at(hull.size()-1)
	if Geometry2D.triangulate_polygon(hull).is_empty(): return PackedVector2Array()
	return hull

static func frame(r, id: String, index: int) -> Texture2D:
	index = clampi(index, 0, 5)
	var key = "combat_revision_%s_%d" % [id,index]
	if r.textures.has(key): return r.textures[key]
	var path = SOURCE + id + ".png"
	if not r.textures.has(path): r.textures[path] = load(path)
	var image = AtlasTexture.new()
	image.atlas = r.textures[path]
	image.region = Rect2(index * 256, 0, 256, 256)
	r.textures[key] = image
	return image

static func sprite(r, image: Texture2D, point: Vector2, size: Vector2, angle: float = 0, tint: Color = Color.WHITE) -> void:
	if image == null or tint.a < .004 or size.x < .1 or size.y < .1: return
	var transform = Transform2D(angle, point)
	var floor = r.world.geometry.floor_polygon
	if r.fx_safe_draw or floor.is_empty() or r.world.geometry.contains_floor(point,size.length()*.5):
		r.draw_set_transform_matrix(r.stage * transform)
		r.draw_texture_rect(image,Rect2(-size*.5,size),false,tint)
		r.draw_set_transform_matrix(r.stage)
		return
	var quad = PackedVector2Array()
	for corner in [Vector2(-.5,-.5),Vector2(.5,-.5),Vector2(.5,.5),Vector2(-.5,.5)]: quad.append(transform * (corner * size))
	# Texture UVs follow the cut polygon. Blasts never paint over the outer walls.
	for piece in Geometry2D.intersect_polygons(quad, floor):
		piece = convex_piece(piece)
		if piece.is_empty(): continue
		var uv = PackedVector2Array()
		for vertex in piece: uv.append((transform.affine_inverse() * vertex) / size + Vector2.ONE * .5)
		r.draw_polygon(piece,PackedColorArray([tint]),uv,image)

static func beam_color(style: String) -> Color:
	return Color({"beam_ink":"9ee7e7","beam_thread":"ffa958","beam_prism":"c6aeff"}.get(style,"ffc969"))

static func flow(r, from: Vector2, to: Vector2, half_width: float, style: String, elapsed: float, alpha: float, hostile: bool = false) -> void:
	var length = from.distance_to(to)
	if length < 1: return
	var direction = from.direction_to(to)
	var color = r.HOSTILE if hostile else beam_color(style)
	var outline = Color("111b25",alpha * .48)
	var edge = direction.orthogonal()*half_width
	for side in [-1,1]: line(r,from+edge*side,to+edge*side,outline,2.5)
	line(r,from,to,Color(color,alpha*.22),half_width*2)
	var count = maxi(1,ceili(length / 100))
	for i in count:
		var start = from.lerp(to,float(i)/count)
		var end = from.lerp(to,float(i+1)/count)
		var phase = 2 if r.reduce_motion else 1 + posmod(int(elapsed*20) + i,4)
		sprite(r,frame(r,style,phase),(start+end)*.5,Vector2(start.distance_to(end)*1.13,half_width*4),direction.angle(),Color(1,1,1,alpha*.94))
	var core = 2.5 + (0 if r.reduce_motion else sin(elapsed*56)*.7)
	line(r,from,to,Color("fff2cc",alpha*(.62+.18*r.flash_scale)),core)
	for i in roundi(minf(9,length/70)*r.particle_scale):
		var fraction = fmod(elapsed * 1.9 + i * .173,1.0)
		var position = from.lerp(to,fraction)
		var side = direction.orthogonal()*sin(elapsed*13+i*1.7)*half_width*.8
		sprite(r,frame(r,style,0),position+side,Vector2(19,24)*(.7+half_width/30),direction.angle(),Color(1,1,1,alpha*.7))

static func beam(r, effect: Dictionary, progress: float) -> bool:
	var from = Vector2(effect.pos)
	var end = Vector2(effect.get("end",effect.pos+effect.dir*effect.range))
	var elapsed = progress * float(effect.total)
	var style = str(effect.get("style","beam_amber"))
	var width = float(effect.get("width",14))
	var alpha = (1-progress) if progress > .65 else 1.0
	if progress > .65: alpha = (1-progress)/.35
	var direction = from.direction_to(end)
	# Ignite quickly, then flowing ribbons, impact fragments and smoke afterglow.
	var front = from.lerp(end,minf(1,elapsed/.045))
	flow(r,from,front,width,style,elapsed,alpha)
	sprite(r,frame(r,style,0),from,Vector2.ONE*(42+width),elapsed*2,Color(1,1,1,alpha))
	var impact_style = "blast_ink" if style=="beam_ink" else "shockwave" if style=="beam_prism" else "blast_flame"
	sprite(r,frame(r,impact_style,2 if progress<.25 else 3 if progress<.55 else 5),end,Vector2.ONE*(width*4+24),elapsed*.6,Color(1,1,1,alpha*.84))
	for i in roundi(12*r.particle_scale):
		var angle = direction.angle() + (i-5.5)*.24
		var travel = minf(40,elapsed*(45+i*8))
		var point = end + Vector2.RIGHT.rotated(angle)*travel
		sprite(r,frame(r,impact_style,5),point,Vector2.ONE*(7+i%3*3),angle+elapsed*3,Color(1,1,1,alpha*.6))
	return true

static func burst(r, effect: Dictionary, progress: float) -> bool:
	var radius = float(effect.get("radius",80))
	var position = Vector2(effect.pos)
	var style = str(effect.get("style","blast_flame"))
	if style not in ["blast_flame","blast_ink","blast_lotus","shockwave"]: style="blast_flame"
	var color = r.HOSTILE if style=="blast_ink" else r.FIRE
	var index = clampi(int(progress*6),0,5)
	var opacity = minf(1,(1-progress)*2.4)
	# The fine dark/light perimeter marks the actual damage radius throughout.
	arc(r,position,radius,0,TAU,72,Color("111b25",opacity*.72),5)
	arc(r,position,radius,0,TAU,72,Color(color,opacity*.8),2)
	sprite(r,frame(r,style,index),position,Vector2.ONE*radius*2.15,0,Color(1,1,1,opacity))
	var shock_radius = radius * minf(1,.22+progress*2.1)
	if progress<.5:
		arc(r,position,shock_radius,0,TAU,64,Color("fff3c8",opacity*.5*(.4+.6*r.flash_scale)),2+2*(1-progress))
	for i in roundi(18*r.particle_scale):
		var angle = i*TAU/18 + float(effect.get("at",0))*.17
		var distance = radius * minf(.95,.12+progress*(1.5+i%3*.18))
		var point = position + Vector2.RIGHT.rotated(angle)*distance
		sprite(r,frame(r,style,5),point,Vector2.ONE*(10+i%4*3)*(1-progress*.6),angle+progress*4,Color(1,1,1,opacity*.65))
	return true

static func zone(r, zone: Dictionary) -> void:
	var warning = r.world.time < zone.active
	var color = r.FIRE if zone.friendly else r.HOSTILE
	var born = float(zone.get("born",zone.active-1.0))
	var elapsed = maxf(0,r.world.time-zone.active)
	var amount = clampf((r.world.time-born)/maxf(.01,zone.active-born),0,1)
	var position = Vector2(zone.pos)
	if zone.get("shape","")=="line":
		var from = Vector2(zone.from)
		var to = Vector2(zone.to)
		if warning:
			line(r,from,to,Color("111b25",.65),zone.width*2+5)
			line(r,from,to,Color(color,.12+amount*.15),zone.width*2)
			for i in 20:
				var start = from.lerp(to,i/20.0)
				var end = from.lerp(to,(i+.55)/20.0)
				line(r,start,end,Color(color,.5+amount*.45),3)
			for point in [from,to]:
				sprite(r,frame(r,"beam_prism",0),point,Vector2.ONE*(25+amount*23),r.clock*.8,Color(1,1,1,.3+amount*.6))
		else:
			flow(r,from,to,float(zone.width),str(zone.get("style","beam_prism")),elapsed,.95,not zone.friendly)
		return
	var radius = float(zone.radius)
	var style = str(zone.get("style","blast_flame" if zone.friendly else "blast_ink"))
	if warning:
		disk(r,position,radius,Color(color,.05+amount*.04))
		arc(r,position,radius,0,TAU,64,Color("111b25",.84),5)
		arc(r,position,radius,0,TAU,64,Color(color,.6+amount*.35),2)
		arc(r,position,radius-5,-PI*.5,-PI*.5+TAU*amount,64,Color("fff3cf",.8),3)
		sprite(r,frame(r,"shockwave",5),position,Vector2.ONE*radius*1.92,r.clock*.12,Color(color,.2+amount*.18))
		for i in 8:
			var axis = Vector2.RIGHT.rotated(i*TAU/8)
			line(r,position+axis*(radius-11),position+axis*(radius+2),Color(color,.9),3)
		sprite(r,frame(r,style,0),position,Vector2.ONE*(24+amount*30),0,Color(1,1,1,.4+amount*.5))
	else:
		var index = clampi(2+int(elapsed*10),2,5)
		var pulse = .72 + (0 if r.reduce_motion else sin(elapsed*7)*.12)
		sprite(r,frame(r,style,index),position,Vector2.ONE*radius*2.1,r.clock*.08,Color(1,1,1,.78 if elapsed<.3 else .32))
		arc(r,position,radius,0,TAU,64,Color("111b25",.9),6)
		arc(r,position,radius,0,TAU,64,Color(color,pulse),3)
		for i in roundi(10*r.particle_scale):
			var axis = Vector2.RIGHT.rotated(i*TAU/10 + elapsed*.45)
			sprite(r,frame(r,style,4),position+axis*radius*.8,Vector2.ONE*18,axis.angle(),Color(1,1,1,.7))
