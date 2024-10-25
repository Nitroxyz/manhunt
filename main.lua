---@diagnostic disable: lowercase-global
meta = {
    name = "Manhunt",
    version = "1.61",
    author = "Gboi",
    description = "Speedrun through the game while the hunters chase you down. (Made for online specifically may work weirdly in local co-op)",
    online_safe = true
}


---Global vars (Use for more clear time measurement). 
---Make sure to not use it + decimal value for intergers
---Like: 2*MIN is okay
---1.5*MIN causes issues atm
SEC = 60;
MIN = 3600;

ROLE = {
    RUNNER = 0,
    HUNTER = 1,
    HELPER = 2,
    NONE = -1,
}

-- Variables used in the mod should show up here!

---Another implementation, where the slot corresponds to a role
---Do not manually update them, use assing_role!
local roles = {-1, -1, -1, -1}
local runner_slot = -1;
local helper_slot = -1;

---Maybe, if its convinient
local my_role = -1;
local my_slot = -1;

-- best if you sort these by doing a_crates b_insta_respawn c_teams
register_option_bool("crates", "Better Crates", "Enables the chance for random crates", false)

register_option_bool("insta_respawn", "Instant Respawn", "The hunters will instantly respawn in a random location when dying", true)

register_option_bool("teams", "2v2", 'ONLY WORKS WITH 4 PLAYERS, One of the hunters is converted into a "helper", and will help the runner. The runner can also heal or revive the helper by pressing the door and whip button', true)

--- GETTER AND CHECKER AND SETTER

-- Returns the role of the slot
function get_role(slot)
    return roles[slot]
end

-- Checks if slot is a hunter
function is_hunter(slot)
    return roles[slot] == ROLE.HUNTER
end

-- Checks if slot is a runner
function is_runner(slot)
    return roles[slot] == ROLE.RUNNER
end

-- Checks if slot is a helper
function is_helper(slot)
    return roles[slot] == ROLE.HELPER
end

-- Checks if slot is not occupied
function is_missing(slot)
    return roles[slot] == ROLE.NONE
end


-- The main way you give the players roles. Generally only done during intialzation
function assign_role(slot, role)
    roles[slot] = role
    if role == ROLE.RUNNER then
        runner_slot = slot
    elseif role == ROLE.HELPER then
        helper_slot = slot
    end
    if slot == my_slot then
        my_role = role
    end
end

-- Clears the roles of all players. Use this before assigning roles
function clear_roles()
    roles = {-1, -1, -1, -1}
    runner_slot = -1;
    helper_slot = -1;
end

--[[
-- Only use it after assigning roles initially
local function get_max_players()
    for slot, e in ipairs(roles) do
        if is_missing(slot) then
            return slot - 1
        end
    end
end
]]

-- Used to update the local slot in case you don't use the generate_roles() function. Also returns it
function update_local_slot()
    local state = get_local_state() --[[@as StateMemory]]
    if state.screen ~= SCREEN.LEVEL then 
        return nil
    end
    my_slot = online.lobby.local_player_slot
    return my_slot
end

-- Gets the Player instance of the local (pov) player
function get_local_player()
    update_local_slot()
    return get_player(my_slot, true)
end

---The slot-based version of get_all_hunters(). Also returns a Player[] table.
function get_hunters()
    local result = {}
    for slot, role in ipairs(roles) do
        if is_hunter(slot) then
            table.insert(result, get_player(slot, true))
        end
    end
    return result
end

-- Get the Player instance of the runner
function get_runner()
    return get_player(runner_slot, true)
end

function get_helper()
    if helper_slot == -1 then
        return nil
    else
        return get_player(helper_slot, true)
    end
end


--- CALCULATORS


---Finds the time since death to later respawn them at a timer. Uses Player as the parameter
---@param player Player
function get_time_since_death(player)
    local state = get_local_state() --[[@as StateMemory]]
    return state.time_total - player.inventory.time_of_death
end


--- FUNCTIONS

---Will fully reset and reassign all of the players roles
---Requires the total amount of players, since get_max_players won't work until assigning roles
---Also generates local player slot
function generate_roles(max_players)
    clear_roles()
    my_slot = online.lobby.local_player_slot
    assign_role(generate_runner_slot(max_players), ROLE.RUNNER)
    if not no_helper() then
        assign_role(generate_helper_slot(), ROLE.HELPER)
    end
    for slot = 1, max_players do
        if get_role(slot) == ROLE.NONE then
            assign_role(slot, ROLE.HUNTER)
        end
    end
end

-- Send the player outside of the map so his ghost cannot interfere. Uses the Player as a parameter
function shaddow_realm(player)
    player.x = -1
    player.y = -1
end

-- Finds and deletes the ghost of dead players
function check_and_delete_ghosts(slot)
    local player = get_player(slot, false)
    local ghost = get_playerghost(slot)
    if player and ghost then
        print("Ping")
        ghost:destroy()
    end
end

-- Chooses a random slot to become the runner. Requires a unique maxplayers, which requires to manually recount all active players
function generate_runner_slot(maxplayers)
    local pair1, pair2 = get_adventure_seed(true)
    return pair1 % maxplayers + 1
end

-- Generates a helper slot
function generate_helper_slot()
    local pair1, pair2 = get_adventure_seed(true)
    local slot = (pair1 * pair2) % 4 + 1
    if slot == generate_runner_slot(4) then slot = (slot+1)%4 end
    return slot
end



function shuffle(t)
    local prng = get_local_prng() --[[@as PRNG]]
    for i = #t, 2, -1 do
        local j = prng:random(1, i)
        t[i], t[j] = t[j], t[i]
    end
end

function contains(table, element)
    for _, value in pairs(table) do
        if value == element then
            return true
        end
    end
    return false
end

---Respawns the players in a set location
---@param player Player
function respawn_player(player, x, y, l)
    local state = get_local_state() --[[@as StateMemory]]
    if player.health > 0 then 
        return
    end
    local coffin = get_entity(spawn(ENT_TYPE.ITEM_COFFIN, x, y, l, 0, 0)) --[[@as Coffin]]
    coffin.player_respawn = true
    coffin:damage(-1, 99, 0, 0, 0, 0)
    coffin:destroy()
end

-- Tries to find a safe position by looking for a time above a floor_generic without any players nearby
function random_location()
    local valid_tiles = get_entities_by(ENT_TYPE.FLOOR_GENERIC, MASK.FLOOR, LAYER.BOTH)
    shuffle(valid_tiles)
    for i, uid in ipairs(valid_tiles) do 
        local x, y, l = get_position(uid)
        y = y+1
        local nearby_players = get_entities_at(0, MASK.PLAYER, x, y, l, 5)
        if not nearby_players[1] and position_is_valid(x, y, l, POS_TYPE.SAFE) then 
            return x, y, l
        end
    end
    return nil
end

-- Gets the total amount of alive players 
function get_max_players()
    local players = 0
    for i=1, 4 do
        if get_player(i, true) then players = players + 1 end
    end
    return players
end

-- Checks if runner is dead
function is_runner_dead()
    local runner = get_runner()
    if not runner then return true end
    return runner.health == 0
end

-- Returns true if there shouldn't be a helper
function no_helper()
    return get_max_players() ~= 4 or not options.teams
end

-- totally did not use ChatGPT.
function find_valid_room(valid_table, l, max_height, min_height, max_width, min_width)
    local state = get_local_state() --[[@as StateMemory]]
    local prng = get_local_prng() --[[@as PRNG]]
    
    -- Generate a shuffled list of x coordinates within the width constraints
    local x_list = {}
    for x = min_width, math.min(state.width - 1, max_width - 1) do
        table.insert(x_list, x)
    end
    for i = #x_list, 2, -1 do
        local j = prng:random(1, i)
        x_list[i], x_list[j] = x_list[j], x_list[i] -- Shuffle x_list
    end
    
    -- Generate a shuffled list of y coordinates
    local y_list = {}
    for y = min_height, math.max(state.height - 1, max_height - 1) do
        table.insert(y_list, y)
    end
    for i = #y_list, 2, -1 do
        local j = prng:random(1, i)
        y_list[i], y_list[j] = y_list[j], y_list[i] -- Shuffle y_list
    end

    -- Iterate through shuffled coordinates
    for _, x in ipairs(x_list) do
        for _, y in ipairs(y_list) do
            local rt = get_room_template(x, y, l)
            if contains(valid_table, rt) then
                return x, y, rt
            end
        end
    end
    
    return nil, nil
end

-- Finds the total number of dead players
function get_dead_players()
    local state = get_local_state() --[[@as StateMemory]]
    if state.screen ~= SCREEN.LEVEL then return 0 end -- No checking outside of levels
    local dead = 0
    for i, inventory in ipairs(state.items.player_inventory) do
        if inventory.time_of_death > 0 then dead = dead + 1 end
    end
    return dead
end

-- Returns true if you are a runner
function i_am_runner()
    local state = get_local_state() --[[@as StateMemory]]
    if state.screen == SCREEN.LEVEL then
        local runner = get_runner()
        local me = get_local_player()
        return me and runner and me.uid == runner.uid
    end
    return false
end

-- Returns true if you are a helper
function i_am_helper()
    local state = get_local_state() --[[@as StateMemory]]
    if state.screen == SCREEN.LEVEL then 
        local helper = get_helper()
        local me = get_local_player()
        return me and helper and me.uid == helper.uid
    end
    return false
end

-- Returns a table of all hunters (Causes an error atm)
---@return Player[]
function get_all_hunters()
    local hunters = {}
    local runner = get_runner()
    local helper = get_helper()
    for i=1, get_max_players() do 
        local player = get_player(i, true)
            if helper == nil then 
                if runner ~= nil and player.uid ~= nil and player.uid ~= runner.uid then 
                    table.insert(hunters, player)
                end
            else
                if runner ~= nil and player.uid ~= nil and player.uid ~= runner.uid and player.uid ~= helper.uid then 
                    table.insert(hunters, player)
                end
            end
    end
    return hunters
end

function end_game()
    if is_runner_dead() then
        local runner = get_runner()
        for i=1, get_max_players() do 
            local player = get_player(i, true)
            if player.uid ~= runner.uid then 
                kill_entity(player.uid, true)
            end
        end
    end
end


-- hunter callback
---@param hunter Player
function hunters_function(hunter)
    local state = get_local_state() --[[@as StateMemory]]
    if state.screen == SCREEN.LEVEL then
        -- When entering a level
        if state.time_level <= 1 then
            -- Tries to unmount everyone
            local mounts = get_entities_by(0, MASK.MOUNT, LAYER.BOTH)
            for i, uid in ipairs(mounts) do 
                local mount = get_entity(uid) --[[@as Mount]]
                local rider = get_entity(mount.rider_uid)
                if rider ~= nil and rider.uid == hunter.uid then
                    mount:remove_rider()
                end
            end

            -- Sets the invincibility_frames_timer for hunters
            if state.theme == THEME.DWELLING then
                hunter.invincibility_frames_timer = 3*SEC
            elseif state.theme ~= THEME.DWELLING then
                hunter.invincibility_frames_timer = 2*SEC
            end
        end

        -- When the hunter is alive:
        if hunter.health ~= 0 then
            -- Try to delete their ghost
            check_and_delete_ghosts(hunter.inventory.player_slot)
            
            -- when true, he is still waiting
            local waiting = false
            -- how long he has to wait
            local waittime = 0;
            if state.theme == THEME.DWELLING then
                waittime = 2*SEC
            else
                waittime = 1*SEC
            end
            
            -- checks if hunters has to still wait
            if state.time_level <= waittime then
                waiting = true

                --[[ Set hunters to:
                -- Pass through everything?
                -- Become invisible
                -- Not become pickupable
                -- Have their input disabled
                ]]
                hunter.flags = set_flag(hunter.flags, ENT_FLAG.PASSES_THROUGH_EVERYTHING)
                hunter.flags = set_flag(hunter.flags, ENT_FLAG.INVISIBLE)
                hunter.flags = clr_flag(hunter.flags, ENT_FLAG.PICKUPABLE)
                hunter.more_flags = set_flag(hunter.more_flags, ENT_MORE_FLAG.DISABLE_INPUT)

                -- Put their position on top of the door entrance
                local ex, ey = get_position(get_entities_by(ENT_TYPE.FLOOR_DOOR_ENTRANCE, MASK.FLOOR, LAYER.BOTH)[1])
                hunter.x = ex
                hunter.y = ey
                
                -- Tries to follow the runner with the camera while waiting
                local runner = get_runner()
                if runner then
                    if not i_am_runner() and not i_am_helper() then
                        state.camera.focused_entity_uid = runner.uid
                    else
                        state.camera.focused_entity_uid = get_local_player().uid;
                    end
                end
            end

            -- When the waittime ends
            if state.time_level == waittime then
                generate_world_particles(PARTICLEEMITTER.MERCHANT_APPEAR_POOF, hunter.uid)
                play_sound(VANILLA_SOUND.ENEMIES_VLAD_TRIGGER, hunter.uid)
            end

            -- When not waiting anymore
            -- Are you spamming this flag change?
            if not waiting and state.time_level <= 130 then
                hunter.flags = clr_flag(hunter.flags, ENT_FLAG.PASSES_THROUGH_EVERYTHING)
                hunter.more_flags = clr_flag(hunter.more_flags, ENT_MORE_FLAG.DISABLE_INPUT)
                hunter.flags = clr_flag(hunter.flags, ENT_FLAG.INVISIBLE)
                hunter.flags = set_flag(hunter.flags, ENT_FLAG.PICKUPABLE)
            elseif get_local_player() then
                state.camera.focused_entity_uid = get_local_player().uid;
            end
        -- when the hunter is dead
        else
            if options.insta_respawn and (get_time_since_death(hunter) > 15*SEC) and not is_runner_dead() then
                local x, y, l = random_location()
                respawn_player(hunter, x, y, l)
            end

            -- SEND HIM TO THE SHADDOW REALM
            shaddow_realm(hunter)
        end
    end
end

---Runs all hunter related stuff each frame.
function hunter_callback(slot)
    local state = get_local_state() --[[@as StateMemory]]
    -- Safeguard to not run outside of a level
    if state.screen ~= SCREEN.LEVEL then return end

    -- This alone can prevent some errors
    local hunter = get_player(slot, true)

    -- Run when entering a level (Should probably be moved to a different section)
    if state.time_level <= 1 then
        -- Tries to unmount everyone
        local mounts = get_entities_by(0, MASK.MOUNT, LAYER.BOTH)
        for i, uid in ipairs(mounts) do 
            local mount = get_entity(uid) --[[@as Mount]]
            local rider = get_entity(mount.rider_uid)
            if rider ~= nil and rider.uid == hunter.uid then
                mount:remove_rider()
            end
        end

        -- Sets the invincibility_frames_timer for hunters
        if state.theme == THEME.DWELLING then
            hunter.invincibility_frames_timer = 3*SEC
        elseif state.theme ~= THEME.DWELLING then
            hunter.invincibility_frames_timer = 2*SEC
        end
    end

    -- When the hunter is alive/dead:
    if hunter.health ~= 0 then
        -- Try to delete their ghost
        check_and_delete_ghosts(slot)
        
        -- when true, he is still waiting
        local waiting = false
        -- how long he has to wait
        local waittime = 0;
        if state.theme == THEME.DWELLING then
            waittime = 2*SEC
        else
            waittime = 1*SEC
        end
        
        -- checks if hunters has to still wait
        if state.time_level <= waittime then
            waiting = true

            --[[ Set hunters to:
            -- Pass through everything?
            -- Become invisible
            -- Not become pickupable
            -- Have their input disabled
            ]]
            hunter.flags = set_flag(hunter.flags, ENT_FLAG.PASSES_THROUGH_EVERYTHING)
            hunter.flags = set_flag(hunter.flags, ENT_FLAG.INVISIBLE)
            hunter.flags = clr_flag(hunter.flags, ENT_FLAG.PICKUPABLE)
            hunter.more_flags = set_flag(hunter.more_flags, ENT_MORE_FLAG.DISABLE_INPUT)

            -- Put their position on top of the door entrance
            local ex, ey = get_position(get_entities_by(ENT_TYPE.FLOOR_DOOR_ENTRANCE, MASK.FLOOR, LAYER.BOTH)[1])
            hunter.x = ex
            hunter.y = ey
            
            -- Tries to follow the runner with the camera while waiting
            local runner = get_player(runner_slot, true)
            if runner then
                if is_hunter(my_slot) then
                    state.camera.focused_entity_uid = runner.uid
                else
                    state.camera.focused_entity_uid = get_local_player().uid;
                end
            end
        end

        -- When the waittime ends
        if state.time_level == waittime then
            generate_world_particles(PARTICLEEMITTER.MERCHANT_APPEAR_POOF, hunter.uid)
            play_sound(VANILLA_SOUND.ENEMIES_VLAD_TRIGGER, hunter.uid)
        end

        -- When not waiting anymore
        -- Are you spamming this flag change?
        if not waiting and state.time_level <= 130 then
            hunter.flags = clr_flag(hunter.flags, ENT_FLAG.PASSES_THROUGH_EVERYTHING)
            hunter.more_flags = clr_flag(hunter.more_flags, ENT_MORE_FLAG.DISABLE_INPUT)
            hunter.flags = clr_flag(hunter.flags, ENT_FLAG.INVISIBLE)
            hunter.flags = set_flag(hunter.flags, ENT_FLAG.PICKUPABLE)
        elseif get_local_player() then
            state.camera.focused_entity_uid = get_local_player().uid;
        end
    -- when the hunter is dead
    else
        if options.insta_respawn and (get_time_since_death(hunter) > 15*SEC) and not is_runner_dead() then
            local x, y, l = random_location()
            respawn_player(hunter, x, y, l)
        end

        -- SEND HIM TO THE SHADDOW REALM
        shaddow_realm(hunter)
    end
end

-- runner callback
function runner_function(slot)
    local state = get_local_state() --[[@as StateMemory]]
    local runner = get_player(slot, true)
    if state.screen == SCREEN.LEVEL then
        -- if runner is... alive?
        if not runner then return end

        -- if runner is dead. Shouldnt you use the function to check that?
        if runner.health == 0 then
            end_game()
        end

        -- helper revive shenanigans
        local holding_buttons = runner:is_button_held(BUTTON.DOOR) and runner:is_button_pressed(BUTTON.WHIP)
        if not no_helper() and holding_buttons and runner.health >= 4 and runner.layer == LAYER.FRONT then 
            local helper = get_helper()
            local x, y, l = get_position(runner.uid)
            if helper then 
                if helper.health == 0 then 
                    helper.inventory.health = math.floor(runner.health / 2)
                    helper.inventory.time_of_death = 0
                    spawn_player(helper_slot, x, y, l)
                    runner.health = math.floor(runner.health / 2)
                else
                    helper.health = helper.health + math.floor(runner.health / 2)
                    runner.health = math.floor(runner.health / 2)
                end
            end
        end
    end
end

-- hunter callback
function helper_function(slot)
    local state = get_local_state() --[[@as StateMemory]]
    local helper = get_helper()
    if not helper then return end
    if state.screen == SCREEN.LEVEL then
        -- make hunter smol
        local base_size = 1.250
        helper.width = base_size / 2
        helper.height = base_size / 2
        helper.hitboxx = 0.168
        helper.hitboxy = 0.210
        helper.offsety = -0.1
        -- shaddow realmed I assume?
        if helper.health == 0 then
            helper.x = 0
            helper.y = 0
            -- shaddow_realm(helper)
        end
    end
end

---Select the runner and helper.
---ON.RESET doesnt need to be the one to do it. Idk which tho
set_callback(function ()
    
end, ON.RESET)

set_callback(function()
    set_adventure_seed(0, 0)
end, ON.ONLINE_LOADING)

-- Primary gameloop
set_callback(function()
    local state = get_local_state() --[[@as StateMemory]]
    if state.screen == SCREEN.LEVEL then
        --local max_players = get_max_players()
        local runner = get_runner()
        local helper = get_helper()
        local coffin_count = 0
        local coffins = get_entities_by(ENT_TYPE.ITEM_COFFIN, MASK.ITEM, LAYER.BOTH)

        
        for i, uid in ipairs(coffins) do
            -- blow up coffins with mind (and whip)
            local whips = get_entities_by({ENT_TYPE.ITEM_WHIP, ENT_TYPE.ITEM_WHIP_FLAME}, MASK.ITEM, LAYER.BOTH)
            local coffin = get_entity(uid) --[[@as Coffin]]
            for i, uid in ipairs(whips) do 
                local aabb = get_hitbox(uid)
                local x, y, l = get_position(uid)
                if coffin:overlaps_with(aabb) then 
                    spawn(ENT_TYPE.FX_POWEREDEXPLOSION, x, y, l, 0, 0)
                    coffin:destroy()
                end
            end

            coffin_count = coffin_count + 1

            -- prevent bombs from hitting a coffin (kinda)
            local x, y, l = get_position(uid)
            local nearby_bombs = get_entities_at({ENT_TYPE.ITEM_BOMB, ENT_TYPE.ITEM_PASTEBOMB}, MASK.ITEM, x, y, l, 3)
            --- totally did not use chatGPT.
            for _, b_uid in ipairs(nearby_bombs) do 
                local bomb = get_entity(b_uid) --[[@as Bomb]]
                if bomb.type.id == ENT_TYPE.ITEM_PASTEBOMB then 
                    bomb.flags = set_flag(bomb.flags, ENT_FLAG.PASSES_THROUGH_EVERYTHING)
                end
                local bomb_x, bomb_y, _ = get_position(b_uid)
                
                -- Calculate direction from coffin to bomb
                local dir_x = bomb_x - x
                local dir_y = bomb_y - y
                local magnitude = math.sqrt(dir_x * dir_x + dir_y * dir_y)
                
                -- Normalize direction and set velocity
                bomb.velocityx = (dir_x / magnitude) * 0.25 -- Adjust multiplier for speed
                bomb.velocityy = (dir_y / magnitude) * 0.25 -- Adjust multiplier for speed
            end
        end
        
        -- do the hunter callback
        for _, hunter in ipairs(get_all_hunters()) do
            hunters_function(hunter)
        end

        -- do the runner callback (Should probably have a check)
        --runner_function(runner)
        
        -- do the helper callback
        --[[
        if helper then
            helper_function(helper)
        end
        ]]

        for slot, role in ipairs(roles) do
            if is_hunter(slot) then
                hunter_callback(slot)
            elseif is_runner(slot) then
                runner_function(slot)
            elseif is_helper(slot) then
                helper_function(slot)
            end
        end

        -- Tries breaking all coffins after 10 seconds
        if state.time_level == 10*SEC then 
            for i, uid in ipairs(coffins) do 
                local coffin = get_entity(uid) --[[@as Coffin]]
                coffin:damage(-1, 99, 0, 0, 0, 0)
                coffin:destroy()
            end
        end
        
        -- The total amount of time until explosions can interact with players
        local explosion_mask_timer = 4*SEC;
        -- Why dont they align on one number (3 or 4)? The previously seen version was using 4
        -- Good showcase why you should use elseif, now
        -- Prevents players from being hit by explosions
        if state.time_level >= explosion_mask_timer then
            set_explosion_mask(MASK.PLAYER | MASK.MOUNT | MASK.MONSTER | MASK.ITEM | MASK.ACTIVEFLOOR | MASK.FLOOR)
        elseif state.time_level < explosion_mask_timer then
            set_explosion_mask(MASK.MOUNT | MASK.MONSTER | MASK.ITEM | MASK.ACTIVEFLOOR | MASK.FLOOR)
        end

        -- Unlock door after time has passed
        local exit_unlock_timer = 0;
        if state.level_count ~= 0 or coffin_count ~= 0 then
            exit_unlock_timer = 10*SEC
        else
            exit_unlock_timer = 5*SEC
        end

        if state.time_level == exit_unlock_timer then
            local exit_door = get_entities_by(ENT_TYPE.FLOOR_DOOR_EXIT, MASK.FLOOR, LAYER.BOTH)
            for i, uid in ipairs(exit_door) do
                local x, y = get_position(uid)
                unlock_door_at(x, y)
            end
        end
    end
end, ON.POST_UPDATE)

-- Level gen callback
set_callback(function()
    local state = get_local_state() --[[@as StateMemory]]
    local prng = get_local_prng() --[[@as PRNG]]

    --idk what this really does
    if state.level == 1 and state.world == 1 then
        local pair1, pair2 = get_adventure_seed(true)
        set_adventure_seed(pair1 + 1, pair2 + 1)
    end
    if state.screen == SCREEN.LEVEL then
        --lock the doors
        local exit_door = get_entities_by(ENT_TYPE.FLOOR_DOOR_EXIT, MASK.FLOOR, LAYER.BOTH)
        local tiles = get_entities_by(ENT_TYPE.FLOOR_GENERIC, MASK.FLOOR, LAYER.BOTH)
        for i, uid in ipairs(exit_door) do 
            local x, y = get_position(uid)
            lock_door_at(x, y)
        end

        -- reset time of death?
        local hunters = get_all_hunters()
        for _, hunter in ipairs(hunters) do
            if hunter.health > 0 then
                hunter.inventory.time_of_death = 0
            end
        end

        -- generate crates
        for i, uid in ipairs(tiles) do 
            local x, y, l = get_position(uid)
            if options.crates and (position_is_valid(x, y+1, l, POS_TYPE.ALCOVE) or position_is_valid(x, y+1, l, POS_TYPE.HOLE) or position_is_valid(x, y+1, l, POS_TYPE.PIT)) then
                if prng:random_chance(8, PRNG_CLASS.ENTITY_VARIATION) then 
                    local present = get_entity(spawn(ENT_TYPE.ITEM_PRESENT, x, y+1, l, 0, 0)) --[[@as Container]]
            
                    --[[ Balancing thoughts 
                    Approximate rarities:
                    Rare: 1-2
                    Medium: 3-5
                    Common: 6-8

                    Eggplant crown is almost an immediate win, should be rare
                    Bomb box should be replace by the player bag from arena (12 bombs + 12 ropes) and be common
                    Jetpack is should be a high medium/common
                    True crown should be a a low medium/rare
                    Kapala should be a rare (Reminder that pickup items can be easily obtained by runners by killing hunters) 
                    Teleport can be anything
                    Telepack can be anything, but preferably be rarer
                    Royal Jelly should be common
                    Vlads Cape should be low medium/rare (Extremly easily obtainable by runners)
                    Elixir should be a high medium/common (This is because its already player locked, meaning it's ) 
                    Light arrow should be common (I mean it's a one-time use one-shot)

                    Potential new additions:
                    Plasma cannon (Rare)
                    Power pack (Common)
                    Mattock (Medium/High medium)
                    Freeze ray (Common)
                    Snap trap (Common)
                    Poison tipped crossbow (Common)
                    Magma pot (High medium/Common)
                    Curse pot (Medium)
                    24 Ropes/Bombs (Low Medium/Rare)
                    ]]

                    -- new table
                    local possible_items = {
                        { item = ENT_TYPE.ITEM_PICKUP_EGGPLANTCROWN, weight = 1 },
                        { item = ENT_TYPE.ITEM_PICKUP_12BAG, weight = 6 },
                        { item = ENT_TYPE.ITEM_PICKUP_24BAG, weight = 3},
                        { item = ENT_TYPE.ITEM_JETPACK, weight = 6 },
                        { item = ENT_TYPE.ITEM_PICKUP_TRUECROWN, weight = 3 },
                        { item = ENT_TYPE.ITEM_PICKUP_KAPALA, weight = 2 },
                        { item = ENT_TYPE.ITEM_TELEPORTER, weight = 4 },
                        { item = ENT_TYPE.ITEM_TELEPORTER_BACKPACK, weight = 3 },
                        { item = ENT_TYPE.ITEM_PICKUP_ROYALJELLY, weight = 8 },
                        { item = ENT_TYPE.ITEM_VLADS_CAPE, weight = 2 },
                        { item = ENT_TYPE.ITEM_PICKUP_ELIXIR, weight = 5 },
                        { item = ENT_TYPE.ITEM_LIGHT_ARROW, weight = 7 },
                        { item = ENT_TYPE.ITEM_SNAP_TRAP, weight = 5},
                        { item = ENT_TYPE.ITEM_FREEZERAY, weight = 7},
                    }

                    --[[ Previous table
                    local possible_items = {
                        { item = ENT_TYPE.ITEM_PICKUP_EGGPLANTCROWN, weight = 3 },
                        { item = ENT_TYPE.ITEM_PICKUP_BOMBBOX, weight = 2 },
                        { item = ENT_TYPE.ITEM_JETPACK, weight = 2 },
                        { item = ENT_TYPE.ITEM_PICKUP_TRUECROWN, weight = 2 },
                        { item = ENT_TYPE.ITEM_PICKUP_KAPALA, weight = 2 },
                        { item = ENT_TYPE.ITEM_TELEPORTER, weight = 2 },
                        { item = ENT_TYPE.ITEM_TELEPORTER_BACKPACK, weight = 2 },
                        { item = ENT_TYPE.ITEM_PICKUP_ROYALJELLY, weight = 3 },
                        { item = ENT_TYPE.ITEM_VLADS_CAPE, weight = 1 },
                        { item = ENT_TYPE.ITEM_PICKUP_ELIXIR, weight = 4 },
                        { item = ENT_TYPE.ITEM_LIGHT_ARROW, weight = 4 },
                    }
                    ]]

                    
                
                    -- Create a weighted table for random selection
                    local weighted_items = {}
                    for _, entry in ipairs(possible_items) do
                        for i = 1, entry.weight do
                            table.insert(weighted_items, entry.item)
                        end
                    end
                
                    -- Select an item based on the weighted probability
                    present.inside = weighted_items[prng:random_index(#weighted_items, PRNG_CLASS.ENTITY_VARIATION)]
                    present.color = Color:aqua()
                else
                    local crate = get_entity(spawn(ENT_TYPE.ITEM_CRATE, x, y+1, l, 0, 0)) --[[@as Container]]
            
                    --[[ Balancing thoughts
                    Rarities
                    Very rare: 1
                    Rare: 2-4
                    Medium: 5-8
                    Common: 9-15

                    Bombbox should be low medium to common
                    Jetpack should be a high rare
                    Teleporter should be a very rare
                    Telepack should be a very rare
                    Royal jelly should be a rare to medium
                    Paste should be a low medium (It has both a really polarizing effect with a lot of bombs, but can also be a curse)
                    Hoverpack should be a medium to low medium
                    Pitchers mit should be a low medium to high medium
                    Spikeshoes should be a rare to medium (Rare case where an item kinda does nothing most of the time)
                    Springshoes should be a medium to low common (The idea is that the runner most likely will obtain one anyways, so make it more common to allow runners to match him)
                    Climbing gloves should be rare to high medium (If there are measures against runners camping, then it can be more common, otherwise make it just show up in most games)
                    Landmine should be low to high common (Great item for both sides)
                    Bomb bag very common
                    Ropes very common
                    Cooked turkey very common


                    Potential additional items
                    Torch (Low Common)
                    Lamp (Low Common) (Fire hard counters the metal back items, so they can be more common)
                    Shotgun (Rare)
                    Freeze ray (Rare)
                    Machete (Medium/Low Common)

                    Potential removed items 
                    Wooden shield is ass
                    True crown should be a present item
                    Kapala should be a present item
                    Vlads cape should be a present item
                    Elixir could be a present item
                    Light arrow could be a present item
                    ]]

                    local possible_items = {
                        { item = ENT_TYPE.ITEM_PICKUP_BOMBBOX, weight = 1 },
                        { item = ENT_TYPE.ITEM_JETPACK, weight = 1 },
                        { item = ENT_TYPE.ITEM_PICKUP_TRUECROWN, weight = 1 },
                        { item = ENT_TYPE.ITEM_PICKUP_KAPALA, weight = 1 },
                        { item = ENT_TYPE.ITEM_TELEPORTER, weight = 1 },
                        { item = ENT_TYPE.ITEM_TELEPORTER_BACKPACK, weight = 1 },
                        { item = ENT_TYPE.ITEM_WOODEN_SHIELD, weight = 2 },
                        { item = ENT_TYPE.ITEM_PICKUP_ROYALJELLY, weight = 2 },
                        { item = ENT_TYPE.ITEM_VLADS_CAPE, weight = 3 },
                        { item = ENT_TYPE.ITEM_PICKUP_ELIXIR, weight = 3 },
                        { item = ENT_TYPE.ITEM_PICKUP_PASTE, weight = 3 },
                        { item = ENT_TYPE.ITEM_LIGHT_ARROW, weight = 3 },
                        { item = ENT_TYPE.ITEM_HOVERPACK, weight = 4 },
                        { item = ENT_TYPE.ITEM_PICKUP_PITCHERSMITT, weight = 4 },
                        { item = ENT_TYPE.ITEM_PICKUP_SPIKESHOES, weight = 4 },
                        { item = ENT_TYPE.ITEM_PICKUP_SPRINGSHOES, weight = 4 },
                        { item = ENT_TYPE.ITEM_PICKUP_CLIMBINGGLOVES, weight = 4 },
                        { item = ENT_TYPE.ITEM_LANDMINE, weight = 4 },
                        { item = ENT_TYPE.ITEM_PICKUP_BOMBBAG, weight = 4 },
                        { item = ENT_TYPE.ITEM_PICKUP_ROPEPILE, weight = 4 },
                        { item = ENT_TYPE.ITEM_PICKUP_COOKEDTURKEY, weight = 4 },
                    }
                
                    -- Create a weighted table for random selection
                    local weighted_items = {}
                    for _, entry in ipairs(possible_items) do
                        for i = 1, entry.weight do
                            table.insert(weighted_items, entry.item)
                        end
                    end
                
                    -- Select an item based on the weighted probability
                    crate.inside = weighted_items[prng:random_index(#weighted_items, PRNG_CLASS.ENTITY_VARIATION)]
                    crate.color = Color:aqua()
                end
            end
            
        end
    end
end, ON.POST_LEVEL_GENERATION)

---Draw the runner/helper aura
---@param ctx GuiDrawContext
set_callback(function(ctx)
    local me = get_local_player()
    if me ~= nil then
        local runner = get_runner()
        if runner and not runner_slot ~= my_slot then 
            local x, y, l = get_position(runner.uid)
            local cx, cy = screen_position(x, y)
            ctx:draw_circle_filled(cx, cy-0.03, 0.04, rgba(255, 0, 0, 100))
        end
        local helper = get_helper()
        if helper and not helper_slot ~= my_slot then 
            local x, y, l = get_position(helper.uid)
            local cx, cy = screen_position(x, y)
            ctx:draw_circle_filled(cx, cy-0.03, 0.04, rgba(255, 255, 0, 100))
        end
    end
end, ON.GUIFRAME)

---dumb cosmic code runs this twice
---generates coffins in cosmic ocean
---@param ctx PostRoomGenerationContext
set_callback(function(ctx)
    local state = get_local_state() --[[@as StateMemory]]
    if state.screen == SCREEN.LEVEL and state.theme == THEME.COSMIC_OCEAN then 
        local already_existing_coffins = 0
        for i=0, 4 do 
            local roomx, roomy = find_valid_room({ROOM_TEMPLATE.COFFIN_PLAYER, ROOM_TEMPLATE.COFFIN_PLAYER_VERTICAL}, LAYER.FRONT, state.height, 0, state.width, 0)
            if roomx ~= nil then 
                already_existing_coffins = already_existing_coffins + 1
            end
        end
        local dead_amount = get_dead_players() - already_existing_coffins
        if dead_amount == 0 then return end
        for i=0, dead_amount do 
            local roomx, roomy = find_valid_room({ROOM_TEMPLATE.SIDE}, LAYER.FRONT, state.height, 1, state.width, 1)
            ctx:set_room_template(roomx, roomy, LAYER.FRONT, ROOM_TEMPLATE.COFFIN_PLAYER)
        end
    end
end, ON.POST_ROOM_GENERATION)