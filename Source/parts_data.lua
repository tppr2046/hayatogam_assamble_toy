-- parts_data.lua
import "CoreLibs/graphics"
local gfx = playdate.graphics

local parts_data = {
    ["GUN"] = {
        name = "GUN",
        hp = 10,
        weight = 3,
        slot_x = 1,
        slot_y = 1,
            color = gfx.kColorBlack,
            image = "images/gun.png",
        -- placement_row: "TOP", "BOTTOM", or "BOTH"
        placement_row = "BOTH"
    },
    ["WHEEL"] = {
        name = "WHEEL",
        hp = 12,
        weight = 4,
        slot_x = 3,
        slot_y = 1,
            color = gfx.kColorBlack,
            image = "images/wheel.png",
            placement_row = "BOTTOM"
    },
    ["CANON"] = {
        name = "CANON",
        hp = 30,
        weight = 10,
        slot_x = 2,
        slot_y = 1,
            color = gfx.kColorBlack,
            image = "images/canon.png",
            placement_row = "TOP"
    }
}

return parts_data