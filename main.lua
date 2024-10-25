meta = {
    name = "Manhunt",
    version = "1.60",
    author = "Gboi",
    description = "Speedrun through the game while the hunters chase you down. (Made for online specifically may work weirdly in local co-op)",
    online_safe = true
}

register_option_bool("crates", "Better Crates", "Enables the chance for random crates", false)

register_option_bool("insta_respawn", "Instant Respawn", "The hunters will instantly respawn in a random location when dying", true)

register_option_bool("teams", "2v2", 'ONLY WORKS WITH 4 PLAYERS, One of the hunters is converted into a "helper", and will help the runner. The runner can also heal or revive the helper by pressing the door and whip button', true)


local function shuffle(t)
    local prng = get_local_prng() --[[@as PRNG]]
    for i = #t, 2, -1 do
        local j = prng:random(1, i)
        t[i], t[j] = t[j], t[i]
    end
end

local function contains(table, element)
    for _, value in pairs(table) do
        if value == element then
            return true
        end
    end
    return false
end

---comment
---@param player Player
local function respawn_player(player, x, y, l)
    local state = get_local_state() --[[@as StateMemory]]
    if player.health > 0 then 
        return
    end
    local coffin = get_entity(spawn(ENT_TYPE.ITEM_COFFIN, x, y, l, 0, 0)) --[[@as Coffin]]
    coffin.player_respawn = true
    coffin:damage(-1, 99, 0, 0, 0, 0)
    coffin:destroy()
end

---@param player Player
local function get_time_since_death(player)
    local state = get_local_state() --[[@as StateMemory]]
    return state.time_total - player.inventory.time_of_death
end

local function check_and_delete_ghosts(slot)
    local player = get_player(slot, false)
    local ghost = get_playerghost(slot)
    if player and ghost then 
        ghost:destroy()
    end
end

local function random_location()
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

local function get_local_player()
    local state = get_local_state() --[[@as StateMemory]]
    if state.screen ~= SCREEN.LEVEL then 
        return nil
    end
    local slot = online.lobby.local_player_slot
    return get_player(slot, true)
end

local function get_runner_slot(mplayers)
    local pair1, pair2 = get_adventure_seed(true)
    return pair1 % mplayers + 1
end

local function get_runner(mplayers)
    local slot = get_runner_slot(mplayers)
    return get_player(slot, true)
end

local function get_max_players()
    local players = 0
    for i=1, 4 do
        if get_player(i, true) then players = players + 1 end
    end
    return players
end

local function is_runner_dead()
    local runner = get_runner(get_max_players())
    if not runner then return true end
    return runner.health == 0
end

local function get_helper_slot()
    local pair1, pair2 = get_adventure_seed(true)
    local slot = (pair1 * pair2) % 4 + 1
    if slot == get_runner_slot(4) then slot = slot % 4 + 1 end
    return slot
end

local function no_helper()
    return get_max_players() ~= 4 or not options.teams
end

local function get_helper()
    if no_helper() then 
        return nil 
    end
    local slot = get_helper_slot()
    return get_player(slot, true)
end

-- totally did not use ChatGPT.
local function find_valid_room(valid_table, l, max_height, min_height, max_width, min_width)
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

local function get_dead_players()
    local state = get_local_state() --[[@as StateMemory]]
    if state.screen ~= SCREEN.LEVEL then return 0 end
    local dead = 0
    for i, inventory in ipairs(state.items.player_inventory) do
        if inventory.time_of_death > 0 then dead = dead + 1 end
    end
    return dead
end

local function i_am_runner()
    local state = get_local_state() --[[@as StateMemory]]
    if state.screen == SCREEN.LEVEL then
        local runner = get_runner(get_max_players())
        local me = get_local_player()
        return me and runner and me.uid == runner.uid
    end
    return false
end

local function i_am_helper()
    local state = get_local_state() --[[@as StateMemory]]
    if state.screen == SCREEN.LEVEL then 
        local helper = get_helper()
        local me = get_local_player()
        return me and helper and me.uid == helper.uid
    end
    return false
end

---@return Player[]
local function get_all_hunters()
    local hunters = {}
    local runner = get_runner(get_max_players())
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

---@param hunter Player
local function hunters_function(hunter)
    local state = get_local_state() --[[@as StateMemory]]
    if state.screen == SCREEN.LEVEL then 
        if state.time_level <= 1 then 
            local mounts = get_entities_by(0, MASK.MOUNT, LAYER.BOTH)
            for i, uid in ipairs(mounts) do 
                local mount = get_entity(uid) --[[@as Mount]]
                local rider = get_entity(mount.rider_uid)
                if rider ~= nil and rider.uid == hunter.uid then 
                    mount:remove_rider()
                end
            end
            if state.theme == THEME.DWELLING then 
                hunter.invincibility_frames_timer = 180
            end
            if state.theme ~= THEME.DWELLING then 
                hunter.invincibility_frames_timer = 120
            end
        end
        if hunter.health ~= 0 then 
            check_and_delete_ghosts(hunter.inventory.player_slot)
            local waiting = false

            local waittime = 0;
            if state.theme == THEME.DWELLING then
                waittime = 120
            else
                waittime = 60
            end
        
            if state.time_level <= waittime then 
                waiting = true
                hunter.flags = set_flag(hunter.flags, ENT_FLAG.PASSES_THROUGH_EVERYTHING)
                hunter.flags = set_flag(hunter.flags, ENT_FLAG.INVISIBLE)
                hunter.flags = clr_flag(hunter.flags, ENT_FLAG.PICKUPABLE)
                hunter.more_flags = set_flag(hunter.more_flags, ENT_MORE_FLAG.DISABLE_INPUT)
                local ex, ey = get_position(get_entities_by(ENT_TYPE.FLOOR_DOOR_ENTRANCE, MASK.FLOOR, LAYER.BOTH)[1])
                local runner = get_runner(get_max_players())
                if runner then 
                    -- local rx, ry = get_position(runner.uid)
                    if not i_am_runner() and not i_am_helper() then 
                        -- set_camera_position(rx, ry)
                        state.camera.focused_entity_uid = runner.uid
                    else
                        state.camera.focused_entity_uid = get_local_player().uid;
                    end
                end
                hunter.x = ex
                hunter.y = ey
            end
            if state.time_level == waittime then
                generate_world_particles(PARTICLEEMITTER.MERCHANT_APPEAR_POOF, hunter.uid)
                play_sound(VANILLA_SOUND.ENEMIES_VLAD_TRIGGER, hunter.uid)
            end

            if not waiting and state.time_level <= 130 then 
                hunter.flags = clr_flag(hunter.flags, ENT_FLAG.PASSES_THROUGH_EVERYTHING)
                hunter.more_flags = clr_flag(hunter.more_flags, ENT_MORE_FLAG.DISABLE_INPUT)
                hunter.flags = clr_flag(hunter.flags, ENT_FLAG.INVISIBLE)
                hunter.flags = set_flag(hunter.flags, ENT_FLAG.PICKUPABLE)
            end
        end
        if hunter.health == 0 and (options.insta_respawn and (get_time_since_death(hunter) > 60 * 15) and not is_runner_dead()) then 
            local x, y, l = random_location()
            respawn_player(hunter, x, y, l)
        end
        if hunter.health == 0 then
            hunter.x = -1
            hunter.y = -1
        end
    end
end

local function end_game()
    local runner = get_runner(get_max_players())
    for i=1, get_max_players() do 
        local player = get_player(i, true)
        if player.uid ~= runner.uid and runner.health == 0 then 
            kill_entity(player.uid, true)
        end
    end
end

---@param runner Player
local function runner_function(runner)
    local state = get_local_state() --[[@as StateMemory]]
    if state.screen == SCREEN.LEVEL then 
        if runner and runner.health == 0 then 
            end_game()
        end
        if runner then 
            local holding_buttons = runner:is_button_held(BUTTON.DOOR) and runner:is_button_pressed(BUTTON.WHIP)
            if not no_helper() and holding_buttons and runner.health >= 4 and runner.layer == LAYER.FRONT then 
                local helper = get_helper()
                local x, y, l = get_position(runner.uid)
                if helper then 
                    if helper.health == 0 then 
                        helper.inventory.health = math.floor(runner.health / 2)
                        helper.inventory.time_of_death = 0
                        spawn_player(get_helper_slot(), x, y, l)
                        runner.health = math.floor(runner.health / 2)
                    else
                        helper.health = helper.health + math.floor(runner.health / 2)
                        runner.health = math.floor(runner.health / 2)
                    end
                end
            end
        end
    end
end

---@param helper Player
local function helper_function(helper)
    local state = get_local_state() --[[@as StateMemory]]
    if state.screen == SCREEN.LEVEL then 
        local base_size = 1.250
        helper.width = base_size / 2
        helper.height = base_size / 2
        helper.hitboxx = 0.168
        helper.hitboxy = 0.210
        helper.offsety = -0.1
        if helper.health == 0 then 
            helper.x = 0
            helper.y = 0
        end
    end
end

set_callback(function()
    set_adventure_seed(0, 0)
end, ON.ONLINE_LOADING)

set_callback(function()
    local state = get_local_state() --[[@as StateMemory]]
    if state.screen == SCREEN.LEVEL then 
        local max_players = get_max_players()
        local runner = get_runner(max_players)
        local helper = get_helper()
        local coffin_count = 0
        local coffins = get_entities_by(ENT_TYPE.ITEM_COFFIN, MASK.ITEM, LAYER.BOTH)
        for i, uid in ipairs(coffins) do
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
        
        for _, hunter in ipairs(get_all_hunters()) do 
            hunters_function(hunter)
        end

        runner_function(runner)
        if helper then helper_function(helper) end

        if state.time_level == 60*10 then 
            for i, uid in ipairs(coffins) do 
                local coffin = get_entity(uid) --[[@as Coffin]]
                coffin:damage(-1, 99, 0, 0, 0, 0)
                coffin:destroy()
            end
        end

        if state.time_level >= 60*3 then 
            set_explosion_mask(MASK.PLAYER | MASK.MOUNT | MASK.MONSTER | MASK.ITEM | MASK.ACTIVEFLOOR | MASK.FLOOR)
        end
        if state.time_level < 60*4 then 
            set_explosion_mask(MASK.MOUNT | MASK.MONSTER | MASK.ITEM | MASK.ACTIVEFLOOR | MASK.FLOOR)
        end

        local did_ten_sec = false

        if (state.level_count ~= 0 or coffin_count ~= 0) then 
            did_ten_sec = true
        end

        if state.time_level == 60*10 then
            local exit_door = get_entities_by(ENT_TYPE.FLOOR_DOOR_EXIT, MASK.FLOOR, LAYER.BOTH)
            for i, uid in ipairs(exit_door) do
                local x, y = get_position(uid)
                unlock_door_at(x, y)
            end
        end
        if not did_ten_sec and state.time_level == 60*5 then
            local exit_door = get_entities_by(ENT_TYPE.FLOOR_DOOR_EXIT, MASK.FLOOR, LAYER.BOTH)
            for i, uid in ipairs(exit_door) do
                local x, y = get_position(uid)
                unlock_door_at(x, y)
            end
        end
    end
end, ON.POST_UPDATE)

set_callback(function()
    local state = get_local_state() --[[@as StateMemory]]
    local prng = get_local_prng() --[[@as PRNG]]
    if state.level == 1 and state.world == 1 then 
        local pair1, pair2 = get_adventure_seed(true)
        set_adventure_seed(pair1 + 1, pair2 + 1)
    end
    if state.screen == SCREEN.LEVEL then 
        local exit_door = get_entities_by(ENT_TYPE.FLOOR_DOOR_EXIT, MASK.FLOOR, LAYER.BOTH)
        local tiles = get_entities_by(ENT_TYPE.FLOOR_GENERIC, MASK.FLOOR, LAYER.BOTH)
        for i, uid in ipairs(exit_door) do 
            local x, y = get_position(uid)
            lock_door_at(x, y)
        end
        local hunters = get_all_hunters()
        for _, hunter in ipairs(hunters) do
            if hunter.health > 0 then
                hunter.inventory.time_of_death = 0
            end
        end
        for i, uid in ipairs(tiles) do 
            local x, y, l = get_position(uid)
            if options.crates and (position_is_valid(x, y+1, l, POS_TYPE.ALCOVE) or position_is_valid(x, y+1, l, POS_TYPE.HOLE) or position_is_valid(x, y+1, l, POS_TYPE.PIT)) then
                if prng:random_chance(8, PRNG_CLASS.ENTITY_VARIATION) then 
                    local present = get_entity(spawn(ENT_TYPE.ITEM_PRESENT, x, y+1, l, 0, 0)) --[[@as Container]]
            
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

---comment
---@param ctx GuiDrawContext
set_callback(function(ctx)
  local me = get_local_player()
  if me ~= nil then 
    local runner = get_runner(get_max_players())
    if runner and not i_am_runner() then 
        local x, y, l = get_position(runner.uid)
        local cx, cy = screen_position(x, y)
        ctx:draw_circle_filled(cx, cy-0.03, 0.04, rgba(255, 0, 0, 100))
    end
    local helper = get_helper()
    if helper and not i_am_helper() then 
        local x, y, l = get_position(helper.uid)
        local cx, cy = screen_position(x, y)
        ctx:draw_circle_filled(cx, cy-0.03, 0.04, rgba(255, 255, 0, 100))
    end
  end
end, ON.GUIFRAME)

---dumb cosmic code runs this twice
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