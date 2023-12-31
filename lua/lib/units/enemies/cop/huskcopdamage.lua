function HuskCopDamage:die(attack_data)
	if not managers.enemy:is_corpse_disposal_enabled() then
		local unit_pos = self._unit:position()
		local unit_rot = self._unit:rotation()

		managers.network:session():send_to_peers_synched("sync_fall_position", self._unit, unit_pos, unit_rot)
	end

	CopDamage.MAD_3_ACHIEVEMENT(attack_data)
	self:_check_friend_4(attack_data)
	self:_remove_debug_gui()
	self._unit:base():set_slot(self._unit, 17)

	if self._unit:inventory() then
		self._unit:inventory():drop_shield()
	end

	attack_data.variant = attack_data.variant or "bullet"
	self._health = 0
	self._health_ratio = 0
	self._dead = true

	self:set_mover_collision_state(false)

	if self._unit:interaction() and self._unit:interaction().tweak_data == "hostage_convert" then
		self._unit:interaction():set_active(false)
	end

	if self._death_sequence and self._unit:damage() and self._unit:damage():has_sequence(self._death_sequence) then
		self._unit:damage():run_sequence_simple(self._death_sequence)
	end

	if self._unit:base().has_tag and self._unit:base():has_tag("spooc") then
		if self._char_tweak.die_sound_event then
			self._unit:sound():play(self._char_tweak.die_sound_event) --ensure that spoocs stop their looping presence sound
		end

		--if not self._unit:movement():cool() then --optional, to reinforce the idea of silent kills if desired
			self._unit:sound():say("x02a_any_3p") --death voiceline, can't use char_tweak().die_sound_event since spoocs have the presence loop stop there (this ensures both are played, unlike in vanilla)
		--end

		if self._unit:damage() and self._unit:damage():has_sequence("kill_spook_lights") then
			self._unit:damage():run_sequence_simple("kill_spook_lights")
		end
	else
		--if not self._unit:movement():cool() then
		if self._char_tweak.die_sound_event then --death voiceline determined through char_tweak().die_sound_event, otherwise use default
			self._unit:sound():say(self._char_tweak.die_sound_event)
		else
			self._unit:sound():say("x02a_any_3p")
		end
		--end
	end

	if self._unit:base().looping_voice then
		self._unit:base().looping_voice:set_looping(false)
		self._unit:base().looping_voice:stop()
		self._unit:base().looping_voice:close()
		self._unit:base().looping_voice = nil
	end

	--[[if self._unit:base():char_tweak().ends_assault_on_death then
		managers.hud:set_buff_enabled("vip", false)
	end]]

	self:_on_death()
	--to add later after adding some mutator fixes, if even wanted
	--managers.mutators:notify(Message.OnCopDamageDeath, self, attack_data)
end

if deathvox:IsTotalCrackdownEnabled() then
	HuskCopDamage._NET_EVENTS = {
		set_drill_shock_tase_time = 1,
		set_joker_no_hurts = 2,
		joker_regen = 3
	}

	function HuskCopDamage:sync_net_event(event_id)
		local net_events = HuskCopDamage._NET_EVENTS

		if event_id == net_events.set_drill_shock_tase_time then
			self._tased_time = tweak_data.upgrades.values.player.drill_shock_tase_time
		elseif event_id == net_events.set_joker_no_hurts then
			local char_tweaks = deep_clone(self._unit:base()._char_tweak)

			char_tweaks.damage.hurt_severity = tweak_data.character.presets.hurt_severities.no_hurts_no_tase
			char_tweaks.can_be_tased = false
			char_tweaks.use_animation_on_fire_damage = false
			char_tweaks.immune_to_knock_down = true
			char_tweaks.immune_to_concussion = true

			self._unit:base()._char_tweak = char_tweaks
			self._unit:character_damage()._char_tweak = char_tweaks
			self._unit:movement()._tweak_data = char_tweaks
			self._unit:movement()._action_common_data.char_tweak = char_tweaks
		elseif event_id == net_events.joker_regen then
			local regen_percent = 0.025 --placerholder, tweakdata upgrade value here
			local init_health = self._HEALTH_INIT
			local new_health = init_health * regen_percent + self._health

			if new_health >= init_health then
				self._health = init_health
				self._health_ratio = 1
			else
				self._health = new_health
				self._health_ratio = new_health / init_health
			end

			self:_update_debug_ws()
		end
	end
end
