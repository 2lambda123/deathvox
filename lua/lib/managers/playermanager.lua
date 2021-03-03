local mvec3_dis = mvector3.distance

Hooks:PostHook(PlayerManager,"_internal_load","deathvox_on_internal_load",function(self)
--this will send whenever the player respawns, so... hm. 
	if Network:is_server() then 
		deathvox:SyncOptionsToClients()
	else
		deathvox:ResetSessionSettings()
	end
--	Hooks:Call("TCD_OnGameStarted")
end)

function PlayerManager:_chk_fellow_crimin_proximity(unit)
	local players_nearby = 0
		
	local criminals = World:find_units_quick(unit, "sphere", unit:position(), 1500, managers.slot:get_mask("criminals_no_deployables"))

	for _, criminal in ipairs(criminals) do
		players_nearby = players_nearby + 1
	end
		
	if players_nearby <= 0 then
		--log("uhohstinky")
	end
		
	return players_nearby
end

--function written for cd, not vanilla
function PlayerManager:team_upgrade_value_by_level(category, upgrade, level, default)
	local cat = tweak_data.upgrades.values.team[category]
	local upg = cat and cat[upgrade]
	return upg and upg[level] or default
end

--function written for cd, not vanilla
function PlayerManager:team_upgrade_level(category, upgrade, default)
	for peer_id, categories in pairs(self._global.synced_team_upgrades) do
		if categories[category] and categories[category][upgrade] then
			return categories[category][upgrade]
		end
	end

	if not self._global.team_upgrades[category] then
		return default or 0
	end

	if not self._global.team_upgrades[category][upgrade] then
		return default or 0
	end

	return self._global.team_upgrades[category][upgrade]
end

if deathvox:IsTotalCrackdownEnabled() then
	
	Hooks:PostHook(PlayerManager,"init","tcd_playermanager_init",function(self)
		self._damage_overshield = {}
	end)
	
	function PlayerManager:check_equipment_placement_valid(player, equipment)
		local equipment_data = managers.player:equipment_data_by_name(equipment)

		if not equipment_data then
			return false
		end

		if equipment_data.equipment == "trip_mine" or equipment_data.equipment == "ecm_jammer" then
			return player:equipment():valid_look_at_placement(tweak_data.equipments[equipment_data.equipment]) and true or false
		elseif equipment_data.equipment == "sentry_gun" or equipment_data.equipment == "ammo_bag" or equipment_data.equipment == "sentry_gun_silent" or equipment_data.equipment == "doctor_bag" or equipment_data.equipment == "first_aid_kit" or equipment_data.equipment == "bodybags_bag" then
			local result,revivable_unit = player:equipment():valid_shape_placement(equipment_data.equipment, tweak_data.equipments[equipment_data.equipment])
			return result and true or false,revivable_unit
		elseif equipment_data.equipment == "armor_kit" then
			return player:equipment():valid_shape_placement(equipment_data.equipment,tweak_data.equipments[equipment_data.equipment]) and true or false
		end

		return player:equipment():valid_placement(tweak_data.equipments[equipment_data.equipment]) and true or false
	end
	
	function PlayerManager:damage_reduction_skill_multiplier(damage_type)
	--the only changes are the armor plates dmg resist, and the nearby-hostage dmg resist bonus from Leverage
		local multiplier = 1
		multiplier = multiplier * self:temporary_upgrade_value("temporary", "dmg_dampener_outnumbered", 1)
		multiplier = multiplier * self:temporary_upgrade_value("temporary", "dmg_dampener_outnumbered_strong", 1)
		multiplier = multiplier * self:temporary_upgrade_value("temporary", "dmg_dampener_close_contact", 1)
		multiplier = multiplier * self:temporary_upgrade_value("temporary", "revived_damage_resist", 1)
		multiplier = multiplier * self:upgrade_value("player", "damage_dampener", 1)
		multiplier = multiplier * self:upgrade_value("player", "health_damage_reduction", 1)
		multiplier = multiplier * self:temporary_upgrade_value("temporary", "first_aid_damage_reduction", 1)
		multiplier = multiplier * self:temporary_upgrade_value("temporary", "revive_damage_reduction", 1)
		multiplier = multiplier * self:get_hostage_bonus_multiplier("damage_dampener")
		multiplier = multiplier * self._properties:get_property("revive_damage_reduction", 1)
		multiplier = multiplier * self._temporary_properties:get_property("revived_damage_reduction", 1)
		if self:get_property("armor_plates_active") then 
			multiplier = multiplier * tweak_data.upgrades.armor_plates_dmg_reduction
		end
		local dmg_red_mul = self:team_upgrade_value("damage_dampener", "team_damage_reduction", 1)


		local player = self:local_player()
		local team_upgrade_level = managers.player:team_upgrade_level("player","civilian_hostage_aoe_damage_resistance")
		if team_upgrade_level > 0 then 
			--this whole mess is for the Leverage skill in Taskmaster
			local player_pos = player:movement():m_pos()
			
			local hostage_range_close,hostage_dmg_resist_1 = unpack(managers.player:team_upgrade_value_by_level("player","civilian_hostage_aoe_damage_resistance",1,{}))
			local hostage_range_far,hostage_dmg_resist_2
			
			if team_upgrade_level == 2 then 
				hostage_range_far,hostage_dmg_resist_2 = unpack(managers.player:team_upgrade_value_by_level("player","civilian_hostage_aoe_damage_resistance",2,{}))
			end
			
			local near_hostage_close,near_hostage_far
			for _,hostage_unit in pairs(World:find_units_quick("sphere",player_pos,hostage_range_far or hostage_range_close,21,22)) do --managers.slot:get_mask("civilians") fails because tied civs are moved out of slot 22 and back into slot upon being moved
				if managers.enemy:is_civilian(hostage_unit) and hostage_unit:brain():is_tied() then 
					
					if team_upgrade_level == 2 then 
						local hostage_pos = hostage_unit:movement():m_pos()
						local hostage_distance = mvec3_dis(player_pos,hostage_pos)
						if hostage_distance <= hostage_range_close then 
							--within close distance is, by definition, also within far distance
							near_hostage_close = true
							near_hostage_far = true
							break
						elseif not near_hostage_far and hostage_distance <= hostage_range_far then 
							--if hasn't already done far hostage check
							near_hostage_far = true
						end
					elseif team_upgrade_level == 1 then 
						near_hostage_close = true
						--only one possible range for basic skill,
						--so we can stop checking hostages now
						break
					end
				end
			end
			
			local hostage_dmg_resist = 1
			
			if near_hostage_far then 
				hostage_dmg_resist = hostage_dmg_resist + hostage_dmg_resist_2
			end
			if near_hostage_close then 
				hostage_dmg_resist = hostage_dmg_resist + hostage_dmg_resist_1
			end
			
			multiplier = multiplier * hostage_dmg_resist
		end
		
		if self:has_category_upgrade("player", "passive_damage_reduction") then
			local health_ratio = self:player_unit():character_damage():health_ratio()
			local min_ratio = self:upgrade_value("player", "passive_damage_reduction")

			if health_ratio < min_ratio then
				dmg_red_mul = dmg_red_mul - (1 - dmg_red_mul)
			end
		end

		multiplier = multiplier * dmg_red_mul

		if damage_type == "melee" then
			multiplier = multiplier * managers.player:upgrade_value("player", "melee_damage_dampener", 1)
		end

		local current_state = self:get_current_state()

		if current_state and current_state:_interacting() then
			multiplier = multiplier * managers.player:upgrade_value("player", "interacting_damage_multiplier", 1)
		end


		return multiplier
	end


	--same as vanilla but disabled HUD element in order to prevent conflicting with damage overshield mechanic
	--if/when the actual absorption mechanic is overhauled, this function (and its accompanying HUD element) may also need to be revisited
	function PlayerManager:set_damage_absorption(key, value)
		self._damage_absorption[key] = value and Application:digest_value(value, true) or nil

--		managers.hud:set_absorb_active(HUDManager.PLAYER_PANEL, self:damage_absorption())
	end
	function PlayerManager:update_cocaine_hud()
		if managers.hud then
--			managers.hud:set_absorb_active(HUDManager.PLAYER_PANEL, self:damage_absorption())
		end
	end
	

	Hooks:PostHook(PlayerManager,"check_skills","deathvox_check_cd_skills",function(self)

	
		if self:has_category_upgrade("player","melee_hit_speed_boost") then
			Hooks:Add("OnPlayerMeleeHit","cd_proc_butterfly_bee_aced",
				function(hit_unit,col_ray,action_data,defense_data,t)
					if hit_unit and not managers.enemy:is_civilian(hit_unit) then 
						managers.player:activate_temporary_property("float_butterfly_movement_speed_multiplier",unpack(managers.player:upgrade_value("player","melee_hit_speed_boost",{0,0})))
					end
				end
			)
		end
		
		if self:has_category_upgrade("player","escape_plan") then 
			Hooks:Add("OnPlayerShieldBroken","cd_proc_escape_plan",
				function(player_unit)
					if alive(player_unit) then 
						local movement = player_unit:movement()
						
						local escape_plan_data = managers.player:upgrade_value("player","escape_plan",{0,0,0,0})
						local stamina_restored_percent = escape_plan_data[1]
						local sprint_speed_bonus = escape_plan_data[2]
						local escape_plan_duration = escape_plan_data[3]
						local move_speed_bonus = escape_plan_data[4]
						movement:_change_stamina(movement:_max_stamina() * stamina_restored_percent)
						self:activate_temporary_property("escape_plan_speed_bonus",escape_plan_duration,{sprint_speed_bonus,move_speed_bonus})
					end
				end
			)
		end
		
		if self:has_category_upgrade("saw","consecutive_damage_bonus") then 
			self:set_property("rolling_cutter_aced_stacks",0)
			
			Hooks:Register("OnProcRollingCutterBasic")
			Hooks:Add("OnProcRollingCutterBasic","AddToRollingCutterStacks",
				function(stack_add)
					stack_add = stack_add or 1
					local rolling_cutter_data = self:upgrade_value("saw","consecutive_damage_bonus",{0,0,0})
					
					self:add_to_property("rolling_cutter_aced_stacks",stack_add)
					
					managers.enemy:remove_delayed_clbk("rolling_cutter_stacks_expire",true)
					managers.enemy:add_delayed_clbk("rolling_cutter_stacks_expire",
						function()
							self:set_property("rolling_cutter_aced_stacks",0)
						end,
						Application:time() + rolling_cutter_data[3]
					)
				end
			)
		end
	
		if self:has_category_upgrade("class_heavy","collateral_damage") then 
			self._message_system:register(Message.OnWeaponFired,"proc_collateral_damage",
				function(weapon_unit,result)
				
					--this is called on any weapon firing,
					--so this needs checks to make sure that the weapon class is heavy
					--and that the user_unit is the player
					local player = self:local_player()
					if not alive(player) then 
						return
					end
					local weapon_base = weapon_unit and weapon_unit:base()
					if weapon_base and weapon_base._setup and weapon_base._setup.user_unit and weapon_base:is_weapon_class("class_heavy") then 
						if weapon_base._setup.user_unit ~= player then 
							return
						end
					else
						return
					end
					
					local collateral_damage_data = self:upgrade_value("class_heavy","collateral_damage",{0,0})
					local damage_mul = collateral_damage_data[1]
					local radius = collateral_damage_data[2]
					
					--do stuff here
					
						--works on miss
						--does not hit civs
				end
			)
		end
		
		if self:has_category_upgrade("class_heavy","death_grips_stacks") then
			self:set_property("current_death_grips_stacks",0)
			self._message_system:register(Message.OnEnemyKilled,"proc_death_grips",
				function(weapon_unit,variant,killed_unit)
					local player = self:local_player()
					if not alive(player) then 
						return
					end
					local weapon_base = weapon_unit and weapon_unit:base()
					if weapon_base and weapon_base._setup and weapon_base._setup.user_unit and weapon_base:is_weapon_class("class_heavy") then 
						if weapon_base._setup.user_unit ~= player then 
							return
						end
					else
						return
					end
					local death_grips_data = self:upgrade_value("class_heavy","death_grips_stacks",{0,0})
					self:set_property("current_death_grips_stacks",math.min(self:get_property("current_death_grips_stacks") + 1,death_grips_data[2]))
					managers.enemy:remove_delayed_clbk("death_grips_stacks_expire",true)
					managers.enemy:add_delayed_clbk("death_grips_stacks_expire",
						function()
							self:set_property("current_death_grips_stacks",0)
						end,
						Application:time() + death_grips_data[1]
					)
				end
			)
		end
		
		if self:has_category_upgrade("class_heavy","lead_farmer") then 
			self:set_property("current_lead_farmer_stacks",0)
			self._message_system:register(Message.OnEnemyKilled,"proc_lead_farmer",
				function(weapon_unit,variant,killed_unit)
					local player = self:local_player()
					if not alive(player) then 
						return
					end
					local weapon_base = weapon_unit and weapon_unit:base()
					if weapon_base and weapon_base._setup and weapon_base._setup.user_unit and weapon_base:is_weapon_class("class_heavy") then 
						if weapon_base._setup.user_unit ~= player then 
							return
						end
					else
						return
					end
					self:add_to_property("current_lead_farmer_stacks",1)
				end
			)
			
			Hooks:Add("OnPlayerReloadComplete","on_player_reloaded_consume_lead_farmer",
				--Message.OnPlayerReload is called when reload STARTS, which is before the reload mul is calculated.
				--so it's pretty useless to reset stacks from that message event.
				function(weapon_unit)
					local weapon_base = weapon_unit and weapon_unit:base()
					if weapon_base and weapon_base:is_weapon_class("class_heavy") then 
						managers.player:set_property("current_lead_farmer_stacks",0)
					end
				end
			)
		end
		
		if self:has_category_upgrade("class_shotgun","shell_games_reload_bonus") then
			self:set_property("shell_games_rounds_loaded",0)
		end
		if self:has_category_upgrade("weapon", "making_miracles_basic") then
			self:set_property("making_miracles_stacks",0)
			self._message_system:register(Message.OnHeadShot,"proc_making_miracles_basic",
				function()
					local player = self:local_player()
					if not alive(player) then 
						return
					end
					local weapon = player:inventory():equipped_unit():base()
					if not weapon:is_weapon_class("class_rapidfire") then 
						return
					end
					
					self:add_to_property("making_miracles_stacks",1) --add one stack
					managers.enemy:remove_delayed_clbk("making_miracles_stack_expire",true) --reset timer if active
					managers.enemy:add_delayed_clbk("making_miracles_stack_expire", --add 4-second removal timer for stacks
						function()
							self:set_property("making_miracles_stacks",0)
						end,
						Application:time() + self:upgrade_value("weapon","making_miracles_basic",{0,0})[2]
					)
				end
			)
		else
			self._message_system:unregister(Message.OnLethalHeadShot,"proc_making_miracles_basic")
		end
		
		if self:has_category_upgrade("weapon","making_miracles_aced") then 
			self._message_system:register(Message.OnLethalHeadShot,"proc_making_miracles_aced",
				function(attack_data)
					local player = self:local_player()
					if not alive(player) then 
						return
					end
					local weapon_base = attack_data and attack_data.weapon_unit and attack_data.weapon_unit:base()
					if weapon_base and weapon_base._setup and weapon_base._setup.user_unit and weapon_base:is_weapon_class("class_rapidfire") then 
						if weapon_base._setup.user_unit ~= player then 
							return
						end
					else
						return
					end
					
					self:add_to_property("making_miracles_stacks",1)
				end
			)
	else
		self._message_system:unregister(Message.OnLethalHeadShot,"proc_making_miracles_aced")
	end
		self:set_property("current_point_and_click_stacks",0)
		if self:has_category_upgrade("player","point_and_click_stacks") then 
			Hooks:Add("TCD_Create_Stack_Tracker_HUD","TCD_CreatePACElement",function(hudtemp)
			 --check_skills() is called before the hud is created so it must instead call on an event
			
				--create buff-specific hud element; todo create a hudbuff class to handle this
				--this is temporary until more of the core systems are done, and then i can dedicate more time 
				--to creating a buff tracker system + hud elements 
				--		-offy\
				
--				local hudtemp = managers.hud and managers.hud._hud_temp and managers.hud._hud_temp._hud_panel
				if hudtemp and alive(hudtemp) then
					if alive(hudtemp:child("point_and_click_tracker")) then 
						BeardLib:RemoveUpdater("update_tcd_buffs_hud")
						hudtemp:remove(hudtemp:child("point_and_click_tracker"))
					end
					local trackerhud = hudtemp:panel({
						name = "point_and_click_tracker",
						w = 100,
						h = 100
					})
					trackerhud:set_position((hudtemp:w() - trackerhud:w()) / 2,450)
					local debug_trackerhud = trackerhud:rect({
						name = "debug",
						color = Color.red,
						visible = false,
						alpha = 0.1
					})
					local icon_size = 64
					local icon_x,icon_y = 6,11 --bullseye
					local skill_atlas = "guis/textures/pd2/skilltree/icons_atlas"
					local skill_atlas_2 = "guis/textures/pd2/skilltree_2/icons_atlas_2"
					local perkdeck_atlas = "guis/textures/pd2/specialization/icons_atlas"	

					local icon = trackerhud:bitmap({
						name = "icon",
						texture = skill_atlas_2,
						texture_rect = {icon_x * 80,icon_y * 80,80,80},
						alpha = 0.9,
--						x = (trackerhud:w() - icon_size) / 2,
--						y = 0,
						w = icon_size,
						h = icon_size
					})
					icon:set_center(trackerhud:w()/2,trackerhud:h()/2)
					local stack_count = trackerhud:text({
						name = "text",
						text = "0",
						font = tweak_data.hud.medium_font,
						font_size = 16,
						align = "center",
						color = Color.white,
						vertical = "bottom"
					})
					
					BeardLib:AddUpdater("update_tcd_buffs_hud",function(t,dt)
						if alive(stack_count) then 
							stack_count:set_text(self:get_property("current_point_and_click_stacks",0))
							if managers.enemy:is_clbk_registered("point_and_click_on_shot_missed") and alive(icon) then 
								icon:set_color(Color(math.sin(t * 300 * math.pi),0,0))
							else
								icon:set_color(Color.white)
							end
						end
					end,false)
				end
			end)
			
			self._message_system:register(Message.OnEnemyShot,"proc_point_and_click",function(unit,attack_data)
				local player = self:local_player()
				if not alive(player) then 
					return
				end
				local weapon_base = attack_data and attack_data.weapon_unit and attack_data.weapon_unit:base()
				if weapon_base and weapon_base._setup and weapon_base._setup.user_unit and weapon_base:is_weapon_class("class_precision") then 
					if weapon_base._setup.user_unit ~= player then 
						return
					end
				else
					return
				end
				self:add_to_property("current_point_and_click_stacks",self:upgrade_value("player","point_and_click_stacks",0))
			end)
			if self:has_category_upgrade("player","point_and_click_stack_from_kill") then 
				self._message_system:register(Message.OnEnemyKilled,"proc_investment_returns_basic",function(weapon_unit,variant,killed_unit)
					local player = self:local_player()
					if not alive(player) then 
						return
					end
					local weapon_base = weapon_unit and weapon_unit:base()
					if weapon_base and weapon_base._setup and weapon_base._setup.user_unit and weapon_base:is_weapon_class("class_precision") then 
						if weapon_base._setup.user_unit ~= player then 
							return
						end
					else
						return
					end
					self:add_to_property("current_point_and_click_stacks",self:upgrade_value("player","point_and_click_stack_from_kill",0))
				end)
			else
				self._message_system:unregister(Message.OnEnemyKilled,"proc_investment_returns_basic")
			end
			
			if self:has_category_upgrade("player","point_and_click_stack_from_headshot_kill") then 
				self._message_system:register(Message.OnLethalHeadShot,"proc_investment_returns_aced",function(attack_data)
					local player = self:local_player()
					if not alive(player) then 
						return
					end
					local weapon_base = attack_data and attack_data.weapon_unit and attack_data.weapon_unit:base()
					if weapon_base and weapon_base._setup and weapon_base._setup.user_unit and weapon_base:is_weapon_class("class_precision") then 
						if weapon_base._setup.user_unit ~= player then 
							return
						end
					else
						return
					end
					self:add_to_property("current_point_and_click_stacks",self:upgrade_value("player","point_and_click_stack_from_headshot_kill",0))
				end)
			else
				self._message_system:unregister(Message.OnLethalHeadShot,"proc_investment_returns_aced")
			end
			
			if self:has_category_upgrade("player","point_and_click_stack_mulligan") then 
				self._message_system:register(Message.OnEnemyKilled,"proc_mulligan_reprieve",function(weapon_unit,variant,killed_unit)
					local player = self:local_player()
					if not alive(player) then 
						return
					end
					local weapon_base = weapon_unit and weapon_unit:base()
					if weapon_base and weapon_base._setup and weapon_base._setup.user_unit and weapon_base:is_weapon_class("class_precision") then 
						if weapon_base._setup.user_unit ~= player then 
							return
						end
					else
						return
					end
					
					managers.enemy:remove_delayed_clbk("point_and_click_on_shot_missed",true)
				end)
			else
				self._message_system:unregister(Message.OnEnemyKilled,"proc_mulligan_reprieve")
			end
			
			self._message_system:register(Message.OnWeaponFired,"clear_point_and_click_stacks",function(weapon_unit,result)
				if result and result.hit_enemy then
					return
				end
				
				local player = self:local_player()
				if not alive(player) then 
					return
				end
				
				local weapon_base = weapon_unit and weapon_unit:base()
				if weapon_base and weapon_base._setup and weapon_base._setup.user_unit and weapon_base:is_weapon_class("class_precision") then 
					if weapon_base._setup.user_unit ~= player then 
						return
					end
				else
					return
				end
				
				if (self:get_property("current_point_and_click_stacks",0) > 0) and not managers.enemy:is_clbk_registered("point_and_click_on_shot_missed") then 
					managers.enemy:add_delayed_clbk("point_and_click_on_shot_missed",callback(self,self,"set_property","current_point_and_click_stacks",0),
						Application:time() + self:upgrade_value("player","point_and_click_stack_mulligan",0)
					)
				end
			end)
		else
			self._message_system:unregister(Message.OnEnemyShot,"proc_point_and_click")
			self._message_system:unregister(Message.OnWeaponFired,"clear_point_and_click_stacks")
		end
		
		if self:has_category_upgrade("weapon","magic_bullet") then 
			self._message_system:register(Message.OnLethalHeadShot,"proc_magic_bullet",function(attack_data)
				local player = self:local_player()
				if not alive(player) then 
					return
				end
				local weapon_base = attack_data.weapon_unit and attack_data.weapon_unit:base()
				if weapon_base and weapon_base._setup and weapon_base._setup.user_unit and weapon_base:is_weapon_class("class_precision") then 
					if weapon_base._setup.user_unit ~= player then 
						return
					end
				else
					return
				end
				
				if not weapon_base:ammo_full() then 
					local magic_bullet_level = self:upgrade_level("weapon","magic_bullet",0)
					local clip_current = weapon_base:get_ammo_remaining_in_clip()
					local clip_max = weapon_base:get_ammo_max_per_clip()
					local weapon_index = self:equipped_weapon_index()
					if (magic_bullet_level == 2) and (clip_current < clip_max) then
						weapon_base:set_ammo_remaining_in_clip(math.min(clip_max,clip_current + self:upgrade_value("weapon","magic_bullet",0)))
					end
					weapon_base:add_ammo_to_pool(self:upgrade_value("weapon","magic_bullet",0),self:equipped_weapon_index())
					managers.hud:set_ammo_amount(weapon_index, weapon_base:ammo_info())
					player:sound():play("pickup_ammo")
				end
			end)
		else
			self._message_system:unregister(Message.OnLethalHeadShot,"proc_magic_bullet")
		end
		
	end)
	
	function PlayerManager:movement_speed_multiplier(speed_state, bonus_multiplier, upgrade_level, health_ratio)
		local multiplier = 1
		local armor_penalty = self:mod_movement_penalty(self:body_armor_value("movement", upgrade_level, 1))
		multiplier = multiplier + armor_penalty - 1

		if bonus_multiplier then
			multiplier = multiplier + bonus_multiplier - 1
		end

		multiplier = multiplier + self:get_temporary_property("float_butterfly_movement_speed_multiplier",0)
		
		local escape_plan_status = self:get_temporary_property("escape_plan_speed_bonus",false)
		local escape_plan_sprint_bonus = 0
		local escape_plan_movement_bonus = 0

		if escape_plan_status and type(escape_plan_status) == "table" then 
			escape_plan_sprint_bonus = escape_plan_status[1] or escape_plan_sprint_bonus
			escape_plan_movement_bonus = escape_plan_status[2] or escape_plan_movement_bonus
		end
		
		if speed_state then
			multiplier = multiplier + self:upgrade_value("player", speed_state .. "_speed_multiplier", 1) - 1
			
			if speed_state == "run" then 
				multiplier = multiplier + escape_plan_sprint_bonus
			end
		end
		multiplier = multiplier + escape_plan_movement_bonus

		multiplier = multiplier + self:get_hostage_bonus_multiplier("speed") - 1
		multiplier = multiplier + self:upgrade_value("player", "movement_speed_multiplier", 1) - 1

		if self:num_local_minions() > 0 then
			multiplier = multiplier + self:upgrade_value("player", "minion_master_speed_multiplier", 1) - 1
		end

		if self:has_category_upgrade("player", "secured_bags_speed_multiplier") then
			local bags = 0
			bags = bags + (managers.loot:get_secured_mandatory_bags_amount() or 0)
			bags = bags + (managers.loot:get_secured_bonus_bags_amount() or 0)
			multiplier = multiplier + bags * (self:upgrade_value("player", "secured_bags_speed_multiplier", 1) - 1)
		end

		if managers.player:has_activate_temporary_upgrade("temporary", "berserker_damage_multiplier") then
			multiplier = multiplier * (tweak_data.upgrades.berserker_movement_speed_multiplier or 1)
		end

		if health_ratio then
			local damage_health_ratio = self:get_damage_health_ratio(health_ratio, "movement_speed")
			multiplier = multiplier * (1 + managers.player:upgrade_value("player", "movement_speed_damage_health_ratio_multiplier", 0) * damage_health_ratio)
		end

		local damage_speed_multiplier = managers.player:temporary_upgrade_value("temporary", "damage_speed_multiplier", managers.player:temporary_upgrade_value("temporary", "team_damage_speed_multiplier_received", 1))
		multiplier = multiplier * damage_speed_multiplier
		return multiplier
	end


end


		--The overshield mechanic is only used in Total Crackdown ((TCD), but its methods are present outside of TCD so that two versions of player damage for any given damage type (damage_bullet, damage_explosion, damage_melee, etc) aren't necessary for TCD and normal Crackdown

--new overshield mechanic whose sources are separate like damage absorption, and provides flat damage reduction like absorption, except the amount of damage you take is subtracted from your overshield amount.
--....so, like overshield in basically any other video game.
function PlayerManager:set_damage_overshield(id,amount,params,skip_update)
	local overshield_data
	
	for i,_overshield_data in pairs(self._damage_overshield) do 
		if _overshield_data.id == id then 
			overshield_data = _overshield_data
			break
		end
	end
	if not overshield_data then 
		local i = #self._damage_overshield + 1
		self._damage_overshield[i] = {}
		overshield_data = self._damage_overshield[i]
	end
	
	overshield_data.amount = amount
	if params then 
		if params.depleted_callback then 
			overshield_data.depleted_callback = params.depleted_callback
		end
	end
	
	--none of that Application:digest_value() nonsense here
	if not skip_update then 
		--skip_update should ideally be used when setting multiple damage overshields at once,
		--since the get_damage_overshield_total() func involves iterating over a table,
		--so it is somewhat inefficient
		self:sort_damage_overshield()
	end
end

--completely unregister a damage overshield
function PlayerManager:remove_damage_overshield(key,skip_update)
	self._damage_overshield[key] = nil
	if not skip_update then 
		self:sort_damage_overshield()
	end
end

--subtracts incoming damage from overshields, and returns remaining damage
--smaller overshield amounts are consumed first
function PlayerManager:consume_damage_overshield(damage)
	--overshield 
	if damage <= 0 then 
		return damage
	end
	local queued_remove = {}
	for i,overshield_data in ipairs(self._damage_overshield) do 
		if damage <= 0 then 
			break
		end
		local prev_overshield_amount = overshield_data.amount
		local new_overshield_amount = math.max(overshield_data.amount - damage,0)
		overshield_data.amount = new_overshield_amount
		local blocked_damage = prev_overshield_amount - new_overshield_amount
		if new_overshield_amount <= 0 then 
			if type(overshield_data.depleted_callback) == "function" then 
				overshield_data.depleted_callback(damage,blocked_damage)
				--note that this callback is performed before the player damage calculation is complete!
			end
			table.insert(queued_remove,i)
		end
		damage = damage - blocked_damage
	end
	
	if #queued_remove > 0 then 
		for i=#queued_remove,1,-1 do 
			table.remove(self._damage_overshield,queued_remove[i])
		end
	end
	self:sort_damage_overshield()
	
	return damage
end

function PlayerManager:sort_damage_overshield()
	table.sort(self._damage_overshield,function(a,b)
		return a.amount > b.amount
	end)
	
	managers.hud:set_absorb_active(HUDManager.PLAYER_PANEL, self:get_damage_overshield_total())
end

function PlayerManager:get_damage_overshield_total()
	local sum = 0
	for k,v in pairs(self._damage_overshield) do 
		sum = sum + v.amount
	end
	return sum
end
