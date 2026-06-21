-- modules/animation/sprite/shared/init.lua

---------------------------------------------------------------------------
-- Init: configure net_sync for animation
---------------------------------------------------------------------------
register_system("First", function(world)
    local entities = world:query({ added = { "animation/sprite" } })
    for _, entity in ipairs(entities) do
        local sprite = entity:get("animation/sprite")
        local initial_state = sprite.sprite and "idle_down" or "idle"
        local initial_facing = sprite.sprite and "down" or nil
        entity:patch({
            ["animation/sprite"] = {
                state = initial_state, speed = 1.0, facing = initial_facing
            },
            net_sync = {
                ["animation/sprite"] = { authority = "server" },
            },
        })

        print(string.format("[ANIMATION/SPRITE/SERVER] Initialized for entity %d (model=%s)",
            entity:id(), tostring(sprite.model)))
    end
end)

---------------------------------------------------------------------------
-- State machine: determine animation state from Velocity2d
---------------------------------------------------------------------------
register_system("Update", function(world)
    local entities = world:query({
        with = { "animation/sprite", "Velocity2d" },
    })
    for _, entity in ipairs(entities) do
        local anim = entity:get("animation/sprite")
        if not anim.clips then goto continue end

        local vel = entity:get("Velocity2d")
        if not vel.linvel then goto continue end

        local vx = vel.linvel.x or 0
        local vy = vel.linvel.y or 0
        local speed = math.sqrt(vx * vx + vy * vy)

        -- Walk vs idle: prefer input_movement (reliably synced client→server) over
        -- Velocity2d, which can read as zero depending on system scheduling order.
        local is_moving = false
        local im = entity:get("input_movement")
        if im then
            is_moving = (im.forward or im.backward or im.left or im.right) and true or false
        else
            is_moving = speed > 0.1
        end

        -- Facing direction: cursor_facing (sent by owning client) takes priority.
        -- Falls back to velocity direction, then last known facing.
        local facing
        local cf = entity:get("cursor_facing")
        if cf and cf.dir then
            facing = cf.dir
        elseif speed > 0.1 then
            if math.abs(vx) > math.abs(vy) then
                facing = vx > 0 and "right" or "left"
            else
                facing = vy < 0 and "down" or "up"
            end
        else
            facing = anim.facing or "down"
        end

        local new_state = is_moving and ("walk_" .. facing) or ("idle_" .. facing)
        local new_speed = 1.0

        if anim.state ~= new_state or anim.speed ~= new_speed or anim.facing ~= facing then
            entity:patch({ ["animation/sprite"] = { state = new_state, speed = new_speed, facing = facing } })
        end

        ::continue::
    end
end, { label = "SpriteAnimationState", after = { "Movement2d" } })
