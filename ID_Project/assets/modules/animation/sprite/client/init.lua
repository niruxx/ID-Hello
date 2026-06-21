-- modules/animation/sprite/client/init.lua
-- Plays sprite atlas animations driven by animation/sprite.state (server-authoritative).
-- Clips, tile layout, frame index, and frame timer are kept in a plain Lua table
-- so they are never overwritten when the server-synced component is updated.

local AnimationSprite = require("modules/animation/sprite/shared/init.lua")

local function frame_rect(frame, columns, tile_size)
    local tile_w = tile_size.x or tile_size[1] or 16
    local tile_h = tile_size.y or tile_size[2] or 16
    local col    = frame % columns
    local row    = math.floor(frame / columns)
    return {
        min = { x = col * tile_w,              y = row * tile_h },
        max = { x = col * tile_w + tile_w,     y = row * tile_h + tile_h },
    }
end

-- Plain Lua table — never goes through the ECS component, so net_sync
-- updates to animation/sprite cannot reset frame progress.
local anim_data = {}  -- [entity_id] → { clips, tile_size, columns, anim_entity_id,
                      --                  last_state, frame_index, frame_timer }

---------------------------------------------------------------------------
-- Init: load image, spawn sprite child, cache clip data locally
---------------------------------------------------------------------------
register_system("First", function(world)
    local entities = world:query({ added = { "animation/sprite" } })
    for _, entity in ipairs(entities) do
        local anim = entity:get("animation/sprite")

        local image_path = anim.image
        if not image_path then
            print(string.format("[ANIMATION/SPRITE/CLIENT] WARNING: entity %d has no image", entity:id()))
            goto continue
        end

        local tile_size = anim.tile_size or { x = 16, y = 16 }
        local columns   = anim.columns  or 1
        local clips     = anim.clips    or {}
        local idle      = clips.idle    or { frames = { 0 }, fps = 1 }
        local first_frame = (idle.frames and idle.frames[1]) or 0
        local scale     = anim.scale    or 1.0
        local image     = load_asset(image_path)

        local anim_entity = spawn({
            Transform = {
                translation = { x = 0, y = 0, z = anim.z or 1.0 },
                scale       = { x = scale, y = scale, z = 1.0 },
            },
            Sprite = {
                image       = image,
                rect        = frame_rect(first_frame, columns, tile_size),
                custom_size = { x = tile_size.x or 16, y = tile_size.y or 16 },
            },
        }):with_parent(entity:id())

        -- Store everything that must survive server component updates locally
        anim_data[entity:id()] = {
            clips          = clips,
            tile_size      = tile_size,
            columns        = columns,
            image          = image,
            anim_entity_id = anim_entity:id(),
            last_state     = nil,
            frame_index    = 1,
            frame_timer    = 0.0,
        }

        print(string.format("[ANIMATION/SPRITE/CLIENT] Sprite spawned for entity %d (image=%s)",
            entity:id(), image_path))

        ::continue::
    end
end)

---------------------------------------------------------------------------
-- Playback: advance frame based on clip fps, update sprite rect
---------------------------------------------------------------------------
register_system("Update", function(world)
    local dt = world:delta_time()

    local entities = world:query({ with = { "animation/sprite" } })
    for _, entity in ipairs(entities) do
        local data = anim_data[entity:id()]
        if not data then goto continue end

        local anim  = entity:get("animation/sprite")
        local state = anim.state or "idle"
        local clips = data.clips
        local clip  = clips[state] or clips["idle_down"] or clips.idle
        if not clip or not clip.frames or #clip.frames == 0 then goto continue end

        -- Reset frame when clip changes
        if data.last_state ~= state then
            data.frame_index = 1
            data.frame_timer = 0.0
        end

        -- Advance frame timer
        local fps = (clip.fps or 1) * (anim.speed or 1.0)
        if fps > 0 and #clip.frames > 1 then
            data.frame_timer = data.frame_timer + dt
            local frame_time = 1.0 / fps
            while data.frame_timer >= frame_time do
                data.frame_timer  = data.frame_timer - frame_time
                data.frame_index  = data.frame_index + 1
                if data.frame_index > #clip.frames then
                    data.frame_index = 1
                end
            end
        end

        -- Update sprite rect
        local anim_entity = world:get_entity(data.anim_entity_id)
        if anim_entity then
            local frame = clip.frames[data.frame_index] or clip.frames[1]
            anim_entity:patch({
                Sprite = {
                    rect        = frame_rect(frame, data.columns, data.tile_size),
                    custom_size = { x = data.tile_size.x or 16, y = data.tile_size.y or 16 },
                },
            })
        end

        data.last_state = state

        ::continue::
    end
end, { label = "SpriteAnimation", after = { "Animation" } })
