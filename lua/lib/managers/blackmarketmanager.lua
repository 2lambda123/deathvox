if deathvox:IsTotalCrackdownEnabled() then
	
	Hooks:PostHook(BlackMarketManager,"get_sorted_grenades","tcd_blackmarketmanager_get_sorted_grenades",function(self,hide_locked)
		local sort_data = Hooks:GetReturn()
		for i=#sort_data,1,-1 do 
			local data = sort_data[i]
			
			local id = data[1]
			local ptd = tweak_data.blackmarket.projectiles[id]
			if ptd and ptd.is_from_perk_deck then
				--hide perk deck throwables
				table.remove(sort_data,i)
			end
		end
	end)
	
	function BlackMarketManager:has_equipped_ability()
		return self:equipped_ability() and true
	end
	
	--this function added in tcd;
	--if ability exists, returns two arguments: (string) ability_id, (int) current_amount
	--else, returns nil
	function BlackMarketManager:equipped_ability()
		local current_specialization = managers.skilltree:digest_value(managers.skilltree._global.specializations.current_specialization, false, 1)
		
		local perkdeck_data = current_specialization and tweak_data.skilltree.specializations[current_specialization]
		if perkdeck_data then
			local ability_id = perkdeck_data.ability_id
			if ability_id then
				return ability_id,Global.blackmarket_manager.grenades[ability_id].amount or 0
					--or tweak_data.blackmarket.projectiles[ability_id].max_amount
			end
		end
	end
	
	function BlackMarketManager:on_aquired_grenade(upgrade, id, loading)
		if not self._global.grenades[id] then
			--Application:error("[BlackMarketManager:on_aquired_grenade] Grenade do not exist in blackmarket", "grenade_id", id)

			return
		end

		self._global.grenades[id].unlocked = true
		self._global.grenades[id].owned = true
		self._global.grenades[id].amount = managers.player:get_max_grenades(id)

		if not loading then
			self._global.new_drops.normal = self._global.new_drops.normal or {}
			self._global.new_drops.normal.grenades = self._global.new_drops.normal.grenades or {}
			self._global.new_drops.normal.grenades[id] = true

			if self._global.grenades[id].ability then
				--self:equip_grenade(id)
				--no! bad!
			end
		end
	end
	
	function BlackMarketManager:recoil_addend(name, categories, recoil_index, silencer, blueprint, current_state, is_single_shot)
		local addend = 0
		local wfm = managers.weapon_factory
		local factory_id = wfm:get_factory_id_by_weapon_id(name)
		
		if recoil_index and recoil_index >= 1 and recoil_index <= #tweak_data.weapon.stats.recoil then
			local index = recoil_index
			index = index + managers.player:upgrade_value("weapon", "recoil_index_addend", 0)
			index = index + managers.player:upgrade_value("player", "stability_increase_bonus_1", 0)
			index = index + managers.player:upgrade_value("player", "stability_increase_bonus_2", 0)
			index = index + managers.player:upgrade_value(name, "recoil_index_addend", 0)
			
			for _, category in ipairs(categories) do
				index = index + managers.player:upgrade_value(category, "recoil_index_addend", 0)
			end
			
			local pm = managers.player
			local player_unit = pm:player_unit()
			
			if player_unit and player_unit:character_damage():is_suppressed() then
				for _, category in ipairs(categories) do
					if managers.player:has_team_category_upgrade(category, "suppression_recoil_index_addend") then
						index = index + managers.player:team_upgrade_value(category, "suppression_recoil_index_addend", 0)
					end
				end

				if managers.player:has_team_category_upgrade("weapon", "suppression_recoil_index_addend") then
					index = index + managers.player:team_upgrade_value("weapon", "suppression_recoil_index_addend", 0)
				end
			else
				for _, category in ipairs(categories) do
					if managers.player:has_team_category_upgrade(category, "recoil_index_addend") then
						index = index + managers.player:team_upgrade_value(category, "recoil_index_addend", 0)
					end
				end

				if managers.player:has_team_category_upgrade("weapon", "recoil_index_addend") then
					index = index + managers.player:team_upgrade_value("weapon", "recoil_index_addend", 0)
				end
			end

			if silencer then
				index = index + managers.player:upgrade_value("weapon", "silencer_recoil_index_addend", 0)

				for _, category in ipairs(categories) do
					index = index + managers.player:upgrade_value(category, "silencer_recoil_index_addend", 0)
				end
			end

			if blueprint and self:is_weapon_modified(factory_id, blueprint) then
				index = index + managers.player:upgrade_value("weapon", "modded_recoil_index_addend", 0)
			end

			index = math.clamp(index, 1, #tweak_data.weapon.stats.recoil)

			if index ~= recoil_index then
				local diff = tweak_data.weapon.stats.recoil[index] - tweak_data.weapon.stats.recoil[recoil_index]
				addend = addend + diff
			end
		end

		return addend
	end

	--this function added in tcd;
	--it should account for the class/subclass-specific bonuses 
	--when used in the menu or other situation where the weapon base is not instantiated,
	--but otherwise it should be kept identical to recoil_addend().
	--DO NOT call every frame! heck, don't even use it mid-heist
	function BlackMarketManager:recoil_addend_menu(name, categories, recoil_index, silencer, blueprint, current_state, is_single_shot)
		
		local addend = 0
		local wfm = managers.weapon_factory
		local factory_id = wfm:get_factory_id_by_weapon_id(name)
		
		--local primary_class = wfm:get_primary_weapon_class_from_blueprint(name,blueprint)
		local subclasses = wfm:get_weapon_subclasses_from_blueprint(name,blueprint)
		
		if recoil_index and recoil_index >= 1 and recoil_index <= #tweak_data.weapon.stats.recoil then
			local index = recoil_index
			index = index + managers.player:upgrade_value("weapon", "recoil_index_addend", 0)
			index = index + managers.player:upgrade_value("player", "stability_increase_bonus_1", 0)
			index = index + managers.player:upgrade_value("player", "stability_increase_bonus_2", 0)
			index = index + managers.player:upgrade_value(name, "recoil_index_addend", 0)
			
			for _, category in ipairs(categories) do
				index = index + managers.player:upgrade_value(category, "recoil_index_addend", 0)
			end
			
			local pm = managers.player
			local player_unit = pm:player_unit()
			
			if player_unit and player_unit:character_damage():is_suppressed() then
				for _, category in ipairs(categories) do
					if managers.player:has_team_category_upgrade(category, "suppression_recoil_index_addend") then
						index = index + managers.player:team_upgrade_value(category, "suppression_recoil_index_addend", 0)
					end
				end

				if managers.player:has_team_category_upgrade("weapon", "suppression_recoil_index_addend") then
					index = index + managers.player:team_upgrade_value("weapon", "suppression_recoil_index_addend", 0)
				end
			else
				for _, category in ipairs(categories) do
					if managers.player:has_team_category_upgrade(category, "recoil_index_addend") then
						index = index + managers.player:team_upgrade_value(category, "recoil_index_addend", 0)
					end
				end

				if managers.player:has_team_category_upgrade("weapon", "recoil_index_addend") then
					index = index + managers.player:team_upgrade_value("weapon", "recoil_index_addend", 0)
				end
			end
			
			for _,subclass in pairs(subclasses) do 
				index = index + managers.player:upgrade_value(subclass,"subclass_stability_addend",0)
			end
			
			if silencer then
				index = index + managers.player:upgrade_value("weapon", "silencer_recoil_index_addend", 0)

				for _, category in ipairs(categories) do
					index = index + managers.player:upgrade_value(category, "silencer_recoil_index_addend", 0)
				end
			end

			if blueprint and self:is_weapon_modified(factory_id, blueprint) then
				index = index + managers.player:upgrade_value("weapon", "modded_recoil_index_addend", 0)
			end

			index = math.clamp(index, 1, #tweak_data.weapon.stats.recoil)

			if index ~= recoil_index then
				local diff = tweak_data.weapon.stats.recoil[index] - tweak_data.weapon.stats.recoil[recoil_index]
				addend = addend + diff
			end
		end

		return addend
	end
	
	function BlackMarketManager:fire_rate_multiplier(name, categories, silencer, detection_risk, current_state, blueprint)
		local subclasses = managers.weapon_factory:get_weapon_subclasses_from_blueprint(name,blueprint)
		local multiplier = 1
		multiplier = multiplier + 1 - managers.player:upgrade_value(name, "fire_rate_multiplier", 1)
		multiplier = multiplier + 1 - managers.player:upgrade_value("weapon", "fire_rate_multiplier", 1)

		for _, category in ipairs(categories) do
			multiplier = multiplier + 1 - managers.player:upgrade_value(category, "fire_rate_multiplier", 1)
		end
		
		for _, subclass in pairs(subclasses) do
			if managers.player:has_category_upgrade(subclass,"subclass_detection_risk_rof_bonus") then 
				local detection_risk_add_firerate = managers.player:upgrade_value(subclass, "subclass_detection_risk_rof_bonus")
				multiplier = multiplier - managers.player:get_value_from_risk_upgrade(detection_risk_add_firerate, detection_risk)
				--log("multiplier is: " .. multiplier .. "")
			end
			
		end

		return self:_convert_add_to_mul(multiplier)
	end

	function BlackMarketManager:_calculate_weapon_concealment(weapon)
		local factory_id = weapon.factory_id
		local weapon_id = weapon.weapon_id or managers.weapon_factory:get_weapon_id_by_factory_id(factory_id)
		local blueprint = weapon.blueprint
		local base_stats = tweak_data.weapon[weapon_id].stats
		local modifiers_stats = tweak_data.weapon[weapon_id].stats_modifiers
		local bonus = 0
		
		local subclasses = managers.weapon_factory:get_weapon_subclasses_from_blueprint(weapon_id,blueprint)

		if not base_stats or not base_stats.concealment then
			return 0
		end

		local bonus_stats = {}

		if weapon.cosmetics and weapon.cosmetics.id and weapon.cosmetics.bonus and not managers.job:is_current_job_competitive() and not managers.weapon_factory:has_perk("bonus", factory_id, blueprint) then
			bonus_stats = tweak_data:get_raw_value("economy", "bonuses", tweak_data.blackmarket.weapon_skins[weapon.cosmetics.id].bonus, "stats") or {}
		end

		local parts_stats = managers.weapon_factory:get_stats(factory_id, blueprint)
		
		for _,subclass_id in pairs(subclasses) do 
			bonus = bonus + managers.player:upgrade_value(subclass_id,"subclass_concealment_addend")
		end

		return (base_stats.concealment + bonus + (parts_stats.concealment or 0) + (bonus_stats.concealment or 0)) * (modifiers_stats and modifiers_stats.concealment or 1)
	end

	function BlackMarketManager:visibility_modifiers()
		local skill_bonuses = 0
		
		if managers.player:has_category_upgrade("player", "burglar_max_concealment") then
			return -232
		end
		
		skill_bonuses = skill_bonuses - managers.player:upgrade_value("player", "passive_concealment_modifier", 0)
		skill_bonuses = skill_bonuses - managers.player:upgrade_value("player", "concealment_modifier", 0)
		skill_bonuses = skill_bonuses - managers.player:upgrade_value("player", "melee_concealment_modifier", 0)
		local armor_data = tweak_data.blackmarket.armors[managers.blackmarket:equipped_armor(true, true)]

		if armor_data.upgrade_level == 2 or armor_data.upgrade_level == 3 or armor_data.upgrade_level == 4 then
			skill_bonuses = skill_bonuses - managers.player:upgrade_value("player", "ballistic_vest_concealment", 0)
		end

		local silencer_bonus = 0
		silencer_bonus = silencer_bonus + self:get_silencer_concealment_modifiers(self:equipped_primary())
		silencer_bonus = silencer_bonus + self:get_silencer_concealment_modifiers(self:equipped_secondary())
		skill_bonuses = skill_bonuses - silencer_bonus

		return skill_bonuses
	end

end