-- parts_data.lua
import "CoreLibs/graphics"
local gfx = playdate.graphics

local parts_data = {
    ["ARM-01"] = {
        name = "Arm Mk1",
        hp = 10,
        weight = 3,
        slot_x = 1,
        slot_y = 1,
        color = gfx.kColorBlack,
        -- placement_row: "TOP", "BOTTOM", or "BOTH"
        placement_row = "BOTH"
    },
    ["LEG-02"] = {
        name = "Leg Mk2",
        hp = 12,
        weight = 4,
        slot_x = 1,
        slot_y = 1,
        color = gfx.kColorBlack,
        placement_row = "BOTTOM"
    },
    ["CORE-03"] = {
        name = "Core Unit",
        hp = 30,
        weight = 10,
        slot_x = 1,
        slot_y = 1,
        color = gfx.kColorBlack,
        placement_row = "TOP"
    }
}

return parts_data