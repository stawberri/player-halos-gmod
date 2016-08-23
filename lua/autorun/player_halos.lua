-- Create variables
CreateConVar( "player_halos", 1, { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "Draw player halos around players. Make this 0 to disable them, 1 to enable them some of the time (according to your other settings), 2 to keep them always on, and 3 to always have them on as long as 'disallow' conditions aren't met." )
CreateConVar( "player_halos_npcs", 0,  { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "Set this to a color in the r g b format of \"[0-1] [0-1] [0-1]\" to make halos be drawn around NPCs as well. For example, to make them a dark greenish yellow: \"player_halos_npcs .25 .3 0\"" )
CreateConVar( "player_halos_color", 0,  { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "Sets color for player halos. Set this to 0 to use each player's personal colors. Set this to 1 to use team colors." )

if CLIENT then
	-- This function helps with converting vectors in the format of <1,1,1> to colors (r, g, b, a), while ensuring they stay visible.
	local minColorVec = Vector( 0.25, 0.25, 0.25 ) -- This is the darkest allowed color.
	local function VecToColor( vect, alpha )
		-- Don't affect our input, in case it's needed elsewhere. Everything should be positive too.
		vec = Vector( math.abs( vect.x ), math.abs( vect.y ), math.abs( vect.z ) )
		if vec.x < minColorVec.x and vec.y < minColorVec.y and vec.z < minColorVec.z then
			vec:Add( minColorVec )
		end
		-- Not sure what happens if you try to make a color with values greater than 255, so just to be safe~
		if vec.x > 1 then vec.x = 1 end
		if vec.y > 1 then vec.y = 1 end
		if vec.z > 1 then vec.z = 1 end
		vec:Mul( 255 )

		if alpha == nil then return Color( vec.x, vec.y, vec.z, 255 )
		else return Color( vec.x, vec.y, vec.z, alpha )
		end
	end

	-- This gets NPCs' glow color.
	local function GetNPCColor()
		local colorTable = string.Explode( " ", GetConVarString( "player_halos_npcs" ) )
		if #colorTable < 3 then return end -- If there aren't enough parameters, return
		local r = tonumber( colorTable[1] )
		local g = tonumber( colorTable[2] )
		local b = tonumber( colorTable[3] )
		if r == nil or g == nil or b == nil then return end -- If the parameters couldn't be converted to numbers, return
		return VecToColor( Vector( r, g, b ) ) -- Return the color.
	end

	-- This decides if we should draw halos.
	local function ShouldDrawHalo( myself, ply, isNPC )
		local enabled = GetConVarNumber( "player_halos" )
		if enabled == 0 then return false end -- Disabled
		if enabled == 2 then return true end -- Always on

		if hook.Run( "PlayerHalosShouldNotDraw", myself, ply, isNPC ) then return false end

		if enabled == 3 then return true end -- On if nothing is disallowing

		return hook.Run( "PlayerHalosShouldDraw", myself, ply, isNPC )
	end

	-- This is just to simplify halo.Add calls.
	local function DrawPlayerHalo( ent, color )
		halo.Add( { ent }, color, 1, 1, 1, true, true )
	end

	--[[ This code can be used if npc detection per frame is too intensive.
	local npcTable = {}
	timer.Create( "playerHalosNpcTableUpdater", 1, 0, function()
		if GetNPCColor() ~= nil then
			local currentNPCTable = {}
			local allEnts = ents.GetAll()
			for _, npc in pairs(allEnts) do
				if IsValid( npc ) and npc:IsNPC() then
					currentNPCTable[ #currentNPCTable + 1 ] = npc -- add to end
				end
			end
			npcTable = currentNPCTable
		else
			npcTable = {}
		end
	end )
	]]

	-- This is my main function!
	local function DrawPlayerHalos()
		if not LocalPlayer():IsValid() then return end -- If there's no player, stuff here might have issues.
		local players = player.GetAll()
		for _, ply in pairs(players) do 
			if ply:IsValid() then -- If they're not valid, things might blow up!
				if ShouldDrawHalo( LocalPlayer(), ply ) then -- First we check if we should even draw their halo in the first place
					local colorMode = GetConVarNumber( "player_halos_color" )
					local color = VecToColor( ply:GetPlayerColor() )
					-- Alternate color modes.
					if colorMode == 1 then
						color = team.GetColor( ply:Team() )
					end
					if ply:Alive() then -- If they're not alive, their player halo floats next to their corpse.
						local physgun = ply:GetVar( "PlayerHalosPhysgunActive", nil ) -- Grab value saved in function below
						-- If colormode is 0, adjust to physgun color.
						if IsValid( colorMode == 0 and physgun ) then -- Is their physgun active?
							-- If it is, we should set their color to their active physgun color and then draw a glow on their physgun.
							local physColor = VecToColor( ply:GetWeaponColor() + VectorRand() * 0.3 ) -- I borrowed this from Gmod's physgun glow script.
							DrawPlayerHalo( physgun, physColor )
							DrawPlayerHalo( ply, physColor )
						else
							local weapon = ply:GetActiveWeapon() -- Find their weapon
							if IsValid( weapon ) then
								DrawPlayerHalo( weapon, color ) -- Draw a halo around their weapon.
							end
							DrawPlayerHalo( ply, color ) -- Draw a halo around them.
						end
					else -- If they're dead, we can highlight their ragdoll instead.
						local plyRagdoll = ply:GetRagdollEntity()
						if IsValid( plyRagdoll ) then -- Make sure it still exists, though.
							DrawPlayerHalo( plyRagdoll, color )
						end
					end
				end
			end
		end
		-- Adding NPCs as an entirely new loop here. Makes code redundant and probably more intensive, but less confusing.
		local npcColor = GetNPCColor()
		if npcColor ~= nil then -- this function can actually be used to check if npc colors are enabled.
			local allEnts = ents.GetAll()
			for _, npc in pairs(allEnts) do
				if IsValid( npc ) and npc:IsNPC() then -- Check this again just in case it changed since it was last called.
					if ShouldDrawHalo( LocalPlayer(), npc, true ) then
						local weapon = npc:GetActiveWeapon()
						if IsValid( weapon ) then
							DrawPlayerHalo( weapon, npcColor )
						end
						DrawPlayerHalo( npc, npcColor )
					end
				end
			end
		end
	end
	hook.Add( "PreDrawHalos", "PlayerHalosDrawPlayerHalos", DrawPlayerHalos )

	-- For some reason there isn't a way to actually check if someone is using their physgun or not from a function, so I need to use this hook.
	local function IsPhysgunning( ply, physgun, enabled, target, bone, hitPos )
		if enabled then ply:SetVar( "PlayerHalosPhysgunActive", physgun ) -- Saving their physgun object here makes it easier to find it again with less work later on.
		else ply:SetVar( "PlayerHalosPhysgunActive", nil ) end
	end
	hook.Add( "DrawPhysgunBeam", "PlayerHalosPhysgunning", IsPhysgunning)
end

-- Team Only

CreateConVar( "player_halos_team_only", 0, { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "Player halos will only appear around team members." )

if CLIENT then
	hook.Add( "PlayerHalosShouldNotDraw", "PlayerHalosObstructed", function( myself, ply, isNPC )
		if not isNPC and GetConVarNumber( "player_halos_team_only" ) ~= 0 then
			if not myself:Team() == ply:Team() then return true end
		end
	end )
end

-- Distant Players

CreateConVar( "player_halos_unobstructed_dist", 1000, { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "Halos will appear around players farther than this distance, even if there is nothing obstructing them. Set this to 0 if halos should never appear because of this." )

if CLIENT then
	hook.Add( "PlayerHalosShouldDraw", "PlayerHalosFarPlayers", function( myself, ply )
		local minDist = GetConVarNumber( "player_halos_unobstructed_dist" )
		if minDist > 0 and myself:GetViewEntity():GetPos():Distance( ply:GetPos() ) > minDist then return true end
	end )
end

-- Flashlight

CreateConVar( "player_halos_flashlight", 1, { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "Other players' halos will appear when your flashlight is on." )
CreateConVar( "player_halos_flashlight_them", 0, { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "Everyone will see your halo when your flashlight is on." )

if CLIENT then
	hook.Add( "PlayerHalosShouldDraw", "PlayerHalosFlashlightOn", function( myself, ply )
		if GetConVarNumber( "player_halos_flashlight" ) ~= 0 then
			if myself:FlashlightIsOn() then return true end
		end
	end )

	hook.Add( "PlayerHalosShouldDraw", "PlayerHalosTheirFlashlightOn", function( myself, ply, isNPC )
		if not isNPC and GetConVarNumber( "player_halos_flashlight_them" ) ~= 0 then
			if ply:FlashlightIsOn() then return true end
		end
	end )
end

-- Obstructed

CreateConVar( "player_halos_obstructed", 1, { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "Player halos will appear for people blocked by something else (like walls)." )

if CLIENT then
	hook.Add( "PlayerHalosShouldDraw", "PlayerHalosObstructed", function( myself, ply )
		if GetConVarNumber( "player_halos_obstructed" ) ~= 0 then
			if not myself:GetViewEntity():IsLineOfSightClear( ply ) then return true end
		end
	end )
end

-- Vehicle
CreateConVar( "player_halos_vehicle", 0, { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "Player halos will appear when you are in a vehicle." )

if CLIENT then
	hook.Add( "PlayerHalosShouldDraw", "PlayerHalosVehicle", function( myself, ply )
		if GetConVarNumber( "player_halos_vehicle" ) ~= 0 then
			if myself:InVehicle() then return true end
		end
	end )
end