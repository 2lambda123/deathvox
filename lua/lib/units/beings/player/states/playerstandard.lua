local mvec3_dis_sq = mvector3.distance_sq
local mvec3_set = mvector3.set
local mvec3_set_z = mvector3.set_z
local mvec3_sub = mvector3.subtract
local mvec3_add = mvector3.add
local mvec3_mul = mvector3.multiply
local mvec3_norm = mvector3.normalize

local tmp_ground_from_vec = Vector3()
local tmp_ground_to_vec = Vector3()
local up_offset_vec = math.UP * 30
local down_offset_vec = math.UP * -40

function PlayerStandard:_update_ground_ray()
	local hips_pos = tmp_ground_from_vec
	local down_pos = tmp_ground_to_vec

	mvec3_set(hips_pos, self._pos)
	mvec3_add(hips_pos, up_offset_vec)
	mvec3_set(down_pos, hips_pos)
	mvec3_add(down_pos, down_offset_vec)

	if self._unit:movement():ladder_unit() then
		self._gnd_ray = self._unit:raycast("ray", hips_pos, down_pos, "slot_mask", self._slotmask_gnd_ray, "ignore_unit", self._unit:movement():ladder_unit(), "ray_type", "body mover", "sphere_cast_radius", 29, "bundle", 9, "report")
	else
		self._gnd_ray = self._unit:raycast("ray", hips_pos, down_pos, "slot_mask", self._slotmask_gnd_ray, "ray_type", "body mover", "sphere_cast_radius", 29, "bundle", 9, "report")
	end

	self._gnd_ray_chk = true
end

function PlayerStandard:_chk_floor_moving_pos(pos)
	local hips_pos = tmp_ground_from_vec
	local down_pos = tmp_ground_to_vec

	mvec3_set(hips_pos, self._pos)
	mvec3_add(hips_pos, up_offset_vec)
	mvec3_set(down_pos, hips_pos)
	mvec3_add(down_pos, down_offset_vec)

	local ground_ray = self._unit:raycast("ray", hips_pos, down_pos, "slot_mask", self._slotmask_gnd_ray, "ray_type", "body mover", "sphere_cast_radius", 29, "bundle", 9)

	if ground_ray and ground_ray.body and math.abs(ground_ray.body:velocity().z) > 0 then
		return ground_ray.body:position().z
	end
end

function PlayerStandard:init(unit)
	PlayerMovementState.init(self, unit)

	self._tweak_data = tweak_data.player.movement_state.standard
	self._obj_com = self._unit:get_object(Idstring("rp_mover"))
	local slot_manager = managers.slot
	self._slotmask_gnd_ray = slot_manager:get_mask("player_ground_check")
	self._slotmask_fwd_ray = slot_manager:get_mask("bullet_impact_targets")
	self._slotmask_bullet_impact_targets = slot_manager:get_mask("bullet_impact_targets")
	self._slotmask_bullet_impact_targets = managers.mutators:modify_value("PlayerStandard:init:melee_slot_mask", self._slotmask_bullet_impact_targets)
	self._slotmask_pickups = slot_manager:get_mask("pickups")
	self._slotmask_AI_visibility = slot_manager:get_mask("AI_visibility")
	self._slotmask_long_distance_interaction = slot_manager:get_mask("long_distance_interaction")
	self._ext_camera = unit:camera()
	self._ext_movement = unit:movement()
	self._ext_damage = unit:character_damage()
	self._ext_inventory = unit:inventory()
	self._ext_anim = unit:anim_data()
	self._ext_network = unit:network()
	self._ext_event_listener = unit:event_listener()
	self._camera_unit = self._ext_camera._camera_unit
	self._camera_unit_anim_data = self._camera_unit:anim_data()
	self._machine = unit:anim_state_machine()
	self._m_pos = self._ext_movement:m_pos()
	self._pos = Vector3()
	self._stick_move = Vector3()
	self._stick_look = Vector3()
	self._cam_fwd_flat = Vector3()
	self._walk_release_t = -100
	self._last_sent_pos = unit:position()
	self._last_sent_pos_t = 0
	self._state_data = unit:movement()._state_data
	local pm = managers.player
	self.RUN_AND_RELOAD = pm:has_category_upgrade("player", "run_and_reload")
	self._pickup_area = 200 * pm:upgrade_value("player", "increased_pickup_area", 1)

	self:set_animation_state("standard")

	self._interaction = managers.interaction
	self._on_melee_restart_drill = pm:has_category_upgrade("player", "drill_melee_hit_restart_chance")
	local controller = unit:base():controller()

	if controller:get_type() ~= "pc" and controller:get_type() ~= "vr" then
		self._input = {}

		table.insert(self._input, BipodDeployControllerInput:new())

		if pm:has_category_upgrade("player", "second_deployable") then
			table.insert(self._input, SecondDeployableControllerInput:new())
		end
	end

	self._input = self._input or {}

	table.insert(self._input, HoldButtonMetaInput:new("night_vision", "weapon_firemode", nil, 0.5))

	self._menu_closed_fire_cooldown = 0

	managers.menu:add_active_changed_callback(callback(self, self, "_on_menu_active_changed"))
end

function PlayerStandard:_check_action_jump(t, input)
	local new_action = nil
	local action_wanted = input.btn_jump_press

	if action_wanted then
		local action_forbidden = self._jump_t and t < self._jump_t + 0.55
		
		local cant_mid_air_jump = nil
		local wave_dashing = nil
		local skill = managers.player:has_category_upgrade("player", "wave_dash_basic")
		local skill2 = managers.player:has_category_upgrade("player", "wave_dash_aced")
		
		if self._state_data.in_air then
			cant_mid_air_jump = true
			
			if skill then			
				if not self._wave_dash_t or self._wave_dash_t and self._wave_dash_t < t then
					cant_mid_air_jump = nil
					action_forbidden = nil
					self._wave_dash_t = t + 5
					wave_dashing = true
				end
			end
		end
			
		
		action_forbidden = action_forbidden or self._unit:base():stats_screen_visible() or cant_mid_air_jump or self:_interacting() or self:_on_zipline() or self:_does_deploying_limit_movement() or self:_is_using_bipod()

		if not action_forbidden then
			if self._state_data.ducking then
				self:_interupt_action_ducking(t)
			else
				if self._state_data.on_ladder then
					self:_interupt_action_ladder(t)
				end

				local action_start_data = {}
				local jump_vel_z = tweak_data.player.movement_state.standard.movement.jump_velocity.z
				
				if wave_dashing then
					if not self._move_dir or not skill2 then
						if not self._move_dir then
							self._move_dir = Vector3()
						end
						
						if skill2 or not self._jump_vel_xy then
							mvec3_set(self._move_dir, self._unit:movement()._m_head_rot:y())
						else
							mvec3_set(self._move_dir, self._jump_vel_xy)
						end
					end	
					
					jump_vel_z = 200
				end
				
				action_start_data.jump_vel_z = jump_vel_z
				
				if self._move_dir then
					local is_running = self._running and self._unit:movement():is_above_stamina_threshold() and t - self._start_running_t > 0.4
					local jump_vel_xy = wave_dashing and 1000 or tweak_data.player.movement_state.standard.movement.jump_velocity.xy[is_running and "run" or "walk"]
					
					action_start_data.jump_vel_xy = jump_vel_xy

					if is_running then
						self._unit:movement():subtract_stamina(tweak_data.player.movement_state.stamina.JUMP_STAMINA_DRAIN)
					end
				end

				new_action = self:_start_action_jump(t, action_start_data)
			end
		end
	end

	return new_action
end

function PlayerStandard:_update_fwd_ray()
	local from = self._unit:movement():m_head_pos()
	local range = alive(self._equipped_unit) and self._equipped_unit:base():has_range_distance_scope() and 20000 or 4000
	local to = self._cam_fwd * range

	mvector3.add(to, from)

	self._fwd_ray = World:raycast("ray", from, to, "slot_mask", self._slotmask_fwd_ray)

	managers.environment_controller:set_dof_distance(math.max(0, math.min(self._fwd_ray and self._fwd_ray.distance or 4000, 4000) - 200), self._state_data.in_steelsight)

	if alive(self._equipped_unit) then
		if self._state_data.in_steelsight and self._equipped_unit:base().check_highlight_unit then
			--with this method, range for depth of field and scope distance isn't affected and marking works through glass (or to be more specific, through surfaces that the AI can see through)
			local marking_from = self._unit:movement():m_head_pos()
			local marking_to = self._cam_fwd * 20000

			mvector3.add(marking_to, marking_from)

			local ray_hits = nil
			local hit_person_or_sentry = false
			local person_mask = managers.slot:get_mask("persons")
			local sentry_mask = managers.slot:get_mask("sentry_gun")
			local wall_mask = managers.slot:get_mask("world_geometry", "vehicles")
			local shield_mask = managers.slot:get_mask("enemy_shield_check")
			local ai_vision_ids = Idstring("ai_vision")

			ray_hits = World:raycast_all("ray", marking_from, marking_to, "slot_mask", self._slotmask_fwd_ray, "ignore_unit", self._equipped_unit:base()._setup.ignore_units)

			local units_hit = {}
			local unique_hits = {}

			for i, hit in ipairs(ray_hits) do
				if not units_hit[hit.unit:key()] then
					units_hit[hit.unit:key()] = true
					unique_hits[#unique_hits + 1] = hit
					hit.hit_position = hit.position
					hit_person_or_sentry = hit_person_or_sentry or hit.unit:in_slot(person_mask) or hit.unit:in_slot(sentry_mask)
					local weak_body = hit.body:has_ray_type(ai_vision_ids)

					if hit_person_or_sentry then
						break
					elseif hit.unit:in_slot(wall_mask) and weak_body then
						break
					elseif hit.unit:in_slot(shield_mask) then
						break
					end
				end
			end

			for _, hit in ipairs(unique_hits) do
				if hit.unit then
					self._equipped_unit:base():check_highlight_unit(hit.unit)
				end
			end
		end

		if self._equipped_unit:base().set_scope_range_distance then
			self._equipped_unit:base():set_scope_range_distance(self._fwd_ray and self._fwd_ray.distance / 100 or false)
		end
	end
end

function PlayerStandard:_get_intimidation_action(prime_target, char_table, amount, primary_only, detect_only, secondary)
	local voice_type, new_action, plural = nil
	local unit_type_enemy = 0
	local unit_type_civilian = 1
	local unit_type_teammate = 2
	local unit_type_camera = 3
	local unit_type_turret = 4
	local is_whisper_mode = managers.groupai:state():whisper_mode()

	if prime_target then
		if prime_target.unit_type == unit_type_teammate then
			local is_human_player, record, do_nothing = nil

			if not detect_only then
				record = managers.groupai:state():all_criminals()[prime_target.unit:key()]

				if record.ai then
					if not prime_target.unit:brain():player_ignore() then
						if secondary then
							if prime_target.unit:movement()._should_stay then
								do_nothing = true
							end
						else
							if self._ext_movement:rally_skill_data() and not managers.player:has_enabled_cooldown_upgrade("cooldown", "long_dis_revive") and (prime_target.unit:character_damage():arrested() or prime_target.unit:character_damage():need_revive()) then
								do_nothing = true
							end
						end

						if not do_nothing then
							prime_target.unit:movement():set_cool(false)
							prime_target.unit:brain():on_long_dis_interacted(0, self._unit, secondary)
						end
					end
				else
					is_human_player = true
				end
			end

			local amount = 0
			local current_state_name = self._unit:movement():current_state_name()

			if current_state_name ~= "arrested" and current_state_name ~= "bleed_out" and current_state_name ~= "fatal" and current_state_name ~= "incapacitated" then
				local rally_skill_data = self._ext_movement:rally_skill_data()

				if rally_skill_data and mvector3.distance_sq(self._pos, record.m_pos) < rally_skill_data.range_sq then
					local needs_revive, is_arrested, action_stop = nil

					if not secondary then
						if prime_target.unit:base().is_husk_player then
							is_arrested = prime_target.unit:movement():current_state_name() == "arrested"
							needs_revive = prime_target.unit:interaction():active() and prime_target.unit:movement():need_revive() and not is_arrested
						else
							is_arrested = prime_target.unit:character_damage():arrested()
							needs_revive = prime_target.unit:character_damage():need_revive()
						end

						if needs_revive then
							if managers.player:has_enabled_cooldown_upgrade("cooldown", "long_dis_revive") then
								voice_type = "revive"

								managers.player:disable_cooldown_upgrade("cooldown", "long_dis_revive")
							else
								do_nothing = true
							end
						elseif is_human_player and not is_arrested and not needs_revive and rally_skill_data.morale_boost_delay_t and rally_skill_data.morale_boost_delay_t < managers.player:player_timer():time() then
							voice_type = "boost"
							amount = 1
						end
					end
				end
			end

			if is_human_player then
				prime_target.unit:network():send_to_unit({
					"long_dis_interaction",
					prime_target.unit,
					amount,
					self._unit,
					secondary or false
				})
			end

			voice_type = voice_type or secondary and not is_human_player and not do_nothing and "ai_stay" or not do_nothing and "come" or nil
			plural = false
		else
			local prime_target_key = prime_target.unit:key()

			if prime_target.unit_type == unit_type_enemy then
				plural = false

				if prime_target.unit:anim_data().hands_back then
					voice_type = "cuff_cop"
				elseif prime_target.unit:anim_data().surrender then
					voice_type = "down_cop"
				elseif is_whisper_mode and prime_target.unit:movement():cool() and prime_target.unit:base():char_tweak().silent_priority_shout then
					voice_type = "mark_cop_quiet"
				elseif prime_target.unit:base():char_tweak().priority_shout then
					voice_type = "mark_cop"
				else
					if managers.groupai:state():has_room_for_police_hostage() or prime_target.unit:anim_data().hands_back or prime_target.unit:anim_data().surrender then
						if prime_target.unit:base():char_tweak().surrender and not prime_target.unit:base():char_tweak().surrender.special and not prime_target.unit:base():char_tweak().surrender.never then
							voice_type = "stop_cop"
						end
					end
				end
			elseif prime_target.unit_type == unit_type_camera then
				plural = false
				voice_type = "mark_camera"
			elseif prime_target.unit_type == unit_type_turret then
				plural = false
				voice_type = "mark_turret"
			elseif prime_target.unit:base():char_tweak().is_escort then
				plural = false
				local e_guy = prime_target.unit

				voice_type = "escort_keep"
			else
				if prime_target.unit:anim_data().stand then
					if prime_target.is_tied or prime_target.unit:movement():stance_name() == "cbt" then
						voice_type = "come"
					else
						voice_type = "down"
					end
				elseif prime_target.unit:anim_data().move then
					if prime_target.is_tied or prime_target.unit:movement():stance_name() == "cbt" then
						voice_type = "come"
					else
						voice_type = "stop"
					end
				elseif prime_target.unit:anim_data().drop then
					if not prime_target.unit:anim_data().tied then
						voice_type = "down_stay"
					end
				else
					if not prime_target.is_tied then
						voice_type = "down"
					end
				end

				local num_affected = 0

				for _, char in pairs(char_table) do
					if char.unit_type == unit_type_civilian then
						if voice_type == "stop" and char.unit:anim_data().move then
							num_affected = num_affected + 1
						elseif voice_type == "down_stay" and char.unit:anim_data().drop then
							num_affected = num_affected + 1
						elseif voice_type == "down" and not char.unit:anim_data().move and not char.unit:anim_data().drop then
							num_affected = num_affected + 1
						end

						if num_affected > 1 then
							plural = true

							break
						end
					end
				end
			end

			if detect_only then
				voice_type = "come"
			else
				local max_inv_wgt = 0

				for _, char in pairs(char_table) do
					if max_inv_wgt < char.inv_wgt then
						max_inv_wgt = char.inv_wgt
					end
				end

				if max_inv_wgt < 1 then
					max_inv_wgt = 1
				end

				if not amount then
					amount = tweak_data.player.long_dis_interaction.intimidate_strength
				end

				local amount_civ = amount * managers.player:upgrade_value("player", "civ_intimidation_mul", 1) * managers.player:team_upgrade_value("player", "civ_intimidation_mul", 1)

				for _, char in pairs(char_table) do
					if char.unit_type ~= unit_type_camera and char.unit_type ~= unit_type_teammate and (not is_whisper_mode or not char.unit:movement():cool()) then
						local int_amount = char.unit_type == unit_type_civilian and amount_civ or amount

						if prime_target_key == char.unit:key() then
							voice_type = char.unit:brain():on_intimidated(int_amount, self._unit) or voice_type
						elseif not primary_only and char.unit_type ~= unit_type_enemy then
							char.unit:brain():on_intimidated(int_amount * char.inv_wgt / max_inv_wgt, self._unit)
						end
					end
				end

				local aoe_intimidation_radius = managers.player:upgrade_value("player", "shout_intimidation_aoe", 0)

				if aoe_intimidation_radius > 0 then
					local target_unit = prime_target.unit
					--target unit will be ignored by the search
					local aoe_civs = target_unit:find_units_quick("sphere", target_unit:position(), aoe_intimidation_radius, managers.slot:get_mask("civilians"))

					for i = 1, #aoe_civs do
						local aoe_civ = aoe_civs[i]

						if not is_whisper_mode or not aoe_civ:movement():cool() then
							if not aoe_civ:anim_data().long_dis_interact_disabled then
								aoe_civ:brain():on_intimidated(amount_civ, self._unit)
							end
						end
					end
				end
			end
		end
	end

	return voice_type, plural, prime_target
end

function PlayerStandard:_get_unit_intimidation_action(intimidate_enemies, intimidate_civilians, intimidate_teammates, only_special_enemies, intimidate_escorts, intimidation_amount, primary_only, detect_only, secondary)
	local char_table = {}
	local unit_type_enemy = 0
	local unit_type_civilian = 1
	local unit_type_teammate = 2
	local unit_type_camera = 3
	local unit_type_turret = 4
	local cam_fwd = self._ext_camera:forward()
	local my_head_pos = self._ext_movement:m_head_pos()

	if _G.IS_VR then
		local hand_unit = self._unit:hand():hand_unit(self._interact_hand)

		if hand_unit:raycast("ray", hand_unit:position(), my_head_pos, "slot_mask", 1) then
			return
		end

		cam_fwd = hand_unit:rotation():y()
		my_head_pos = hand_unit:position()
	end

	local range_mul = managers.player:upgrade_value("player", "intimidate_range_mul", 1) * managers.player:upgrade_value("player", "passive_intimidate_range_mul", 1)
	local intimidate_range_civ = tweak_data.player.long_dis_interaction.intimidate_range_civilians * range_mul
	local intimidate_range_ene = tweak_data.player.long_dis_interaction.intimidate_range_enemies * range_mul
	local highlight_range = tweak_data.player.long_dis_interaction.highlight_range * range_mul
	local intimidate_range_teammates = tweak_data.player.long_dis_interaction.intimidate_range_teammates

	if intimidate_enemies then
		local enemies = managers.enemy:all_enemies()

		for u_key, u_data in pairs(enemies) do
			if self._unit:movement():team().foes[u_data.unit:movement():team().id] and not u_data.unit:anim_data().hands_tied and not u_data.unit:anim_data().long_dis_interact_disabled and (not u_data.unit:character_damage() or not u_data.unit:character_damage():dead()) and (u_data.char_tweak.priority_shout or not only_special_enemies) then
				local can_intimidate = managers.groupai:state():has_room_for_police_hostage() or u_data.unit:anim_data().hands_back or u_data.unit:anim_data().surrender

				if managers.groupai:state():whisper_mode() then
					if u_data.unit:movement():cool() and u_data.char_tweak.silent_priority_shout then
						self:_add_unit_to_char_table(char_table, u_data.unit, unit_type_enemy, highlight_range, false, false, 100, my_head_pos, cam_fwd)
					elseif not u_data.unit:movement():cool() then
						if can_intimidate and u_data.char_tweak.surrender and not u_data.char_tweak.surrender.special and not u_data.char_tweak.surrender.never then
							self:_add_unit_to_char_table(char_table, u_data.unit, unit_type_enemy, intimidate_range_ene, false, false, 200, my_head_pos, cam_fwd, nil, "ai_vision mover") --200 during stealth since this can really save you at times
						end
					end
				else
					if not u_data.char_tweak.priority_shout then
						if can_intimidate and u_data.char_tweak.surrender and not u_data.char_tweak.surrender.special and not u_data.char_tweak.surrender.never then
							self:_add_unit_to_char_table(char_table, u_data.unit, unit_type_enemy, intimidate_range_ene, false, false, 0.01, my_head_pos, cam_fwd, nil, "ai_vision mover")
						end
					else
						local cloaker_type = u_data.unit:base():has_tag("spooc")
						local medic_type = u_data.unit:base():has_tag("medic")
						local minigun_dozer = u_data.unit:base()._tweak_table == "tank_mini"
						local other_dozer_types = u_data.unit:base():has_tag("tank") and not u_data.unit:base():has_tag("medic") and not u_data.unit:base()._tweak_table == "tank_mini"
						local taser_type = u_data.unit:base():has_tag("taser")
						local captain = u_data.unit:base()._tweak_table == "phalanx_vip" and alive(managers.groupai:state():phalanx_vip())
						local other_shields = u_data.unit:base():has_tag("shield") and not u_data.unit:base()._tweak_table == "phalanx_vip"
						local sniper_type = u_data.unit:base():has_tag("sniper")

						local priority = (cloaker_type or taser_type) and 200 or medic_type and 150 and minigun_dozer and 100 or other_dozer_types and 75 or captain and 50 or other_shields and 25 or 10

						self:_add_unit_to_char_table(char_table, u_data.unit, unit_type_enemy, highlight_range * (sniper_type and 3 or 1), false, false, priority, my_head_pos, cam_fwd)
					end
				end
			end
		end
	end

	if intimidate_civilians then
		local civilians = managers.enemy:all_civilians()

		for u_key, u_data in pairs(civilians) do
			if alive(u_data.unit) and u_data.unit:in_slot(21) and not u_data.unit:movement():cool() and not u_data.unit:anim_data().long_dis_interact_disabled then
				local is_escort = u_data.char_tweak.is_escort

				if not is_escort or intimidate_escorts then
					local dist = is_escort and 300 or intimidate_range_civ
					local prio = is_escort and 100000 or 0.001

					if not (u_data.unit:anim_data().drop and u_data.is_tied) then
						self:_add_unit_to_char_table(char_table, u_data.unit, unit_type_civilian, dist, false, false, prio, my_head_pos, cam_fwd)
					end
				end
			end
		end
	end

	if intimidate_teammates then
		local criminals = managers.groupai:state():all_char_criminals()

		if managers.groupai:state():whisper_mode() then
			for u_key, u_data in pairs(criminals) do
				local added = nil

				if u_key ~= self._unit:key() then
					local rally_skill_data = self._ext_movement:rally_skill_data()

					if rally_skill_data and rally_skill_data.long_dis_revive and mvector3.distance_sq(self._pos, u_data.m_pos) < rally_skill_data.range_sq then
						local needs_revive = nil

						if u_data.unit:base().is_husk_player then
							needs_revive = u_data.unit:interaction():active() and u_data.unit:movement():need_revive() and u_data.unit:movement():current_state_name() ~= "arrested"
						else
							needs_revive = u_data.unit:character_damage():need_revive()
						end

						if needs_revive then
							if managers.player:has_enabled_cooldown_upgrade("cooldown", "long_dis_revive") then
								added = true
							end
						end
					end
				end

				if not added and not u_data.is_deployable and not u_data.unit:movement():downed() and not u_data.unit:base().is_local_player and not u_data.unit:anim_data().long_dis_interact_disabled then
					if secondary then
						if not u_data.unit:base().is_husk_player and not u_data.unit:movement():cool() and not u_data.unit:movement()._should_stay then
							self:_add_unit_to_char_table(char_table, u_data.unit, unit_type_teammate, intimidate_range_teammates, true, false, 0.01, my_head_pos, cam_fwd)
						end
					else
						if not u_data.unit:base().is_husk_player and not u_data.unit:movement():cool() then
							self:_add_unit_to_char_table(char_table, u_data.unit, unit_type_teammate, intimidate_range_teammates, true, true, 0.01, my_head_pos, cam_fwd)
						end
					end
				end
			end
		else
			for u_key, u_data in pairs(criminals) do
				local added = nil

				if u_key ~= self._unit:key() then
					local rally_skill_data = self._ext_movement:rally_skill_data()

					if rally_skill_data and rally_skill_data.long_dis_revive and mvector3.distance_sq(self._pos, u_data.m_pos) < rally_skill_data.range_sq then
						local needs_revive = nil

						if u_data.unit:base().is_husk_player then
							needs_revive = u_data.unit:interaction():active() and u_data.unit:movement():need_revive() and u_data.unit:movement():current_state_name() ~= "arrested"
						else
							needs_revive = u_data.unit:character_damage():need_revive()
						end

						if needs_revive then
							if managers.player:has_enabled_cooldown_upgrade("cooldown", "long_dis_revive") then
								added = true

								self:_add_unit_to_char_table(char_table, u_data.unit, unit_type_teammate, intimidate_range_teammates, true, true, 5000, my_head_pos, cam_fwd)
							end
						end
					end
				end

				if not added and not u_data.is_deployable and not u_data.unit:movement():downed() and not u_data.unit:base().is_local_player and not u_data.unit:anim_data().long_dis_interact_disabled then
					if secondary then
						if not u_data.unit:base().is_husk_player and not u_data.unit:movement()._should_stay then
							self:_add_unit_to_char_table(char_table, u_data.unit, unit_type_teammate, intimidate_range_teammates, true, false, 0.01, my_head_pos, cam_fwd)
						end
					else
						self:_add_unit_to_char_table(char_table, u_data.unit, unit_type_teammate, intimidate_range_teammates, true, true, 0.01, my_head_pos, cam_fwd)
					end
				end
			end
		end
	end

	if intimidate_enemies and intimidate_teammates then
		local enemies = managers.enemy:all_enemies()

		for u_key, u_data in pairs(enemies) do
			if u_data.unit:movement():team() and u_data.unit:movement():team().id == "criminal1" and not u_data.unit:movement():cool() and not u_data.unit:anim_data().long_dis_interact_disabled then
				local is_escort = u_data.char_tweak.is_escort

				if not is_escort or intimidate_escorts then
					local dist = is_escort and 300 or intimidate_range_civ
					local prio = is_escort and 100000 or 0.001

					self:_add_unit_to_char_table(char_table, u_data.unit, unit_type_civilian, dist, false, false, prio, my_head_pos, cam_fwd)
				end
			end
		end
	end

	if intimidate_enemies then
		if managers.groupai:state():whisper_mode() then
			for _, unit in ipairs(SecurityCamera.cameras) do
				if alive(unit) and unit:enabled() and not unit:base():destroyed() and (unit:interaction() and unit:interaction():active() and not unit:interaction():disabled() or unit:base().is_friendly) then --apparently friendly means drones, I don't even (the one in Sosa's mansion won't be marked as it's not enabled)
					local dist = 2000
					local prio = 0.001

					self:_add_unit_to_char_table(char_table, unit, unit_type_camera, dist, false, false, prio, my_head_pos, cam_fwd, {
						unit
					})
				end
			end
		end

		local turret_units = managers.groupai:state():turrets()

		if turret_units then
			for _, unit in pairs(turret_units) do
				if alive(unit) and unit:movement():team().foes[self._ext_movement:team().id] then
					self:_add_unit_to_char_table(char_table, unit, unit_type_turret, 2000, false, false, 0.01, my_head_pos, cam_fwd, {
						unit
					})
				end
			end
		end
	end

	local prime_target = self:_get_interaction_target(char_table, my_head_pos, cam_fwd)

	return self:_get_intimidation_action(prime_target, char_table, intimidation_amount, primary_only, detect_only, secondary)
end

function PlayerStandard:calculate_melee_crit(melee_entry)
	local crit_value = managers.player:critical_hit_chance()
	
	if tweak_data.blackmarket.melee_weapons[melee_entry].base_crit then
		crit_value = crit_value + tweak_data.blackmarket.melee_weapons[melee_entry].base_crit --a little bonus if we ever want this.
	end
	
	local critical_roll = math.rand(1)
	critical_hit = critical_roll < crit_value
	
	return critical_hit
end

function PlayerStandard:_get_max_walk_speed(t, force_run)
	local speed_tweak = self._tweak_data.movement.speed
	local movement_speed = speed_tweak.STANDARD_MAX
	local speed_state = "walk"

	if self._state_data.in_steelsight and not managers.player:has_category_upgrade("player", "steelsight_normal_movement_speed") and not _G.IS_VR then
		movement_speed = speed_tweak.STEELSIGHT_MAX
		speed_state = "steelsight"
	elseif self:on_ladder() then
		movement_speed = speed_tweak.CLIMBING_MAX
		speed_state = "climb"
	elseif self._state_data.ducking then
		if not managers.player:has_category_upgrade("player","leg_day_aced") then 
			movement_speed = speed_tweak.CROUCHING_MAX
			speed_state = "crouch"
		end
	elseif self._state_data.in_air then
		movement_speed = speed_tweak.INAIR_MAX
		speed_state = nil
	elseif self._running or force_run then
		movement_speed = speed_tweak.RUNNING_MAX
		speed_state = "run"
	end

	movement_speed = managers.modifiers:modify_value("PlayerStandard:GetMaxWalkSpeed", movement_speed, self._state_data, speed_tweak)
	local morale_boost_bonus = self._ext_movement:morale_boost()
	local multiplier = managers.player:movement_speed_multiplier(speed_state, speed_state and morale_boost_bonus and morale_boost_bonus.move_speed_bonus, nil, self._ext_damage:health_ratio())
	multiplier = multiplier * (self._tweak_data.movement.multiplier[speed_state] or 1)
	local apply_weapon_penalty = true

	if self:_is_meleeing() then
		local melee_entry = managers.blackmarket:equipped_melee_weapon()
		apply_weapon_penalty = not tweak_data.blackmarket.melee_weapons[melee_entry].stats.remove_weapon_movement_penalty
	end

	if alive(self._equipped_unit) and apply_weapon_penalty then
		multiplier = multiplier * self._equipped_unit:base():movement_penalty()
	end

	if managers.player:has_activate_temporary_upgrade("temporary", "increased_movement_speed") then
		multiplier = multiplier * managers.player:temporary_upgrade_value("temporary", "increased_movement_speed", 1)
	end

	local final_speed = movement_speed * multiplier

	return final_speed
end

local mvec_pos_new = Vector3()
local mvec_achieved_walk_vel = Vector3()
local mvec_move_dir_normalized = Vector3()

function PlayerStandard:_update_movement(t, dt)
	local anim_data = self._unit:anim_data()
	local weapon_id = alive(self._equipped_unit) and self._equipped_unit:base() and self._equipped_unit:base():get_name_id()
	local weapon_tweak_data = weapon_id and tweak_data.weapon[weapon_id]
	local pos_new = nil
	self._target_headbob = self._target_headbob or 0
	self._headbob = self._headbob or 0
	
	local WALK_SPEED_MAX = self:_get_max_walk_speed(t)
	
	self._cached_final_speed = self._cached_final_speed or 0

	if WALK_SPEED_MAX ~= self._cached_final_speed then
		self._cached_final_speed = WALK_SPEED_MAX

		self._ext_network:send("action_change_speed", WALK_SPEED_MAX)
	end

	if self._state_data.on_zipline and self._state_data.zipline_data.position then
		local speed = mvector3.length(self._state_data.zipline_data.position - self._pos) / dt / 500
		pos_new = mvec_pos_new

		mvector3.set(pos_new, self._state_data.zipline_data.position)

		if self._state_data.zipline_data.camera_shake then
			self._ext_camera:shaker():set_parameter(self._state_data.zipline_data.camera_shake, "amplitude", speed)
		end

		if alive(self._state_data.zipline_data.zipline_unit) then
			local dot = mvector3.dot(self._ext_camera:rotation():x(), self._state_data.zipline_data.zipline_unit:zipline():current_direction())

			self._ext_camera:camera_unit():base():set_target_tilt(dot * 10 * speed)
		end

		self._target_headbob = 0
	elseif self._move_dir then
		local enter_moving = not self._moving
		self._moving = true

		if enter_moving then
			self._last_sent_pos_t = t

			self:_update_crosshair_offset()
		end

		mvector3.set(mvec_move_dir_normalized, self._move_dir)
		mvector3.normalize(mvec_move_dir_normalized)

		local wanted_walk_speed = WALK_SPEED_MAX * math.min(1, self._move_dir:length())
		local acceleration = self._state_data.in_air and 700 or self._running and 5000 or 3000
		local achieved_walk_vel = mvec_achieved_walk_vel

		if self._jump_vel_xy and self._state_data.in_air and mvector3.dot(self._jump_vel_xy, self._last_velocity_xy) > 0 then
			local input_move_vec = wanted_walk_speed * self._move_dir
			local jump_dir = mvector3.copy(self._last_velocity_xy)
			local jump_vel = mvector3.normalize(jump_dir)
			local fwd_dot = jump_dir:dot(input_move_vec)

			if fwd_dot < jump_vel then
				local sustain_dot = (input_move_vec:normalized() * jump_vel):dot(jump_dir)
				local new_move_vec = input_move_vec + jump_dir * (sustain_dot - fwd_dot)

				mvector3.step(achieved_walk_vel, self._last_velocity_xy, new_move_vec, 700 * dt)
			else
				mvector3.multiply(mvec_move_dir_normalized, wanted_walk_speed)
				mvector3.step(achieved_walk_vel, self._last_velocity_xy, wanted_walk_speed * self._move_dir:normalized(), acceleration * dt)
			end

			local fwd_component = nil
		else
			mvector3.multiply(mvec_move_dir_normalized, wanted_walk_speed)
			mvector3.step(achieved_walk_vel, self._last_velocity_xy, mvec_move_dir_normalized, acceleration * dt)
		end

		if mvector3.is_zero(self._last_velocity_xy) then
			mvector3.set_length(achieved_walk_vel, math.max(achieved_walk_vel:length(), 100))
		end

		pos_new = mvec_pos_new

		mvector3.set(pos_new, achieved_walk_vel)
		mvector3.multiply(pos_new, dt)
		mvector3.add(pos_new, self._pos)

		self._target_headbob = self:_get_walk_headbob()
		self._target_headbob = self._target_headbob * self._move_dir:length()

		if weapon_tweak_data and weapon_tweak_data.headbob and weapon_tweak_data.headbob.multiplier then
			self._target_headbob = self._target_headbob * weapon_tweak_data.headbob.multiplier
		end
	elseif not mvector3.is_zero(self._last_velocity_xy) then
		local decceleration = self._state_data.in_air and 250 or math.lerp(2000, 1500, math.min(self._last_velocity_xy:length() / tweak_data.player.movement_state.standard.movement.speed.RUNNING_MAX, 1))
		local achieved_walk_vel = math.step(self._last_velocity_xy, Vector3(), decceleration * dt)
		pos_new = mvec_pos_new

		mvector3.set(pos_new, achieved_walk_vel)
		mvector3.multiply(pos_new, dt)
		mvector3.add(pos_new, self._pos)

		self._target_headbob = 0
	elseif self._moving then
		self._target_headbob = 0
		self._moving = false

		self:_update_crosshair_offset()
	end

	if self._headbob ~= self._target_headbob then
		local ratio = 4

		if weapon_tweak_data and weapon_tweak_data.headbob and weapon_tweak_data.headbob.speed_ratio then
			ratio = weapon_tweak_data.headbob.speed_ratio
		end

		self._headbob = math.step(self._headbob, self._target_headbob, dt / ratio)

		self._ext_camera:set_shaker_parameter("headbob", "amplitude", self._headbob)
	end

	local ground_z = self:_chk_floor_moving_pos()

	if ground_z and not self._is_jumping then
		if not pos_new then
			pos_new = mvec_pos_new

			mvector3.set(pos_new, self._pos)
		end

		mvector3.set_z(pos_new, ground_z)
	end

	if pos_new then
		self._unit:movement():set_position(pos_new)
		mvector3.set(self._last_velocity_xy, pos_new)
		mvector3.subtract(self._last_velocity_xy, self._pos)

		if not self._state_data.on_ladder and not self._state_data.on_zipline then
			mvector3.set_z(self._last_velocity_xy, 0)
		end

		mvector3.divide(self._last_velocity_xy, dt)
	else
		mvector3.set_static(self._last_velocity_xy, 0, 0, 0)
	end

	local cur_pos = pos_new or self._pos

	self:_update_network_jump(cur_pos, false)
	self:_update_network_position(t, dt, cur_pos, pos_new)
end

Hooks:Register("OnPlayerMeleeHit")
local melee_vars = {
	"player_melee",
	"player_melee_var2"
}
function PlayerStandard:_do_melee_damage(t, bayonet_melee, melee_hit_ray, melee_entry, hand_id, force_max_charge)
	melee_entry = melee_entry or managers.blackmarket:equipped_melee_weapon()
	local melee_td = tweak_data.blackmarket.melee_weapons[melee_entry]
	local instant_hit = melee_td.instant
	local melee_damage_delay = melee_td.melee_damage_delay or 0
	local charge_lerp_value = instant_hit and 0 or force_max_charge and 1 or self:_get_melee_charge_lerp_value(t, melee_damage_delay)

	self._ext_camera:play_shaker(melee_vars[math.random(#melee_vars)], math.max(0.3, charge_lerp_value))

	local sphere_cast_radius = 20
	local col_ray = nil

	if melee_hit_ray then
		col_ray = melee_hit_ray ~= true and melee_hit_ray or nil
	else
		col_ray = self:_calc_melee_hit_ray(t, sphere_cast_radius)
	end

	if col_ray and alive(col_ray.unit) then
		local damage, damage_effect = managers.blackmarket:equipped_melee_weapon_damage_info(charge_lerp_value)
		local damage_effect_mul = math.max(managers.player:upgrade_value("player", "melee_knockdown_mul", 1), managers.player:upgrade_value(self._equipped_unit:base():weapon_tweak_data().categories and self._equipped_unit:base():weapon_tweak_data().categories[1], "melee_knockdown_mul", 1))
		damage = damage * managers.player:get_melee_dmg_multiplier()
--		if mark_enemy_on_hit then 
		if melee_td.random_damage_mul then 
			--because the above function is probably meant to be a constant, 
			--calculate random damage multiplier here (currently only used by jackpot lever)
			damage = damage * melee_td.random_damage_mul[#melee_td.random_damage_mul]
		end

		
		damage_effect = damage_effect * damage_effect_mul
		col_ray.sphere_cast_radius = sphere_cast_radius
		local hit_unit = col_ray.unit

		if hit_unit:character_damage() then
			if bayonet_melee then
				self._unit:sound():play("fairbairn_hit_body", nil, false)
			else
				local hit_sfx = "hit_body"

				if hit_unit:character_damage() and hit_unit:character_damage().melee_hit_sfx then
					hit_sfx = hit_unit:character_damage():melee_hit_sfx()
				end

				self:_play_melee_sound(melee_entry, hit_sfx, self._melee_attack_var)
			end

			if not hit_unit:character_damage()._no_blood then
				managers.game_play_central:play_impact_flesh({
					col_ray = col_ray
				})
				managers.game_play_central:play_impact_sound_and_effects({
					no_decal = true,
					no_sound = true,
					col_ray = col_ray
				})
			end

			self._camera_unit:base():play_anim_melee_item("hit_body")
		elseif self._on_melee_restart_drill and hit_unit:base() and (hit_unit:base().is_drill or hit_unit:base().is_saw) then
			hit_unit:base():on_melee_hit(managers.network:session():local_peer():id())
		else
			if bayonet_melee then
				self._unit:sound():play("knife_hit_gen", nil, false)
			else
				self:_play_melee_sound(melee_entry, "hit_gen", self._melee_attack_var)
			end

			self._camera_unit:base():play_anim_melee_item("hit_gen")
			managers.game_play_central:play_impact_sound_and_effects({
				no_decal = true,
				no_sound = true,
				col_ray = col_ray,
				effect = Idstring("effects/payday2/particles/impacts/fallback_impact_pd2")
			})
		end

		local custom_data = nil

		if _G.IS_VR and hand_id then
			custom_data = {
				engine = hand_id == 1 and "right" or "left"
			}
		end

		managers.rumble:play("melee_hit", nil, nil, custom_data)
		managers.game_play_central:physics_push(col_ray)
		local character_unit, shield_knock = nil
		local can_shield_knock = managers.player:has_category_upgrade("player", "shield_knock")

		if can_shield_knock and hit_unit:in_slot(8) and alive(hit_unit:parent()) and not hit_unit:parent():character_damage():is_immune_to_shield_knockback() then
			shield_knock = true
			character_unit = hit_unit:parent()
		end

		character_unit = character_unit or hit_unit
		local target_is_civilian = managers.enemy:is_civilian(character_unit)

		if character_unit:character_damage() and character_unit:character_damage().damage_melee then
			local dmg_multiplier = 1

			dmg_multiplier = dmg_multiplier + managers.player:upgrade_value("class_melee","weapon_class_damage_mul",0)
			local stacking_deck_add_mul = managers.player:get_temporary_property("shuffle_cut_melee_bonus_damage",0)

			dmg_multiplier = dmg_multiplier + stacking_deck_add_mul
			
			if not target_is_civilian and not managers.groupai:state():is_enemy_special(character_unit) then
				dmg_multiplier = dmg_multiplier * managers.player:upgrade_value("player", "non_special_melee_multiplier", 1)
			else
				dmg_multiplier = dmg_multiplier * managers.player:upgrade_value("player", "melee_damage_multiplier", 1)
			end

			dmg_multiplier = dmg_multiplier * managers.player:upgrade_value("player", "melee_" .. tostring(melee_td.stats.weapon_type) .. "_damage_multiplier", 1)

			
			if managers.player:has_category_upgrade("melee", "stacking_hit_damage_multiplier") then
				self._state_data.stacking_dmg_mul = self._state_data.stacking_dmg_mul or {}
				self._state_data.stacking_dmg_mul.melee = self._state_data.stacking_dmg_mul.melee or {
					nil,
					0
				}
				local stack = self._state_data.stacking_dmg_mul.melee

				if stack[1] and t < stack[1] then
					dmg_multiplier = dmg_multiplier * (1 + managers.player:upgrade_value("melee", "stacking_hit_damage_multiplier", 0) * stack[2])
				else
					stack[2] = 0
				end
			end

			local health_ratio = self._ext_damage:health_ratio()
			local damage_health_ratio = managers.player:get_damage_health_ratio(health_ratio, "melee")

			if damage_health_ratio > 0 then
				local damage_ratio = damage_health_ratio
				dmg_multiplier = dmg_multiplier * (1 + managers.player:upgrade_value("player", "melee_damage_health_ratio_multiplier", 0) * damage_ratio)
			end

			dmg_multiplier = dmg_multiplier * managers.player:temporary_upgrade_value("temporary", "berserker_damage_multiplier", 1)
			local target_dead = character_unit:character_damage().dead and not character_unit:character_damage():dead()
			local target_hostile = managers.enemy:is_enemy(character_unit) and not tweak_data.character[character_unit:base()._tweak_table].is_escort and character_unit:brain():is_hostile()
			local life_leach_available = managers.player:has_category_upgrade("temporary", "melee_life_leech") and not managers.player:has_activate_temporary_upgrade("temporary", "melee_life_leech")

			if target_dead and target_hostile and life_leach_available then
				managers.player:activate_temporary_upgrade("temporary", "melee_life_leech")
				self._unit:character_damage():restore_health(managers.player:temporary_upgrade_value("temporary", "melee_life_leech", 1))
			end

			local special_weapon = melee_td.special_weapon
			local action_data = {
				variant = "melee",
			}
			if melee_td.stats.knockback_tier then 
				local knockback_tier = melee_td.stats.knockback_tier
				if melee_td.random_knockback_tier then 
					knockback_tier = CopDamage.melee_knockback_tiers[math.random(#CopDamage.melee_knockback_tiers)]
				end
				action_data.knockback_tier = knockback_tier + math.floor(charge_lerp_value) + managers.player:upgrade_value("class_melee","knockdown_tier_increase",0) --only used in tcd
			end
			
			if special_weapon == "taser" then
				action_data.variant = "taser_tased"
			end

			if _G.IS_VR and melee_entry == "weapon" and not bayonet_melee then
				dmg_multiplier = 0.1
			end

			action_data.damage = shield_knock and 0 or damage * dmg_multiplier
			action_data.damage_effect = damage_effect
			action_data.attacker_unit = self._unit
			action_data.col_ray = col_ray
			action_data.critical_hit = self:calculate_melee_crit(melee_entry)

			if shield_knock then
				action_data.shield_knock = can_shield_knock
			end

			action_data.name_id = melee_entry
			action_data.charge_lerp_value = charge_lerp_value

			if managers.player:has_category_upgrade("melee", "stacking_hit_damage_multiplier") then
				self._state_data.stacking_dmg_mul = self._state_data.stacking_dmg_mul or {}
				self._state_data.stacking_dmg_mul.melee = self._state_data.stacking_dmg_mul.melee or {
					nil,
					0
				}
				local stack = self._state_data.stacking_dmg_mul.melee

				if character_unit:character_damage().dead and not character_unit:character_damage():dead() then
					stack[1] = t + managers.player:upgrade_value("melee", "stacking_hit_expire_t", 1)
					stack[2] = math.min(stack[2] + 1, tweak_data.upgrades.max_melee_weapon_dmg_mul_stacks or 5)
				else
					stack[1] = nil
					stack[2] = 0
				end
			end
			if not character_unit:character_damage():dead() then 
				Hooks:Call("OnPlayerMeleeHit",character_unit,col_ray,action_data,defense_data,t)
			end
			local defense_data = character_unit:character_damage():damage_melee(action_data)

			self:_check_melee_dot_damage(col_ray, defense_data, melee_entry)
			self:_perform_sync_melee_damage(hit_unit, col_ray, action_data.damage)
			
			
			return defense_data
		else
			self:_perform_sync_melee_damage(hit_unit, col_ray, damage)
		end
	end

	if managers.player:has_category_upgrade("melee", "stacking_hit_damage_multiplier") then
		self._state_data.stacking_dmg_mul = self._state_data.stacking_dmg_mul or {}
		self._state_data.stacking_dmg_mul.melee = self._state_data.stacking_dmg_mul.melee or {
			nil,
			0
		}
		local stack = self._state_data.stacking_dmg_mul.melee
		stack[1] = nil
		stack[2] = 0
	end
	
	return col_ray
end

Hooks:PostHook(PlayerStandard,"_interupt_action_reload","totalcrackdown_interrupt_reload",function(self,t)
	managers.player:set_property("shell_games_rounds_loaded",0)
end)

Hooks:Register("OnPlayerReloadComplete")
function PlayerStandard:_update_reload_timers(t, dt, input)
	if self._state_data.reload_enter_expire_t and self._state_data.reload_enter_expire_t <= t then
		self._state_data.reload_enter_expire_t = nil

		self:_start_action_reload(t)
	end

	if self._state_data.reload_expire_t then
		local loaded_shell,interupt = self._equipped_unit:base():update_reloading(t, dt, self._state_data.reload_expire_t - t) 
		if loaded_shell then 
		--the sole change here from cd is to prematurely exit the reload animation if the gun finishes loading before the animation does
		--this is really just an issue in shotgun reloads with the shell games skill, since 
		--ovk made it REALLY DIFFICULT to change reload speed for shotgun reloads specifically.
		--thanks FPCameraPlayerBase:enter_shotgun_reload_loop()
			managers.hud:set_ammo_amount(self._equipped_unit:base():selection_index(), self._equipped_unit:base():ammo_info())

			if self._queue_reload_interupt then
				self._queue_reload_interupt = nil
				interupt = true
			end
		end

		if self._state_data.reload_expire_t <= t or interupt then
			managers.player:remove_property("shock_and_awe_reload_multiplier")

			self._state_data.reload_expire_t = nil

			if self._equipped_unit:base():reload_exit_expire_t() then
				local speed_multiplier = self._equipped_unit:base():reload_speed_multiplier()

				if self._equipped_unit:base():started_reload_empty() then
					self._state_data.reload_exit_expire_t = t + self._equipped_unit:base():reload_exit_expire_t() / speed_multiplier

					self._ext_camera:play_redirect(self:get_animation("reload_exit"), speed_multiplier)
					self._equipped_unit:base():tweak_data_anim_play("reload_exit", speed_multiplier)
				else
					self._state_data.reload_exit_expire_t = t + self._equipped_unit:base():reload_not_empty_exit_expire_t() / speed_multiplier

					self._ext_camera:play_redirect(self:get_animation("reload_not_empty_exit"), speed_multiplier)
					self._equipped_unit:base():tweak_data_anim_play("reload_not_empty_exit", speed_multiplier)
				end
			elseif self._equipped_unit then
				if not interupt then
					self._equipped_unit:base():on_reload()
					Hooks:Call("OnPlayerReloadComplete",self._equipped_unit)
				end

				managers.statistics:reloaded()
				managers.hud:set_ammo_amount(self._equipped_unit:base():selection_index(), self._equipped_unit:base():ammo_info())

				if input.btn_steelsight_state then
					self._steelsight_wanted = true
				elseif self.RUN_AND_RELOAD and self._running and not self._end_running_expire_t and not self._equipped_unit:base():run_and_shoot_allowed() then
					self._ext_camera:play_redirect(self:get_animation("start_running"))
				end
			end
		end
	end

	if self._state_data.reload_exit_expire_t and self._state_data.reload_exit_expire_t <= t then
		self._state_data.reload_exit_expire_t = nil

		if self._equipped_unit then
			managers.statistics:reloaded()
			managers.hud:set_ammo_amount(self._equipped_unit:base():selection_index(), self._equipped_unit:base():ammo_info())

			if input.btn_steelsight_state then
				self._steelsight_wanted = true
			elseif self.RUN_AND_RELOAD and self._running and not self._end_running_expire_t and not self._equipped_unit:base():run_and_shoot_allowed() then
				self._ext_camera:play_redirect(self:get_animation("start_running"))
			end

			if self._equipped_unit:base().on_reload_stop then
				self._equipped_unit:base():on_reload_stop()
			end
		end
	end
end

if deathvox:IsTotalCrackdownEnabled() then 

	function PlayerStandard:_do_action_throw_projectile(t, input, drop_projectile)
		local current_state_name = self._camera_unit:anim_state_machine():segment_state(self:get_animation("base"))
		self._state_data.throwing_projectile = nil
		local projectile_entry = managers.blackmarket:equipped_projectile()
		local projectile_data = tweak_data.blackmarket.projectiles[projectile_entry]
		self._state_data.projectile_expire_t = t + projectile_data.expire_t
		self._state_data.projectile_repeat_expire_t = t + math.min(projectile_data.repeat_expire_t, projectile_data.expire_t)

		managers.network:session():send_to_peers_synched("play_distance_interact_redirect", self._unit, "throw_grenade")

		self._state_data.projectile_global_value = projectile_data.anim_global_param or "projectile_frag"

		self._camera_unit:anim_state_machine():set_global(self._state_data.projectile_global_value, 1)
		self._ext_camera:play_redirect(self:get_animation("projectile_throw"))
		self:_stance_entered()
		
		if managers.player:has_category_upgrade("class_throwing","projectile_charged_damage_mul") then 
			local held_time = self._state_data.projectile_start_t and (t - self._state_data.projectile_start_t)
			local charge_time_threshold,damage_mul_addend = unpack(managers.player:upgrade_value("class_throwing","projectile_charged_damage_mul",{math.huge,0}))
			if held_time and held_time >= charge_time_threshold then 
				managers.player:set_property("charged_throwable_damage_bonus",damage_mul_addend)
			end
		end
	end
	
	function PlayerStandard:_get_melee_charge_lerp_value(t, offset)
		offset = offset or 0
		local melee_entry = managers.blackmarket:equipped_melee_weapon()
		local max_charge_time = tweak_data.blackmarket.melee_weapons[melee_entry].stats.charge_time / (1 + managers.player:upgrade_value("class_melee","melee_charge_speed_mul",0))

		if not self._state_data.melee_start_t then
			return 0
		end
		
		return math.clamp(t - self._state_data.melee_start_t - offset, 0, max_charge_time) / max_charge_time
	end

	Hooks:PreHook(PlayerStandard,"_check_action_interact","totalcrackdown_sentry_checkclosemenu",function(self,t, input)
		--if tcd's sentry control menu is open, close it when interact button is pressed again
		--also, conditionally select mode (same as left-clicking any option) if settings and holding allow
		
		if input.btn_interact_release then 
			if TripmineControlMenu.action_radial and TripmineControlMenu.action_radial:active() and TripmineControlMenu.interacted_radial_start_t then
				if TripmineControlMenu.interacted_radial_start_t + SentryControlMenu:GetMenuButtonHoldThreshold() < t then 
					local allow_selection = TripmineControlMenu.button_held_state
					TripmineControlMenu.action_radial:Hide(nil,allow_selection)
					
					TripmineControlMenu.interacted_radial_start_t = nil
				else
					if TripmineControlMenu.button_held_state == nil then 
						TripmineControlMenu.button_held_state = true
						return
					elseif TripmineControlMenu.button_held_state == true then 
						TripmineControlMenu.button_held_state = false
					end
				end
			end
		end
	end)

--these four functions are only changed to allow sprinting while meleeing and prevent animation breaking from doing those things i just said
	function PlayerStandard:_start_action_melee(t, input, instant)
		self._equipped_unit:base():tweak_data_anim_stop("fire")
		self:_interupt_action_reload(t)
		self:_interupt_action_steelsight(t)
		
		if not managers.player:has_category_upgrade("player","can_melee_and_sprint") then
			self:_interupt_action_running(t)
		end
		
		self:_interupt_action_charging_weapon(t)

		self._state_data.melee_charge_wanted = nil
		self._state_data.meleeing = true
		self._state_data.melee_start_t = nil
		local melee_entry = managers.blackmarket:equipped_melee_weapon()
		local primary = managers.blackmarket:equipped_primary()
		local primary_id = primary.weapon_id
		local bayonet_id = managers.blackmarket:equipped_bayonet(primary_id)
		local bayonet_melee = false

		if bayonet_id and melee_entry == "weapon" and self._equipped_unit:base():selection_index() == 2 then
			bayonet_melee = true
		end

		if instant then
			self:_do_action_melee(t, input)

			return
		end
		
		managers.player._melee_stance_dr_t = t + 5

		self:_stance_entered()

		if self._state_data.melee_global_value then
			self._camera_unit:anim_state_machine():set_global(self._state_data.melee_global_value, 0)
		end

		local melee_entry = managers.blackmarket:equipped_melee_weapon()
		self._state_data.melee_global_value = tweak_data.blackmarket.melee_weapons[melee_entry].anim_global_param

		self._camera_unit:anim_state_machine():set_global(self._state_data.melee_global_value, 1)

		local current_state_name = self._camera_unit:anim_state_machine():segment_state(self:get_animation("base"))
		local attack_allowed_expire_t = tweak_data.blackmarket.melee_weapons[melee_entry].attack_allowed_expire_t or 0.15
		self._state_data.melee_attack_allowed_t = t + (current_state_name ~= self:get_animation("melee_attack_state") and attack_allowed_expire_t or 0)
		local instant_hit = tweak_data.blackmarket.melee_weapons[melee_entry].instant

		if not instant_hit then
			self._ext_network:send("sync_melee_start", 0)
		end

		if current_state_name == self:get_animation("melee_attack_state") then
			self._ext_camera:play_redirect(self:get_animation("melee_charge"))

			return
		end

		local offset = nil

		if current_state_name == self:get_animation("melee_exit_state") then
			local segment_relative_time = self._camera_unit:anim_state_machine():segment_relative_time(self:get_animation("base"))
			offset = (1 - segment_relative_time) * 0.9
		end

		offset = math.max(offset or 0, attack_allowed_expire_t)

		self._ext_camera:play_redirect(self:get_animation("melee_enter"), nil, offset)
	end
	
	function PlayerStandard:_start_action_unequip_weapon(t, data)
		local speed_multiplier = self:_get_swap_speed_multiplier()

		self._equipped_unit:base():tweak_data_anim_stop("equip")
		self._equipped_unit:base():tweak_data_anim_play("unequip", speed_multiplier)

		local tweak_data = self._equipped_unit:base():weapon_tweak_data()
		self._change_weapon_data = data
		self._unequip_weapon_expire_t = t + (tweak_data.timers.unequip or 0.5) / speed_multiplier

		self:_interupt_action_charging_weapon(t)

		local result = self._ext_camera:play_redirect(self:get_animation("unequip"), speed_multiplier)

		self:_interupt_action_reload(t)
		self:_interupt_action_steelsight(t)
		self._ext_network:send("switch_weapon", speed_multiplier, 1)
	end

	function PlayerStandard:_start_action_running(t)
		if not self._move_dir then
			self._running_wanted = true

			return
		end

		if self:on_ladder() or self:_on_zipline() then
			return
		end
		local is_meleeing = self:_is_meleeing()
		if is_meleeing and not managers.player:has_category_upgrade("player","can_melee_and_sprint") then 
			return
		end

		if self._shooting and not self._equipped_unit:base():run_and_shoot_allowed() or self._use_item_expire_t or self._state_data.in_air or self:_is_throwing_projectile() or self:_is_charging_weapon() then
			self._running_wanted = true

			return
		end

		if self._state_data.ducking and not self:_can_stand() then
			self._running_wanted = true

			return
		end

		if not self:_can_run_directional() then
			return
		end

		self._running_wanted = false

		if managers.player:get_player_rule("no_run") then
			return
		end

		if not self._unit:movement():is_above_stamina_threshold() then
			return
		end

		if (not self._state_data.shake_player_start_running or not self._ext_camera:shaker():is_playing(self._state_data.shake_player_start_running)) and managers.user:get_setting("use_headbob") then
			self._state_data.shake_player_start_running = self._ext_camera:play_shaker("player_start_running", 0.75)
		end

		self:set_running(true)

		self._end_running_expire_t = nil
		self._start_running_t = t
		self._play_stop_running_anim = nil

		if not is_meleeing and (not self:_is_reloading() or not self.RUN_AND_RELOAD) then
			if not self._equipped_unit:base():run_and_shoot_allowed() then
				self._ext_camera:play_redirect(self:get_animation("start_running"))
			else
				self._ext_camera:play_redirect(self:get_animation("idle"))
			end
		end

		if not self.RUN_AND_RELOAD then
			self:_interupt_action_reload(t)
		end

		self:_interupt_action_steelsight(t)
		self:_interupt_action_ducking(t)
	end
	
	function PlayerStandard:_end_action_running(t)
		if not self._end_running_expire_t then
			local speed_multiplier = self._equipped_unit:base():exit_run_speed_multiplier()
			self._end_running_expire_t = t + 0.4 / speed_multiplier
			local stop_running = not self._equipped_unit:base():run_and_shoot_allowed() and (not self.RUN_AND_RELOAD or not self:_is_reloading())

			if stop_running and not self:_is_meleeing() then
				self._ext_camera:play_redirect(self:get_animation("stop_running"), speed_multiplier)
			end
		end
	end	
	
	function PlayerStandard:_start_action_jump(t, action_start_data)
		if not self:_is_meleeing() and (self._running and not self.RUN_AND_RELOAD and not self._equipped_unit:base():run_and_shoot_allowed()) then
			self:_interupt_action_reload(t)
			self._ext_camera:play_redirect(self:get_animation("stop_running"), self._equipped_unit:base():exit_run_speed_multiplier())
		end

		self:_interupt_action_running(t)

		self._jump_t = t
		local jump_vec = action_start_data.jump_vel_z * math.UP

		self._unit:mover():jump()

		if self._move_dir then
			local move_dir_clamp = self._move_dir:normalized() * math.min(1, self._move_dir:length())
			self._last_velocity_xy = move_dir_clamp * action_start_data.jump_vel_xy
			self._jump_vel_xy = mvector3.copy(self._last_velocity_xy)
		else
			self._last_velocity_xy = Vector3()
		end

		self:_perform_jump(jump_vec)
	end

	function PlayerStandard:_update_use_item_timers(t, input)
		if self._use_item_expire_t then
			local valid,target_revive = managers.player:check_selected_equipment_placement_valid(self._unit)
			if target_revive and alive(target_revive) then 
				local teammate_name = "Teammate"
				local teammate_peer_id = managers.criminals:character_peer_id_by_unit(target_revive)
				local character_name = managers.criminals:character_name_by_unit(target_revive)
				teammate_name = (teammate_peer_id and managers.network:session():peer(teammate_peer_id):name()) or (character_name and managers.localization:text("menu_" .. character_name)) or teammate_name
				
				managers.hud:show_progress_timer({
					text = string.gsub(managers.localization:text("hud_deploying_revive_fak"),"$TEAMMATE_NAME",teammate_name)
				})
			else
				managers.hud:show_progress_timer({
					text = managers.player:selected_equipment_deploying_text() or managers.localization:text("hud_deploying_equipment", {
						EQUIPMENT = managers.player:selected_equipment_name()
					})
				})
			end
			
			local deploy_timer = managers.player:selected_equipment_deploy_timer()

			managers.hud:set_progress_timer_bar_valid(valid, not valid and "hud_deploy_valid_help")
			managers.hud:set_progress_timer_bar_width(deploy_timer - (self._use_item_expire_t - t), deploy_timer)

			if self._use_item_expire_t <= t then
				self:_end_action_use_item(valid)

				self._use_item_expire_t = nil
			end
		end
	end

	function PlayerStandard:_check_action_primary_attack(t, input) --TEMPORARY FIX, REMOVE WHEN CLAIRE AUTO ANIMS ARE ADDED
		local new_action = nil
		local action_wanted = input.btn_primary_attack_state or input.btn_primary_attack_release

		if action_wanted then
			local action_forbidden = self:_is_reloading() or self:_changing_weapon() or self:_is_meleeing() or self._use_item_expire_t or self:_interacting() or self:_is_throwing_projectile() or self:_is_deploying_bipod() or self._menu_closed_fire_cooldown > 0 or self:is_switching_stances()

			if not action_forbidden then
				self._queue_reload_interupt = nil
				local start_shooting = false

				self._ext_inventory:equip_selected_primary(false)

				if self._equipped_unit then
					local weap_base = self._equipped_unit:base()
					local fire_mode = weap_base:fire_mode()
					local fire_on_release = weap_base:fire_on_release()

					if weap_base:out_of_ammo() then
						if input.btn_primary_attack_press then
							weap_base:dryfire()
						end
					elseif weap_base.clip_empty and weap_base:clip_empty() then
						if self:_is_using_bipod() then
							if input.btn_primary_attack_press then
								weap_base:dryfire()
							end

							self._equipped_unit:base():tweak_data_anim_stop("fire")
						elseif fire_mode == "single" then
							if input.btn_primary_attack_press or self._equipped_unit:base().should_reload_immediately and self._equipped_unit:base():should_reload_immediately() then
								self:_start_action_reload_enter(t)
							end
						else
							new_action = true

							self:_start_action_reload_enter(t)
						end
					elseif self._running and not self._equipped_unit:base():run_and_shoot_allowed() then
						self:_interupt_action_running(t)
					else
						if not self._shooting then
							if weap_base:start_shooting_allowed() then
								local start = fire_mode == "single" and input.btn_primary_attack_press
								start = start or fire_mode ~= "single" and input.btn_primary_attack_state
								start = start and not fire_on_release
								start = start or fire_on_release and input.btn_primary_attack_release

								if start then
									weap_base:start_shooting()
									self._camera_unit:base():start_shooting()

									self._shooting = true
									self._shooting_t = t
									start_shooting = true

									if (fire_mode == "auto") and not (weap_base:is_weapon_class("class_shotgun") and managers.player:has_category_upgrade("class_shotgun","heartbreaker_doublebarrel") and weap_base:weapon_tweak_data().CLIP_AMMO_MAX == 2) then
										self._unit:camera():play_redirect(self:get_animation("recoil_enter"))

										if (not weap_base.akimbo or weap_base:weapon_tweak_data().allow_akimbo_autofire) and (not weap_base.third_person_important or weap_base.third_person_important and not weap_base:third_person_important()) then
											self._ext_network:send("sync_start_auto_fire_sound", 0)
										end
									end
								end
							else
								self:_check_stop_shooting()

								return false
							end
						end

						local suppression_ratio = self._unit:character_damage():effective_suppression_ratio()
						local spread_mul = math.lerp(1, tweak_data.player.suppression.spread_mul, suppression_ratio)
						local autohit_mul = math.lerp(1, tweak_data.player.suppression.autohit_chance_mul, suppression_ratio)
						local suppression_mul = managers.blackmarket:threat_multiplier()
						local dmg_mul = managers.player:temporary_upgrade_value("temporary", "dmg_multiplier_outnumbered", 1)

						if managers.player:has_category_upgrade("player", "overkill_all_weapons") or weap_base:is_category("shotgun", "saw") then
							dmg_mul = dmg_mul * managers.player:temporary_upgrade_value("temporary", "overkill_damage_multiplier", 1)
						end

						local health_ratio = self._ext_damage:health_ratio()
						local primary_category = weap_base:weapon_tweak_data().categories[1]
						local damage_health_ratio = managers.player:get_damage_health_ratio(health_ratio, primary_category)

						if damage_health_ratio > 0 then
							local upgrade_name = weap_base:is_category("saw") and "melee_damage_health_ratio_multiplier" or "damage_health_ratio_multiplier"
							local damage_ratio = damage_health_ratio
							dmg_mul = dmg_mul * (1 + managers.player:upgrade_value("player", upgrade_name, 0) * damage_ratio)
						end

						dmg_mul = dmg_mul * managers.player:temporary_upgrade_value("temporary", "berserker_damage_multiplier", 1)
						dmg_mul = dmg_mul * managers.player:get_property("trigger_happy", 1)
						local fired = nil

						if fire_mode == "single" then
							if input.btn_primary_attack_press and start_shooting then
								fired = weap_base:trigger_pressed(self:get_fire_weapon_position(), self:get_fire_weapon_direction(), dmg_mul, nil, spread_mul, autohit_mul, suppression_mul)
							elseif fire_on_release then
								if input.btn_primary_attack_release then
									fired = weap_base:trigger_released(self:get_fire_weapon_position(), self:get_fire_weapon_direction(), dmg_mul, nil, spread_mul, autohit_mul, suppression_mul)
								elseif input.btn_primary_attack_state then
									weap_base:trigger_held(self:get_fire_weapon_position(), self:get_fire_weapon_direction(), dmg_mul, nil, spread_mul, autohit_mul, suppression_mul)
								end
							end
						elseif input.btn_primary_attack_state then
							fired = weap_base:trigger_held(self:get_fire_weapon_position(), self:get_fire_weapon_direction(), dmg_mul, nil, spread_mul, autohit_mul, suppression_mul)
						end

						if weap_base.manages_steelsight and weap_base:manages_steelsight() then
							if weap_base:wants_steelsight() and not self._state_data.in_steelsight then
								self:_start_action_steelsight(t)
							elseif not weap_base:wants_steelsight() and self._state_data.in_steelsight then
								self:_end_action_steelsight(t)
							end
						end

						local charging_weapon = fire_on_release and weap_base:charging()

						if not self._state_data.charging_weapon and charging_weapon then
							self:_start_action_charging_weapon(t)
						elseif self._state_data.charging_weapon and not charging_weapon then
							self:_end_action_charging_weapon(t)
						end

						new_action = true

						if fired then
							managers.rumble:play("weapon_fire")

							local weap_tweak_data = tweak_data.weapon[weap_base:get_name_id()]
							local shake_multiplier = weap_tweak_data.shake[self._state_data.in_steelsight and "fire_steelsight_multiplier" or "fire_multiplier"]

							self._ext_camera:play_shaker("fire_weapon_rot", 1 * shake_multiplier)
							self._ext_camera:play_shaker("fire_weapon_kick", 1 * shake_multiplier, 1, 0.15)
							self._equipped_unit:base():tweak_data_anim_stop("unequip")
							self._equipped_unit:base():tweak_data_anim_stop("equip")

							if not self._state_data.in_steelsight or not weap_base:tweak_data_anim_play("fire_steelsight", weap_base:fire_rate_multiplier()) then
								weap_base:tweak_data_anim_play("fire", weap_base:fire_rate_multiplier())
							end

							if fire_mode == "single" and weap_base:get_name_id() ~= "saw" then
								if not self._state_data.in_steelsight then
									self._ext_camera:play_redirect(self:get_animation("recoil"), weap_base:fire_rate_multiplier())
								elseif weap_tweak_data.animations.recoil_steelsight then
									self._ext_camera:play_redirect(weap_base:is_second_sight_on() and self:get_animation("recoil") or self:get_animation("recoil_steelsight"), 1)
								end
							end

							local recoil_multiplier = (weap_base:recoil() + weap_base:recoil_addend()) * weap_base:recoil_multiplier()

	--						cat_print("jansve", "[PlayerStandard] Weapon Recoil Multiplier: " .. tostring(recoil_multiplier))

							local up, down, left, right = unpack(weap_tweak_data.kick[self._state_data.in_steelsight and "steelsight" or self._state_data.ducking and "crouching" or "standing"])

							self._camera_unit:base():recoil_kick(up * recoil_multiplier, down * recoil_multiplier, left * recoil_multiplier, right * recoil_multiplier)

							if self._shooting_t then
								local time_shooting = t - self._shooting_t
								local achievement_data = tweak_data.achievement.never_let_you_go

								if achievement_data and weap_base:get_name_id() == achievement_data.weapon_id and achievement_data.timer <= time_shooting then
									managers.achievment:award(achievement_data.award)

									self._shooting_t = nil
								end
							end

							if managers.player:has_category_upgrade(primary_category, "stacking_hit_damage_multiplier") then
								self._state_data.stacking_dmg_mul = self._state_data.stacking_dmg_mul or {}
								self._state_data.stacking_dmg_mul[primary_category] = self._state_data.stacking_dmg_mul[primary_category] or {
									nil,
									0
								}
								local stack = self._state_data.stacking_dmg_mul[primary_category]

								if fired.hit_enemy then
									stack[1] = t + managers.player:upgrade_value(primary_category, "stacking_hit_expire_t", 1)
									stack[2] = math.min(stack[2] + 1, tweak_data.upgrades.max_weapon_dmg_mul_stacks or 5)
								else
									stack[1] = nil
									stack[2] = 0
								end
							end

							if weap_base.set_recharge_clbk then
								weap_base:set_recharge_clbk(callback(self, self, "weapon_recharge_clbk_listener"))
							end

							managers.hud:set_ammo_amount(weap_base:selection_index(), weap_base:ammo_info())

							local impact = not fired.hit_enemy

							if weap_base.third_person_important and weap_base:third_person_important() then
								self._ext_network:send("shot_blank_reliable", impact, 0)
							elseif weap_base.akimbo and not weap_base:weapon_tweak_data().allow_akimbo_autofire or fire_mode == "single" then
								self._ext_network:send("shot_blank", impact, 0)
							end
						elseif fire_mode == "single" then
							new_action = false
						end
					end
				end
			elseif self:_is_reloading() and self._equipped_unit:base():reload_interuptable() and input.btn_primary_attack_press then
				self._queue_reload_interupt = true
			end
		end

		if not new_action then
			self:_check_stop_shooting()
		end

		return new_action
	end

	function PlayerStandard:_check_stop_shooting() --TEMPORARY FIX, REMOVE WHEN CLAIRE AUTO ANIMS ARE ADDED
		if self._shooting then
			self._equipped_unit:base():stop_shooting()
			self._camera_unit:base():stop_shooting(self._equipped_unit:base():recoil_wait())

			local weap_base = self._equipped_unit:base()
			local fire_mode = weap_base:fire_mode()

			if fire_mode == "auto" and (not weap_base.akimbo or weap_base:weapon_tweak_data().allow_akimbo_autofire) then
				self._ext_network:send("sync_stop_auto_fire_sound", 0)
			end

			if fire_mode == "auto" and not self:_is_reloading() and not self:_is_meleeing() and not (weap_base:is_weapon_class("class_shotgun") and managers.player:has_category_upgrade("class_shotgun","heartbreaker_doublebarrel") and weap_base:weapon_tweak_data().CLIP_AMMO_MAX == 2) then
				self._unit:camera():play_redirect(self:get_animation("recoil_exit"))
			end

			self._shooting = false
			self._shooting_t = nil
		end
	end

	function PlayerStandard:_update_omniscience(t, dt)
		if managers.groupai:state():whisper_mode() and managers.player:has_category_upgrade("player", "standstill_omniscience") and tweak_data.player.omniscience then 

			local range = tweak_data.upgrades.values.player.omniscience_range[1]
			if self._moving or self:running() or self:in_air() or not self._state_data.omniscience_t then 
				self._state_data.omniscience_t = t + tweak_data.upgrades.values.player.omniscience_timer[1]
			else
				if self._state_data.omniscience_t <= t then 
					range = tweak_data.upgrades.values.player.omniscience_range[2]
				end
			end
			
			local sensed_targets = World:find_units_quick("sphere", self._unit:movement():m_pos(), range, managers.slot:get_mask("trip_mine_targets"))

			for _, unit in ipairs(sensed_targets) do
				if alive(unit) and not unit:base():char_tweak().is_escort then
					self._state_data.omniscience_units_detected = self._state_data.omniscience_units_detected or {}

					if not self._state_data.omniscience_units_detected[unit:key()] or self._state_data.omniscience_units_detected[unit:key()] <= t then
						self._state_data.omniscience_units_detected[unit:key()] = t + tweak_data.player.omniscience.target_resense_t

						managers.game_play_central:auto_highlight_enemy(unit, true)

						break
					end
				end
			end
		else
			self._state_data.omniscience_t = nil
			return
		end
	end
	
	local orig_throw_grenade = PlayerStandard._check_action_throw_grenade
	function PlayerStandard:_check_action_throw_grenade(t, input, ...)
		local action_wanted = input.btn_throw_grenade_press

		local projectile_entry = managers.blackmarket:equipped_projectile()
		local projectile_tweak = tweak_data.blackmarket.projectiles[projectile_entry]

		if not managers.player:can_throw_grenade() then
			return
		end

		local action_forbidden = not PlayerBase.USE_GRENADES or self:chk_action_forbidden("interact") or self._unit:base():stats_screen_visible() or self:_is_throwing_grenade() or self:_interacting() or self:is_deploying() or self:_changing_weapon() or self:_is_meleeing() or self:_is_using_bipod()

		if action_forbidden then
			return
		end

		if projectile_tweak.override_equipment_id then 
			local equipment_data = tweak_data.equipments[projectile_tweak.override_equipment_id]
			if equipment_data then 
				if projectile_tweak.instant_use then 
					if input.btn_projectile_state then --held
						if not self._held_throwable_equipment then 
							self._held_throwable_equipment = true
							self:_play_unequip_animation()
						end
--						managers.hud:hide_progress_timer_bar(complete)
--						managers.hud:set_progress_timer_bar_valid(valid, not valid and "hud_deploy_valid_help")
						local valid,on_enemy = self._unit:equipment():valid_look_at_placement(equipment_data,managers.player:has_category_upgrade("trip_mine","can_place_on_enemies")) and true or false

						local equipment_name = managers.localization:text(equipment_data.text_id or "cursed_error")
--						managers.hud:show_progress_timer({
--							text = managers.localization:text(valid and "hud_deploying_tripmine_preview" or "hud_deploy_valid_help",{EQUIPMENT = equipment_name})
--						})
						if equipment_data.sound_start then
							self._unit:sound_source():post_event(equipment_data.sound_start)
						end
					elseif input.btn_projectile_release and self._held_throwable_equipment then
						self._held_throwable_equipment = nil
						self:_play_equip_animation()
						
						local valid,on_enemy = self._unit:equipment():valid_look_at_placement(equipment_data,managers.player:has_category_upgrade("trip_mine","can_place_on_enemies")) and true or false
						
						local equipmentbase = self._unit:equipment()
						if valid and equipment_data.use_function_name and equipmentbase[equipment_data.use_function_name] then 
							valid = equipmentbase[equipment_data.use_function_name](equipmentbase)
						end
						
						if valid then 
							managers.player:add_grenade_amount(-1)
							if equipment_data.sound_done then
								self._unit:sound_source():post_event(equipment_data.sound_done)
							end
						else
							if equipment_data.sound_interupt then 
								self._unit:sound_source():post_event(equipment_data.sound_interupt)
							end
						end
						equipmentbase:on_deploy_interupted()
						
--						local wtd = self._equipped_unit:base():weapon_tweak_data()
--						self._equip_weapon_expire_t = managers.player:player_timer():time() + (wtd.timers.equip or 0.7)
--						self:_play_equip_animation()
						
--						managers.hud:remove_progress_timer()
					end
				else
					if not action_wanted then
						self._held_throwable_equipment = nil
						return
					end
					self:_start_action_use_throwable_equipment(t,equipment_data)
				end
			end
		else
			if not action_wanted then
				return
			end
			self:_start_action_throw_grenade(t, input)
		end

		return action_wanted
	end

	function PlayerStandard:_interupt_action_throw_grenade(t, input)
		if not self:_is_throwing_grenade() then
			return
		end
 		local projectile_entry = managers.blackmarket:equipped_projectile()
		local projectile_tweak = tweak_data.blackmarket.projectiles[projectile_entry]
		if projectile_tweak.override_equipment_id then 
			self:_interupt_action_use_throwable_equipment(t)

		else
			self._ext_camera:play_redirect(self:get_animation("equip"))
			self._camera_unit:base():unspawn_grenade()
			self._camera_unit:base():show_weapon()
			self._state_data.throw_grenade_expire_t = nil
		end

		self:_stance_entered()
	end

	function PlayerStandard:_start_action_use_throwable_equipment(t,equipment_data)
	
		self:_interupt_action_reload(t)
		self:_interupt_action_steelsight(t)
		self:_interupt_action_running(t)
		self:_interupt_action_charging_weapon(t)
	
		local equipment_name = managers.localization:text(equipment_data.text_id or "cursed_error")
		local deploy_timer = equipment_data.deploy_time

		self._use_throwable_equipment_expire_t = t + deploy_timer

		self:_play_unequip_animation()

		local text = managers.player:selected_equipment_deploying_text() or managers.localization:text("hud_deploying_equipment", {
			EQUIPMENT = equipment_name
		})

		managers.hud:show_progress_timer({
			text = text
		})
		managers.hud:show_progress_timer_bar(0, deploy_timer)
		
		if equipment_data.sound_start then
			self._unit:sound_source():post_event(equipment_data.sound_start)
		end

		managers.network:session():send_to_peers_synched("sync_teammate_progress", 2, true, equipment_id, deploy_timer, false)
	end

	function PlayerStandard:_update_throwable_equipment_timers(t)
 		local projectile_entry = managers.blackmarket:equipped_projectile()
		local projectile_tweak = tweak_data.blackmarket.projectiles[projectile_entry]
		local equipment_id = projectile_tweak.override_equipment_id
		local equipment_data = equipment_id and tweak_data.equipments[equipment_id]
		if equipment_data then 

			local valid = self._unit:equipment():valid_look_at_placement(equipment_data) and true or false
			
			local deploy_time_total = equipment_data.deploy_time
			local deploy_time_current = deploy_time_total - math.max(0,self._use_throwable_equipment_expire_t - t)
			
			local text = managers.localization:text("hud_deploying_equipment", {
				EQUIPMENT = managers.localization:text(equipment_data.text_id or "cursed_error")
			})

			managers.hud:show_progress_timer({
				text = text
			})
			
			managers.hud:set_progress_timer_bar_width(deploy_time_current,deploy_time_total)
			managers.hud:set_progress_timer_bar_valid(valid, not valid and "hud_deploy_valid_help")
			
			
			if self._use_throwable_equipment_expire_t <= t then 
				self:_end_action_use_throwable_equipment(valid,equipment_data)
			end
		end
	end
		
	function PlayerStandard:_interupt_action_use_throwable_equipment(t, input, complete, equipment_data)

		if self._use_throwable_equipment_expire_t then
			self._use_throwable_equipment_expire_t = nil
			local tweak_data = self._equipped_unit:base():weapon_tweak_data()
			self._equip_weapon_expire_t = managers.player:player_timer():time() + (tweak_data.timers.equip or 0.7)
			self:_play_equip_animation()
			managers.hud:hide_progress_timer_bar(complete)
			managers.hud:remove_progress_timer()


			if not complete then
				if not equipment_data then 
					local projectile_entry = managers.blackmarket:equipped_projectile()
					local projectile_tweak = tweak_data.blackmarket.projectiles[projectile_entry]
					local equipment_id = projectile_tweak.override_equipment_id
					equipment_data = equipment_id and tweak_data.equipments[equipment_id]
				end
				
				if equipment_data.sound_interupt then 
					self._unit:sound_source():post_event(post_event)
				end
				
			end

			self._unit:equipment():on_deploy_interupted()
			managers.network:session():send_to_peers_synched("sync_teammate_progress", 2, false, "", 0, complete and true or false)
		end
	end

	function PlayerStandard:_end_action_use_throwable_equipment(valid,equipment_data)
		local pm = managers.player
		local equipmentbase = self._unit:equipment()
		
		if not pm:can_throw_grenade() then 
			valid = false
		end
		
		if valid and equipment_data.use_function_name and equipmentbase[equipment_data.use_function_name] then 
			valid = equipmentbase[equipment_data.use_function_name](equipmentbase)
		end
		
		if valid then 
			if equipment_data.sound_done then
				self._unit:sound_source():post_event(equipment_data.sound_done)
			end
			pm:add_grenade_amount(-1)
		end

		self:_interupt_action_use_throwable_equipment(nil, nil, valid,equipment_data)

	end
	
	function PlayerStandard:_update_throw_grenade_timers(t,input,...)
		if self._use_throwable_equipment_expire_t then 
			return self:_update_throwable_equipment_timers(t,...)
		end
		
		if self._state_data.throw_grenade_expire_t and self._state_data.throw_grenade_expire_t <= t then
			self._state_data.throw_grenade_expire_t = nil

			self:_stance_entered()

			if self._equipped_unit and input.btn_steelsight_state then
				self._steelsight_wanted = true
			end
		end
	end

	local orig_throwing_grenade_check = PlayerStandard._is_throwing_grenade
	function PlayerStandard:_is_throwing_grenade(...)
		return orig_throwing_grenade_check(self,...) or self._use_throwable_equipment_expire_t and true or false --or self._held_throwable_equipment
	end
	
	local orig_deploying_check = PlayerStandard.is_deploying
	function PlayerStandard:is_deploying(...)
		return orig_deploying_check(self,...) or self._use_throwable_equipment_expire_t
	end

	function PlayerStandard:_check_action_interact(t, input)
		local keyboard = self._controller.TYPE == "pc" or managers.controller:get_default_wrapper_type() == "pc"
		local new_action, timer, interact_object = nil

		if input.btn_interact_press then
			if _G.IS_VR then
				self._interact_hand = input.btn_interact_left_press and PlayerHand.LEFT or PlayerHand.RIGHT
			end

			if not self:_action_interact_forbidden() then
				new_action, timer, interact_object = self._interaction:interact(self._unit, input.data, self._interact_hand)

				if new_action then
					self:_play_interact_redirect(t, input)
				end

				if timer then
					new_action = true
					
					if not managers.player:has_category_upgrade("player", "burglar_camera_freeturn") then
						self._ext_camera:camera_unit():base():set_limits(80, 50)
					end
					
					self:_start_action_interact(t, input, timer, interact_object)
				end

				if not new_action then
					self._start_intimidate = true
					self._start_intimidate_t = t
				end
			end
		end

		local secondary_delay = tweak_data.team_ai.stop_action.delay
		local force_secondary_intimidate = false

		if not new_action and keyboard and input.btn_interact_secondary_press then
			force_secondary_intimidate = true
		end

		if input.btn_interact_release then
			local released = true

			if _G.IS_VR then
				local release_hand = input.btn_interact_left_release and PlayerHand.LEFT or PlayerHand.RIGHT
				released = release_hand == self._interact_hand
			end

			if released then
				if self._start_intimidate and not self:_action_interact_forbidden() then
					if t < self._start_intimidate_t + secondary_delay then
						self:_start_action_intimidate(t)

						self._start_intimidate = false
					end
				else
					self:_interupt_action_interact()
				end
			end
		end

		if (self._start_intimidate or force_secondary_intimidate) and not self:_action_interact_forbidden() and (not keyboard and t > self._start_intimidate_t + secondary_delay or force_secondary_intimidate) then
			self:_start_action_intimidate(t, true)

			self._start_intimidate = false
		end

		return new_action
	end

	function PlayerStandard:_start_action_intimidate(t, secondary)
		if not self._intimidate_t or tweak_data.player.movement_state.interaction_delay < t - self._intimidate_t then
			local skip_alert = managers.groupai:state():whisper_mode()
			local voice_type, plural, prime_target = self:_get_unit_intimidation_action(not secondary, not secondary, true, false, true, nil, nil, nil, secondary)

			if prime_target and prime_target.unit and prime_target.unit.base and (prime_target.unit:base().unintimidateable or prime_target.unit:anim_data() and prime_target.unit:anim_data().unintimidateable) then
				return
			end

			local interact_type, sound_name = nil
			local sound_suffix = plural and "plu" or "sin"

			if voice_type == "stop" then
				interact_type = "cmd_stop"
				sound_name = "f02x_" .. sound_suffix
			elseif voice_type == "stop_cop" then
				interact_type = "cmd_stop"
				sound_name = "l01x_" .. sound_suffix
			elseif voice_type == "mark_cop" or voice_type == "mark_cop_quiet" then
				interact_type = "cmd_point"

				if voice_type == "mark_cop_quiet" then
					sound_name = tweak_data.character[prime_target.unit:base()._tweak_table].silent_priority_shout .. "_any"
				else
					sound_name = tweak_data.character[prime_target.unit:base()._tweak_table].priority_shout .. "x_any"
					sound_name = managers.modifiers:modify_value("PlayerStandart:_start_action_intimidate", sound_name, prime_target.unit)
				end

				if managers.player:has_category_upgrade("player", "special_enemy_highlight") then
					if Network:is_server() and managers.player:has_category_upgrade("player", "convert_enemies_target_marked") then
						prime_target.unit:contour():add(managers.player:get_contour_for_marked_enemy(), true, managers.player:upgrade_value("player", "mark_enemy_time_multiplier", 1), nil, nil, managers.network:session():local_peer():id())
					else
						prime_target.unit:contour():add(managers.player:get_contour_for_marked_enemy(), true, managers.player:upgrade_value("player", "mark_enemy_time_multiplier", 1))
					end
				end
			elseif voice_type == "down" then
				interact_type = "cmd_down"
				sound_name = "f02x_" .. sound_suffix
				self._shout_down_t = t
			elseif voice_type == "down_cop" then
				interact_type = "cmd_down"
				sound_name = "l02x_" .. sound_suffix
			elseif voice_type == "cuff_cop" then
				interact_type = "cmd_down"
				sound_name = "l03x_" .. sound_suffix
			elseif voice_type == "down_stay" then
				interact_type = "cmd_down"

				if self._shout_down_t and t < self._shout_down_t + 2 then
					sound_name = "f03b_any"
				else
					sound_name = "f03a_" .. sound_suffix
				end
			elseif voice_type == "come" then
				interact_type = "cmd_come"
				local static_data = managers.criminals:character_static_data_by_unit(prime_target.unit)

				if static_data then
					local character_code = static_data.ssuffix
					sound_name = "f21" .. character_code .. "_sin"
				else
					sound_name = "f38_any"
				end
			elseif voice_type == "revive" then
				interact_type = "cmd_get_up"
				local static_data = managers.criminals:character_static_data_by_unit(prime_target.unit)

				if not static_data then
					return
				end

				local character_code = static_data.ssuffix
				sound_name = "f36x_any"

				if math.random() < self._ext_movement:rally_skill_data().revive_chance then
					prime_target.unit:interaction():interact(self._unit)
				end

				self._ext_movement:rally_skill_data().morale_boost_delay_t = managers.player:player_timer():time() + (self._ext_movement:rally_skill_data().morale_boost_cooldown_t or 3.5)
			elseif voice_type == "boost" then
				interact_type = "cmd_gogo"
				local static_data = managers.criminals:character_static_data_by_unit(prime_target.unit)

				if not static_data then
					return
				end

				local character_code = static_data.ssuffix
				sound_name = "g18"
				self._ext_movement:rally_skill_data().morale_boost_delay_t = managers.player:player_timer():time() + (self._ext_movement:rally_skill_data().morale_boost_cooldown_t or 3.5)
			elseif voice_type == "escort" then
				interact_type = "cmd_point"
				sound_name = "f41_" .. sound_suffix
			elseif voice_type == "escort_keep" or voice_type == "escort_go" then
				interact_type = "cmd_point"
				sound_name = "f40_any"
			elseif voice_type == "bridge_codeword" then
				sound_name = "bri_14"
				interact_type = "cmd_point"
			elseif voice_type == "bridge_chair" then
				sound_name = "bri_29"
				interact_type = "cmd_point"
			elseif voice_type == "undercover_interrogate" then
				sound_name = "f46x_any"
				interact_type = "cmd_point"
			elseif voice_type == "undercover_escort" then
				sound_name = "f41_any"
				interact_type = "cmd_point"
			elseif voice_type == "mark_camera" then
				sound_name = "f39_any"
				interact_type = "cmd_point"

				prime_target.unit:contour():add("mark_unit", true, managers.player:upgrade_value("player", "mark_enemy_time_multiplier", 1))
			elseif voice_type == "mark_turret" then
				sound_name = "f44x_any"
				interact_type = "cmd_point"
				local type = prime_target.unit:base().get_type and prime_target.unit:base():get_type()

				if Network:is_server() and managers.player:has_category_upgrade("player", "convert_enemies_target_marked") then
					prime_target.unit:contour():add(managers.player:get_contour_for_marked_enemy(type), true, managers.player:upgrade_value("player", "mark_enemy_time_multiplier", 1), nil, nil, managers.network:session():local_peer():id())
				else
					prime_target.unit:contour():add(managers.player:get_contour_for_marked_enemy(type), true, managers.player:upgrade_value("player", "mark_enemy_time_multiplier", 1))
				end
			elseif voice_type == "ai_stay" then
				sound_name = "f48x_any"
				interact_type = "cmd_stop"
			end

			self:_do_action_intimidate(t, interact_type, sound_name, skip_alert)
		end
	end

	--wrote the HUD code and stuff real quick and dirty just so that we could start getting feedback from testers
	--IOU some prettier code
	-- -offy
	Hooks:Add("TCD_Create_Stack_Tracker_HUD","TCD_Create_TagTeam_HUD",function(hudtemp)
		if hudtemp and alive(hudtemp) then
			if alive(hudtemp:child("deathvox_tagteam")) then 
				hudtemp:remove(hudtemp:child("deathvox_tagteam"))
			end
			local deathvox_tagteam = hudtemp:panel({
				name = "deathvox_tagteam"
			})
		end
	end)
	
	function PlayerStandard:_update_tagteam_hud_targets(t,input)
		
		local released
		if self._cache_held_grenade then --todo make consistent with tripmine code
			if not input.btn_projectile_state then 
				self._cache_held_grenade = false
				released = true
			end
		else
			self._cache_held_grenade = input.btn_projectile_state
			if not input.btn_projectile_state then
				return false
			end
		end

		local pm = managers.player
		--todo: external function to update tag team targets on hud?
		--or just new waypoint w/callback destroy function?
		
		local base_data = pm:upgrade_value("player", "tag_team_base_deathvox")
		
		local player = pm:local_player()
		local player_eye = player:camera():position()
		local player_fwd = player:camera():rotation():y()
		local tagged = nil
		local heisters_slot_mask = World:make_slot_mask(2, 3, 4, 5, 16, 24)
		local tag_distance = base_data.distance
		local long_distance_revive_health = pm:upgrade_value("player","tag_team_long_distance_revive",0)
		local long_distance_revive_level = pm:upgrade_level("player","tag_team_long_distance_revive",0)
		local max_angle = base_data.max_angle

		local head_pos = player:movement():m_head_pos()
		local head_rot = player:movement():m_head_rot()
		local aim_direction = head_rot:yaw()
		local best_pick = {
			unit = nil,
			distance = nil,
			hud_element = nil,
			angle = 360
		}
		local panel = managers.hud and managers.hud._hud_temp and managers.hud._hud_temp._hud_panel:child("deathvox_tagteam")
		if not alive(panel) then 
			return
		end

		local ws = managers.hud._workspace
		local current_camera = managers.viewport:get_current_camera()
		local this_frame = {}
		local texture,texture_rect = tweak_data.hud_icons:get_icon_data("tag_team")
		local nearby_heisters = World:find_units_quick("sphere",head_pos,tag_distance,heisters_slot_mask)
		for _,unit in pairs(nearby_heisters) do 
			local u_key = tostring(unit:key())
			this_frame[u_key] = true
			local unit_pos = unit:oobb() and unit:oobb():center() or unit:position()
			local angle = math.abs(mvector3.angle(unit_pos - head_pos,head_rot:y()))
			local hud_element = panel:child(u_key)
			local coords = ws:world_to_screen(current_camera,unit_pos) or {x = -100,y = -100}
			local c_x,c_y = coords.x,coords.y
			
			if alive(hud_element) then 
				hud_element:set_color(Color("888888"))
				hud_element:set_alpha(0.5)
			else
				hud_element = panel:bitmap({
					name = tostring(u_key),
					texture = texture,
					texture_rect = texture_rect,
					alpha = 0.5,
					w = 48,
					h = 48
				})
			end
			
			if angle < max_angle then 
				hud_element:show()
				hud_element:set_center(c_x,c_y)
				if angle < best_pick.angle then 
					best_pick = {
						unit = unit,
						distance = distance,
						hud_element = hud_element,
						angle = angle
					}
				end
			else
				hud_element:hide()
			end
		end
		
		if released then 
			for _,element in pairs(panel:children()) do 
				panel:remove(element)
			end
		else
			for _,element in pairs(panel:children()) do 
				if element == best_pick.hud_element then 
					element:set_color(Color.white)
					element:set_alpha(1)
				elseif not this_frame[element:name()] then --i have strong feelings about doing it this way. i'll be back for this
					panel:remove(element)
				end
			end
		end
		
		return released
	end

	function PlayerStandard:_check_action_use_ability(t, input)
		local action_wanted = input.btn_throw_grenade_press
		local held = input.btn_projectile_state

		local equipped_ability,amount = managers.blackmarket:equipped_grenade()
		local ptd = equipped_ability and tweak_data.blackmarket.projectiles[equipped_ability] 
		if ptd then 
			if ptd.hold_function_name then 
				action_wanted = self[ptd.hold_function_name](self,t, input) 
			end
		end
		
		if not action_wanted then
			return
		end
		if not managers.player:attempt_ability(equipped_ability) then
			return
		end

		return action_wanted
	end

	function PlayerStandard:_find_pickups(t)
		local pm = managers.player
		
		local pickup_radius = 200 * pm:upgrade_value("player", "increased_pickup_area", 1) * pm:team_upgrade_value("player","ammo_pickup_range_mul",1)
	
		local pickups = World:find_units_quick("sphere", self._unit:movement():m_pos(), pickup_radius, self._slotmask_pickups)
		local grenade_tweak = tweak_data.blackmarket.projectiles[managers.blackmarket:equipped_grenade()]
		local may_find_grenade = grenade_tweak and not grenade_tweak.base_cooldown and pm:has_category_upgrade("player", "regain_throwable_from_ammo")

		for _, pickup in ipairs(pickups) do
			if pickup:pickup() and pickup:pickup():pickup(self._unit) then
				if may_find_grenade then
					local data = pm:upgrade_value("player", "regain_throwable_from_ammo", nil)

					if data then
						pm:add_coroutine("regain_throwable_from_ammo", PlayerAction.FullyLoaded, pm, data.chance, data.chance_inc)
					end
				end

				for id, weapon in pairs(self._unit:inventory():available_selections()) do
					managers.hud:set_ammo_amount(id, weapon.unit:base():ammo_info())
				end
			end
		end
	end
	
end
