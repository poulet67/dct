--[[
-- SPDX-License-Identifier: LGPL-3.0
--
-- Inventory class
--
--
--
--]]

-- TO DO:
-- Figure out front end architecture
-- Turn all the outText into individual messages
-- Set up a scheduled function to check for deliveries
-- When delivery detected schedule function to spawn appropriate flight
-- Check coalition of airfield (for that matter, have a means to deal with captured airfields
-- Deal with multicrew somehow

local dctutils   = require("dct.utils")
local utils   = require("libs.utils")
local JSON   = require("libs.JSON")
local class  = require("libs.namedclass")
local Logger = require("dct.libs.Logger").getByName("Inventory")
local enum        = require("dct.enum")
local Command     = require("dct.Command")
local settings    = _G.dct.settings

local Inventory = class("Inventory")
function Inventory:__init(base)
	
	--utils.tprint(base) 
	Logger:debug("INVENTORY: "..base.name)		
	self.base = base
	self._inventory = self:init_inv(base) -- the actual 'inventory table'

	
	--self.inventory_tables_path = settings.theaterpath..utils.sep.."tables"..utils.sep.."inventories"
	--self._theater = theater might be useful to have these (n.b might also be able to just grab these with requires, no need to pass anything
	--self._cmdr = cmdr
	

	
	
end

function Inventory:init_inv()
	
	local name = self.base.name
	Logger:debug("INVENTORY: "..name)	
	
	if(master_table[name]) then
		
		Logger:debug("INVENTORY FOUND: "..name)
		return master_table[name]
		
	else --no table found, issue empty inventory
	
		local empty_table = { 	
								["airframes"] = {},
								["munitions"] = {},
								["ground units"] = {},
								["naval"] = {},
								["trains"] = {},

							}
							
		master_table[name] = empty_table
		
		Logger:debug("NEW INVENTORY: "..name)
		
		return master_table[name]
	
	end

end

function compute_withdrawl_table(unit_takingOff)
	
	local withdrawl_table = { 	
						["airframes"] = {},
						["munitions"] = {},
						["ground units"] = {},
						["naval"] = {},
						["trains"] = {},
						["other"] = {},
							}
	
	local descTable = unit_takingOff:getDesc()
	local airframe = descTable.typeName	
	local ammoTable = unit_takingOff:getAmmo()
	
	withdrawl_table["airframes"][airframe] = 1 
	withdrawl_table["other"]["Flight Crew"] = master_table["crew_requirements"][airframe]
	
	utils.tprint(ammoTable)		
	Logger:debug("TABLE DUMP")	
	utils.tprint(master_table["info"])	
	
	for k,v in pairs(ammoTable) do
		local typeName = ammoTable[k].desc.typeName
		
		if(master_table["info"][typeName]["link"]) then
			
			Logger:debug("link found: "..master_table["info"][typeName]["link"])
			withdrawl_table["munitions"][master_table["info"][typeName]["link"]] = v.count
			
		else
			withdrawl_table["munitions"][typeName] = v.count
		end
	end
	
	withdrawl_table["other"]["Jet Fuel"] = (unit_takingOff:getFuel() * descTable.fuelMassMax) or 0 -- N.B WW2 era aircraft and possibly some prop planes may use avgas .. for now we will keep it all under the same umbrella
	
	--TODO: add cargo handling
	
	--end
		
	utils.tprint(withdrawl_table)	
	
	return withdrawl_table
	
end

function Inventory:handleTakeoff(event)
	
	Logger:debug("INVENTORY TAKEOFF: "..self.base.name)
	
	local unit_takingOff = event.initiator
	
	--if(unit_takingOff:getPlayerName()) then -- AI units will subtract from inventory when dispatched
		
		--Logger:debug("INVENTORY - TAKEOFF: "..unit_takingOff:getPlayerName())
		
		withdrawl_table = compute_withdrawl_table(unit_takingOff)			
		
		valid_loadout_table = self:Check(withdrawl_table)
		
		
		if(valid_loadout_table["all"]) then --Unit has a valid loadout
		
			self:Withdraw(withdrawl_table)
			
		else	
			
			outTextForGroup(unit_takingOff.groupId, "You have taken off with a configuration that is impossible given the current airbase inventory. You will be kicked to spectator upon which you will be able to re-slot into an aircraft. Please read the briefing for information on the logistics and inventory system.", 60)
			-- Kick player (somehow)
			
			--OLD
			--trigger.action.outText("Temporal anomaly detected! You will phase into nullspace in "..explode_delay.." seconds", 30)	
			--timer.scheduleFunction(explode_player, event.initiator, timer.getTime() + explode_delay) -- seconds mission time required


		end
	
	--end
	
	
end

function Inventory:handleLanding(event)

end

function Inventory:Check(withdrawl_table)
	
	local ValidLoadout = true
	local ValidTable = {}
	

	for k, v in pairs(withdrawl_table) do --Go through categories: airframes, munitions...
		
		for keys, values in pairs(withdrawl_table[k]) do					
				
			if(self._inventory[k][v]) then
								
				Logger:debug("INVENTORY check k: "..k.." v: "..v)
				
				ValidTable[v] = self._inventory[k][v]["qty"] > withdrawl_table[k][v]
				ValidLoadout = ValidTable[v] and ValidLoadout
			
			else

				ValidTable[v] = false
				ValidLoadout = false
			
			end
		end
	end
			
	utils.tprint(ValidTable)	
	
	ValidTable["all"] = ValidLoadout

	return ValidTable
	
end

function Inventory:Withdraw(withdrawl_table)
	--MAKE SURE YOU ALWAYS CHECK BEFORE WITHDRAWING!
	
	for k, v in pairs(withdrawl_table) do --Go through categories: airframes, munitions...
		
		for keys, values in pairs(withdrawl_table[k]) do
										
			Logger:debug("INVENTORY Withdraw k: "..keys.." v: "..values)			
			self._inventory[k][v]["qty"] = self._inventory[k][v]["qty"] - values
			
		end
		
	end
		
end

function generate_master()

	local path = settings.server.theaterpath..utils.sep.."tables"..utils.sep.."inventories"..utils.sep.."inventory.JSON"
	local inv_table = dctutils.read_JSON_file(path)
		
	path = settings.server.theaterpath..utils.sep.."tables"..utils.sep.."inventories"..utils.sep.."link.tbl"
	local lnk_table = dctutils.read_lua_file(path)
	
	path = settings.server.theaterpath..utils.sep.."tables"..utils.sep.."inventories"..utils.sep.."display_names.tbl"
	local dn_table = dctutils.read_lua_file(path)

	path = settings.server.theaterpath..utils.sep.."tables"..utils.sep.."inventories"..utils.sep.."master.JSON"
	local master_table = dctutils.read_JSON_file(path)
	
	path = settings.server.theaterpath..utils.sep.."tables"..utils.sep.."inventories"..utils.sep.."crew.tbl"
	local crew_table = dctutils.read_lua_file(path)

	for k,v in pairs(dn_table) do
	
		for key, value in pairs(dn_table[k]) do
			
			if(master_table[k][key]) then
			
				master_table[k][key]["displayName"] = dn_table[k][key]
			
			end
	
		end
		
	end
		
	for k,v in pairs(lnk_table) do
					
		for key, value in pairs(lnk_table[k]) do
		
			if(master_table[k][key]) then
				
				master_table[k][key]["link"] = master_table[k][lnk_table[k][key]]
			
			end
			
		end
		
	end	
		
	inv_table["info"] = master_table --to do: make sure this field can't be chosen as a base name
	inv_table["crew_requirements"] = crew_table --to do: make sure this field can't be chosen as a base name
		
	Logger:debug("INVENTORY: -- MASTER DUMP")

	return inv_table
	
end

master_table = generate_master()

--[[
function EventHandler:onEvent(event)
  onTakeoffEvent(event)
  onLandingEvent(event)
  onBirthEvent(event)  
end

--]]


--[[
function onTakeoffEvent(event)
  
	if event.id == world.event.S_EVENT_TAKEOFF then
		--trigger.action.outText("takeoff", 30)
		
		local departingAirbase = event.place:getName()		
		--trigger.action.outText(departingAirbase, 30)
		--test_ammoTable = event.initiator:getAmmo()
		--trigger.action.outText(event.initiator, 30)	
		
		
		if(Inventory_Check(event.initiator, event.place:getName())) then --Unit has a valid loadout
		
			Inventory_Checkout(event.initiator, departingAirbase)
		
		else	
		
			trigger.action.outText("Temporal anomaly detected! You will phase into nullspace in "..explode_delay.." seconds", 30)	
			timer.scheduleFunction(explode_player, event.initiator, timer.getTime() + explode_delay) -- seconds mission time required


		end
		
	end
	
  
end

function onLandingEvent(event)
  
	if event.id == world.event.S_EVENT_LAND then
	
		trigger.action.outText("Landing ------------- Inventory Transfer:", 30)
		trigger.action.outText(event.initiator:getName(), 30)
		arrivingAirbase = event.place:getName()
		
		--trigger.action.outText(arrivingAirbase, 30)
		--test_ammoTable = event.initiator:getAmmo()
		--trigger.action.outText(event.initiator, 30)	
		
		--Check if landing aircraft has any deliveries
		
		for k, v in pairs(deliveries) do
		
			if(deliveries[k].UnitAttachedto == event.initiator:getName()) then
			
				trigger.action.outText("Delivery Detected!", 30)				
				Delivery_Handoff(arrivingAirbase, event.initiator:getName())
				deliveries[k] = nil --clear this entry from the table
				break -- not sure if we will ever want multiple deliveries attached to 1 unit. Can't think of a use case, but if that happens this like will need to be removed. As is it will slightly improve performance				
				
			end
		
		end
		

		--if(Inventory_Check(event.initiator, event.place:getName())) then --Unit has a valid loadout not sure if we need to check anything really?
		
		Inventory_Handoff(event.initiator, arrivingAirbase) -- going to need to think a bit about how to deal with logistics aircraft comming and going, especially things like the C-130 having 4 crew members...
		
		--else		
		--	trigger.action.outText("Boom!", 30)	
		--	trigger.action.explosion(event.initiator:getPoint(), 50)

		--end
		
	end
	
  
end

function onBirthEvent(event)
  
	if event.id == world.event.S_EVENT_BIRTH then
		--trigger.action.outText("inside birth event", 30)		
		local position = event.initiator:getPoint()
		local CurrentAirbase = getCurrentAirbase(position.x, position.y, position.z)	
		
		missionCommands.addCommandForGroup(event.initiator:getGroup():getID(), "Check Loadout vs. Inventory", nil, Inventory_Manual_Check_Loadout, event.initiator) -- Submenus: List available weapons at current airbase, list available airframs at air base (something else?)
	
		
	--playerLocationTable[event.initiator] = 
	
	end	
  
end
		
	
end

deliveries = {}
inventories = {}
EventHandler = {}
explode_delay = 5
--playerLocationTable = {}


--Might want an entirely seperate system for deliveries
function Inventory:delivery(arrivingAirbase, UnitAttachedto)

--trigger.action.outText("DING DING DING  -------  ", 30)
--trigger.action.outText("DING DING DING  -------  "..deliveries[1].UnitAttachedto, 30)
--trigger.action.outText("DING DING DING  -------  "..deliveries[1].Cargo.PilotLives, 30)
--trigger.action.outText("DING DING DING  -------  "..deliveries[1].Cargo.Weapons[1].quantity, 30)


	for k, v in pairs(deliveries) do
			
		if(deliveries[k].UnitAttachedto == UnitAttachedto) then
		
				PilotsDelivered = deliveries[k].Cargo.PilotLives				
				trigger.action.outText("PilotLives"..PilotsDelivered, 30)				
				FuelDelivered = deliveries[k].Cargo.Fuel				
				WeaponsDelivered = deliveries[k].Cargo.Weapons
				--GroundUnitsDelivered = deliveries[k].Cargo.GroundUnits
				Inventory_Add_Pilots(arrivingAirbase, PilotsDelivered)
				Inventory_Add_Fuel(arrivingAirbase, FuelDelivered)
				
				for key, value in pairs(WeaponsDelivered) do
				
					Inventory_Add_Weapon(WeaponsDelivered[key].displayName, arrivingAirbase, WeaponsDelivered[key].quantity)
				
				end	
				
				break
	
		end
		
	end
end
--]]
	
function Inventory:check_loadout(MunitionTable)

	--MunitionTable:
	--A table of the munitions carried 

	Logger:debug("INVENTORY --- CHECKING LOADOUT")
	
	currentAirbase = getCurrentAirbase(playerUnit:getPoint().x,playerUnit:getPoint().y,playerUnit:getPoint().z)
	
	local valid = Inventory_Check(playerUnit)
	
	if(valid) then
		
		message = "Your loadout is approved, you may proceed."
		
	elseif(not(valid)) then
		
		message = "You currently in an airframe or have weapons equipped that do not exist at this airbase. Temporal paradoxes are NOT permitted. Please change your loadout before takeoff."
		
	end
	
	return message
	
end

--[[
function Inventory:checkout(playerUnit, currentAirbase)

	trigger.action.outText("INVENTORY CHECKOUT REPORT:", 30)
	
	descTable = playerUnit:getDesc()
	
	currentFuelPct = playerUnit:getFuel()	
	fuelMassMax = descTable.fuelMassMax	
	myFuel = fuelMassMax*currentFuelPct	
	
	--First Level stuff
	
	for k, v in pairs(inventories) do
	
		if(inventories[k].Airbase == currentAirbase) then			
	
		--PilotLives
		
			inventories[k].PilotLives = inventories[k].PilotLives - 1 -- Ways this can break: Multicrew
			trigger.action.outText("1 Pilot withdrawn from "..currentAirbase.." "..inventories[k].PilotLives.." remain", 30)
			--Fuel
			inventories[k].Fuel = inventories[k].Fuel-myFuel
			trigger.action.outText(myFuel.." kg of fuel withdrawn from "..currentAirbase.." "..inventories[k].Fuel.." kg remain", 30)
			
		end
		
		
	end
	
	
	AirframeName = descTable.displayName		

	for key, value in pairs(inventories) do
	
		if(inventories[key].Airbase == currentAirbase) then				-- might have to think about this a bit in the case of multiple inventories that are assigned to the same airbase...
			
			for Key, Value in pairs(inventories[key].Airframes) do
			
				if(inventories[key].Airframes[Key].displayName == AirframeName) then
					--trigger.action.outText("Airframes ding", 30)
					inventories[key].Airframes[Key].quantity = inventories[key].Airframes[Key].quantity - 1
					trigger.action.outText("1 Airframe of type "..AirframeName.." withdrawn from "..currentAirbase.." "..inventories[key].Airframes[Key].quantity.." remain", 30)
					break
					
				end
			end
			
			break
			
		end
	end	
	
	-- Weapons
	ammoTable = playerUnit:getAmmo()
	
	if(ammoTable ~= nil) then	
	
		for k,v in pairs(ammoTable) do
		
			number = v.count
			WeaponName = v.desc.displayName
			
			--trigger.action.outText(number, 30)
			--trigger.action.outText(WeaponName, 30)
			--trigger.action.outText(currentAirbase, 30)
			
			for key, value in pairs(inventories) do
			
				if(inventories[key].Airbase == currentAirbase) then				.
					
					for Key, Value in pairs(inventories[key].Weapons) do
					
						if(inventories[key].Weapons[Key].displayName == WeaponName) then
							--trigger.action.outText("DING DING DING:", 30)
							inventories[key].Weapons[Key].quantity = inventories[key].Weapons[Key].quantity - number
							trigger.action.outText(number.." weapons of type "..WeaponName.." withdrawn "..inventories[key].Weapons[Key].quantity.." remain", 30)
							break
							
						end
					end
					
					break
					
				end
			end
		end
	end
	

end
]]--
--[[
function Inventory:handoff(playerUnit, currentAirbase)
	
	--To do: include fuel, airframes and pilots.

	trigger.action.outText("ITEMS DELIVERED:", 30)
	
	
	descTable = playerUnit:getDesc()
	
	currentFuelPct = playerUnit:getFuel()	
	fuelMassMax = descTable.fuelMassMax	
	myFuel = fuelMassMax*currentFuelPct	
	
	--First Level stuff
	
	for k, v in pairs(inventories) do
	
		if(inventories[k].Airbase == currentAirbase) then			
	
		--PilotLives
		
			inventories[k].PilotLives = inventories[k].PilotLives + 1 -- Ways this can break: Multicrew
			trigger.action.outText("1 Pilot transferred to "..currentAirbase.." "..inventories[k].PilotLives.." now in stock", 30)
			--Fuel
			inventories[k].Fuel = inventories[k].Fuel+myFuel
			trigger.action.outText(myFuel.." kg of fuel transferred to "..currentAirbase.." "..inventories[k].Fuel.." kg now in stock", 30)
			
		end
		
		
	end
	
	
	AirframeName = descTable.displayName		

	for key, value in pairs(inventories) do
	
		if(inventories[key].Airbase == currentAirbase) then				-- might have to think about this a bit in the case of multiple inventories that are assigned to the same airbase...
			
			for Key, Value in pairs(inventories[key].Airframes) do
			
				if(inventories[key].Airframes[Key].displayName == AirframeName) then
					--trigger.action.outText("Airframes ding", 30)
					inventories[key].Airframes[Key].quantity = inventories[key].Airframes[Key].quantity + 1
					trigger.action.outText("1 Airframe of type "..AirframeName.." transferred to "..currentAirbase.." "..inventories[key].Airframes[Key].quantity.." now in stock", 30)
					break
					
				end
			end
			
			break
			
		end
	end	
	
	AirframeName = descTable.displayName		


	-- Weapons
	
	ammoTable = playerUnit:getAmmo()
	
	
	if(ammoTable ~= nil) then	
	
		for k,v in pairs(ammoTable) do
		
			number = v.count
			WeaponName = v.desc.displayName
			
			--trigger.action.outText(number, 30)
			--trigger.action.outText(WeaponName, 30)
			--trigger.action.outText(currentAirbase, 30)
			
			for key, value in pairs(inventories) do
			
				if(inventories[key].Airbase == currentAirbase) then				-- might have to think about this a bit in the case of multiple inventories that are assigned to the same airbase...
					
					for Key, Value in pairs(inventories[key].Weapons) do
					
						if(inventories[key].Weapons[Key].displayName == WeaponName) then
							--trigger.action.outText("DING DING DING:", 30)
							inventories[key].Weapons[Key].quantity = inventories[key].Weapons[Key].quantity + number
							trigger.action.outText("There are now"..inventories[key].Weapons[Key].quantity.." "..WeaponName.." at "..currentAirbase, 30)
							break
							
						end
					end
					
					break
					
				end
			end
		end
	end
	

end

function Inventory:Add_Weapon(WeaponName, InvAirbase, quantitytoAdd)

	for key, value in pairs(inventories) do
	
		if(inventories[key].Airbase == InvAirbase) then				-- might have to think about this a bit in the case of multiple inventories that are assigned to the same airbase...
			
			for Key, Value in pairs(inventories[key].Weapons) do
			
				if(inventories[key].Weapons[Key].displayName == WeaponName) then

					inventories[key].Weapons[Key].quantity = inventories[key].Weapons[Key].quantity + quantitytoAdd
					
					trigger.action.outText("There are now"..inventories[key].Weapons[Key].quantity.." "..WeaponName.." at "..InvAirbase, 30)
					
					break
					
				end
			end
			
			break
			
		end
	end


end

function Inventory:Add_Fuel(InvAirbase, quantitytoAdd)

	for key, value in pairs(inventories) do
	
		if(inventories[key].Airbase == InvAirbase) then				

			inventories[key].Fuel = inventories[key].Fuel + quantitytoAdd
			
			trigger.action.outText("There is now"..inventories[key].Fuel.." kg of Fuel at"..InvAirbase, 30)
					
			break
					
		end


	end


end

function Inventory:Add_Pilots(InvAirbase, quantitytoAdd)


	for key, value in pairs(inventories) do
	
		if(inventories[key].Airbase == InvAirbase) then				

			inventories[key].PilotLives = inventories[key].PilotLives + quantitytoAdd
			
			trigger.action.outText("There is now"..inventories[key].PilotLives.." kg of Fuel at"..InvAirbase, 30)
					
			break
					
		end


	end


end

function Inventory:Add_GroundUnit(UnitName, InvAirbase, quantitytoAdd)

-- not yet implemented

end
--]]

--[[
function Inventory:get_weapon_qty(WeaponName, currentAirbase)
	
	local num_weapons = 0;
	
	for k, v in pairs(inventories) do

		--trigger.action.outText("QTY CHECK:", 30)
		--trigger.action.outText("key:"..k, 30)
		--trigger.action.outText("airbase"..currentAirbase, 30)
		--trigger.action.outText("test"..inventories[k].Airbase, 30)
		
		if(inventories[k].Airbase == currentAirbase) then
			
		 	for key, value in pairs(inventories[k].Weapons) do
				
				if(inventories[k].Weapons[key].displayName == WeaponName) then
					num_weapons = num_weapons + inventories[k].Weapons[key].quantity
					break
				end
			
			end
		end
	end
	
	trigger.action.outText("There are "..num_weapons.." weapons of type "..WeaponName.." at "..currentAirbase, 30)
	
	return num_weapons
			
end

function Inventory_Find_Airframe_Qty(AirframeName, currentAirbase)
	
	local num_airframes = 0;
	
	for k, v in pairs(inventories) do

		if(inventories[k].Airbase == currentAirbase) then
			
		 	for key, value in pairs(inventories[k].Airframes) do
				
				if(inventories[k].Airframes[key].displayName == AirframeName) then

					num_airframes = num_airframes + inventories[k].Airframes[key].quantity
					--trigger.action.outText("count"..num_airframes, 30)
					break
				end
			
			end
		end
	end
	
	trigger.action.outText("There are "..num_airframes.." airframes of type "..AirframeName.." at "..currentAirbase, 30)
	
	return num_airframes
			
end

function Inventory_Find_PilotLives_Qty(currentAirbase)
	
	local PilotLives = 0;
	
	for k, v in pairs(inventories) do

		if(inventories[k].Airbase == currentAirbase) then
				
			PilotLives = inventories[k].PilotLives
				
		end
	end
	
	trigger.action.outText("There are "..PilotLives.." pilots available at "..currentAirbase, 30)
	
	return PilotLives
			
end

function Inventory_Find_Fuel_Qty(currentAirbase)
		
	local FuelQty = 0;
	
	for k, v in pairs(inventories) do

		if(inventories[k].Airbase == currentAirbase) then
				
			FuelQty = inventories[k].Fuel
				
		end
	end
	
	trigger.action.outText("There is "..FuelQty.." kg of fuel at "..currentAirbase, 30)
	
	return FuelQty
			
end


function check_for_deliveries() --TBC

    trigger.action.outText("Checking for deliveries", 30)	
	
 	file = io.open("", "w+") 
	file:write(JSON:encode_pretty(inventories))
	file:close()  

	
end
]]--
--[[
function explode_player(playerUnit)

    trigger.action.outText("KABOOM!", 30)	
	trigger.action.explosion(playerUnit:getPoint(), 100)
	
end
]]--

return Inventory