local mvec1 = Vector3()
local mvec2 = Vector3()
local mrot1 = Rotation()

function ProjectileBase:update(unit, t, dt)
	if not self._simulated and not self._collided then
		self._unit:m_position(mvec1)
		mvector3.set(mvec2, self._velocity * dt)
		mvector3.add(mvec1, mvec2)
		self._unit:set_position(mvec1)

		if self._orient_to_vel then
			mrotation.set_look_at(mrot1, mvec2, math.UP)
			self._unit:set_rotation(mrot1)
		end

		self._velocity = Vector3(self._velocity.x, self._velocity.y, self._velocity.z - 980 * dt)
	end

	if self._sweep_data and not self._collided then
		self._unit:m_position(self._sweep_data.current_pos)

		local col_ray = nil

		if self._thrower_unit then
			col_ray = World:raycast("ray", self._sweep_data.last_pos, self._sweep_data.current_pos, "slot_mask", self._sweep_data.slot_mask, "ignore_unit", {self._thrower_unit}) --prevent husks from hitting themselves with RPGs/grenade launchers
		else
			col_ray = World:raycast("ray", self._sweep_data.last_pos, self._sweep_data.current_pos, "slot_mask", self._sweep_data.slot_mask)
		end

		if self._draw_debug_trail then
			Draw:brush(Color(1, 0, 0, 1), nil, 3):line(self._sweep_data.last_pos, self._sweep_data.current_pos)
		end

		if col_ray and col_ray.unit then
			mvector3.direction(mvec1, self._sweep_data.last_pos, self._sweep_data.current_pos)
			mvector3.add(mvec1, col_ray.position)
			self._unit:set_position(mvec1)
			self._unit:set_position(mvec1)

			if self._draw_debug_impact then
				Draw:brush(Color(0.5, 0, 0, 1), nil, 10):sphere(col_ray.position, 4)
				Draw:brush(Color(0.5, 1, 0, 0), nil, 10):sphere(self._unit:position(), 3)
			end

			col_ray.velocity = self._unit:velocity()
			self._collided = true

			self:_on_collision(col_ray)
		end

		self._unit:m_position(self._sweep_data.last_pos)
	end
end

function ProjectileBase.throw_projectile(projectile_type, pos, dir, owner_peer_id, npc_unit, npc_throwable)
	if not ProjectileBase.check_time_cheat(projectile_type, owner_peer_id) then
		return
	end

	local tweak_entry = tweak_data.blackmarket.projectiles[projectile_type]
	local unit_name = Idstring(not Network:is_server() and tweak_entry.local_unit or tweak_entry.unit)
	local unit = World:spawn_unit(unit_name, pos, Rotation(dir, math.UP))

	if npc_unit then
		if not Network:is_server() then
			return
		end

		if alive(npc_unit) then
			unit:base():set_thrower_unit(npc_unit)

			if not npc_throwable then
				unit:base():set_weapon_unit(npc_unit:inventory():equipped_unit())
			end
		end
	else
		if owner_peer_id and managers.network:session() then
			local peer = managers.network:session():peer(owner_peer_id)
			local thrower_unit = peer and peer:unit()

			if alive(thrower_unit) then
				unit:base():set_thrower_unit(thrower_unit)

				if not tweak_entry.throwable and thrower_unit:movement() and thrower_unit:movement():current_state() then
					unit:base():set_weapon_unit(thrower_unit:movement():current_state()._equipped_unit)
				end
			end
		end
	end

	unit:base():throw({
		dir = dir,
		projectile_entry = projectile_type
	})

	if not npc_unit then
		if unit:base().set_owner_peer_id then
			unit:base():set_owner_peer_id(owner_peer_id)
		end
	end

	local projectile_type_index = tweak_data.blackmarket:get_index_from_projectile_id(projectile_type)
	local sync_peer_id = 0

	if not npc_unit and owner_peer_id then
		sync_peer_id = owner_peer_id
	end

	managers.network:session():send_to_peers_synched("sync_throw_projectile", unit:id() ~= -1 and unit or nil, pos, dir, projectile_type_index, sync_peer_id)

	if tweak_data.blackmarket.projectiles[projectile_type].impact_detonation then
		unit:damage():add_body_collision_callback(callback(unit:base(), unit:base(), "clbk_impact"))
		unit:base():create_sweep_data()
	end

	return unit
end
