-- Place a structure at position `pos` with rotation `rot`
-- `structure` is a table with flat VoxelArea form array `data`, dimension vector `size`, and position vector `center`
local function place_structure(pos, structure, rot)
    rot = rot or {x = 0, y = 0, z = 0}

    local vm = minetest.get_voxel_manip()
    local msize = math.max(structure.size.x, structure.size.y, structure.size.z)
    local emin, emax = vm:read_from_map(vector.subtract(pos, msize), vector.add(pos, msize))
    local data = vm:get_data()

    local varea = VoxelArea:new({MinEdge = emin, MaxEdge = emax})
    local sarea = VoxelArea:new({MinEdge = {x = 0, y = 0, z = 0}, MaxEdge = vector.subtract(structure.size, 1)})

    -- Place the localized non-padded structure in a usable VoxelArea
    for p, id in pairs(structure.data) do
        p = sarea:position(p)

        local center = vector.round(structure.center)
        -- Get the direction from the center to pos and rotate it
        local rotdir = vector.rotate(vector.direction(center, p), rot)
        -- Re-apply length
        local lpos = vector.multiply(vector.normalize(rotdir), vector.distance(center, p))
        -- Apply center offset and round
        local rotated = vector.round(vector.add(lpos, center))

        -- Non-destructive
        local idx = varea:indexp(vector.add(rotated, pos))
        if data[idx] == minetest.CONTENT_AIR or data[idx] == minetest.CONTENT_IGNORE then
            data[idx] = id
        end
    end

    vm:set_data(data)
    vm:write_to_map(true)
end

-- Returns a z value given cone radius, cone height, x, and y
local function cone_z(r, h, x, y)
    -- Cone formula (x^2 + y^2 = z^2)
    return -math.sqrt((x ^ 2) / ((r * (1 / h)) ^ 2) + (y ^ 2) / ((r * (1 / h)) ^ 2)) + h
end

-- Place a cone with radius and height
local function cone(pos, radius, height, rot, itemname)
    local size = vector.apply({x = radius * 2 + 1, y = height, z = radius * 2 + 1}, math.ceil)
    local cid = minetest.get_content_id(itemname)
    local data = {}

    for z = -radius, radius do
        for x = -radius, radius do
            local y = cone_z(radius, height, x, z)
            if y >= 0 then
                for i = 0, y do
                    local p = vector.round({x = x + radius, y = i, z = z + radius})
                    data[p.z * size.y * size.x + p.y * size.x + p.x + 1] = cid
                end
            end
        end
    end

    place_structure(vector.subtract(pos, {x = radius - 1, y = 0, z = radius - 1}), {
        size = size,
        data = data,
        center = {x = radius / 2, y = 0, z = radius / 2}
    }, rot)
end

-- Place multiple cones along an arc of size `angle` and radius `blast_radius` at `pitch` and `yaw`
local function cone_arc(pos, pitch, yaw, angle, blast_radius, cone_radius, length, itemname)
    local inc = math.pi * 2 / blast_radius
    for y = -angle / 2, angle / 2, inc do
        local dir = minetest.yaw_to_dir(yaw + y)
        local off = vector.multiply(dir, blast_radius)
        local p = vector.add(pos, off)
        cone(vector.floor(p), cone_radius, length, {x = pitch, y = yaw + y, z = 0}, itemname)
    end
end

-- Place 3 cone arcs of decreasing size
local function blast(pos, yaw, size)
    for layer = 0, 2 do
        -- Pitch each layer up slightly
        local pitch = math.rad(-80 + layer * 20)
        -- Make each layer slightly smaller
        local angle = math.rad(160 - layer * 20)
        local b_rad = size * (1 / 3)
        local c_rad = 4 - layer
        local length = math.ceil(size * (2 / 3) * ((5 - layer) / 5))
        cone_arc(pos, pitch, yaw, angle, b_rad, c_rad, length, "default:ice")
    end
end

-- Emit cloud of particles in blast shape
local function blast_cloud(pos, yaw, size)
    -- This will spawn between 362 and 3982 particles (inclusive), theoretically
    for y = -90, 90, 0.5 do
        for _ = 0, math.random(0, 10) do
            math.randomseed(y)

            local dir = vector.normalize(vector.rotate({x = 0, y = 0, z = 1}, {
                x = math.rad(math.random(0, 30)),
                y = yaw + math.rad(y),
                z = 0
            }))

            minetest.add_particle({
                pos = vector.add(pos, vector.multiply(dir, math.random(0, 20) / 10)),
                velocity = vector.multiply(dir, math.random(5, 6)),
                acceleration = vector.multiply(dir, -0.1),
                expirationtime = size / 10 + math.random(0, 10) / 10,
                size = 0,
                node = {name = "default:ice"},
            })
        end
    end
end

-- Change ice texture because mine looks cooler
minetest.register_on_mods_loaded(function()
    if minetest.get_modpath("default") then
        minetest.override_item("default:ice", {
            tiles = {"iceblast_ice.png"},
            drawtype = "glasslike",
            sunlight_propagates = true,
            use_texture_alpha = true,
        })

        minetest.register_craft({
            output = "iceblast:staff",
            recipe = {
                {"default:ice"},
                {"default:mese_crystal_fragment"},
                {"default:stick"},
            }
        })
    else
        minetest.register_node(":default:ice", {
            description = "Ice",
            tiles = {"iceblast_ice.png"},
            drawtype = "glasslike",
            paramtype = "light",
            sunlight_propagates = true,
            use_texture_alpha = true,
            is_ground_content = false,
            groups = {cracky = 3, cools_lava = 1, slippery = 3},
        })
    end
end)

minetest.register_tool("iceblast:staff", {
    description = "Ice Staff",
    inventory_image = "iceblast_staff.png",
    on_use = function(_, user)
        minetest.sound_play({name = "iceblast_blast"}, {pos = user:get_pos()}, true)
        blast_cloud(vector.add(user:get_pos(), {x = 0, y = 1, z = 0}), user:get_look_horizontal(), 30)
        blast(vector.add(user:get_pos(), {x = 0, y = 2, z = 0}), user:get_look_horizontal(), 30)
    end
})
