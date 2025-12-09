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
        color = gfx.kColorBlack
    },
    ["LEG-02"] = {
        name = "Leg Mk2",
        hp = 12,
        weight = 4,
        slot_x = 1,
        slot_y = 1,
        color = gfx.kColorBlack
    },
    ["CORE-03"] = {
        name = "Core Unit",
        hp = 30,
        weight = 10,
        slot_x = 1,
        slot_y = 1,
        color = gfx.kColorBlack
    },
    -- 舊示例零件（保留供測試）
    ["WHEEL_2X1"] = {
        name = "Wheel",
        hp = 20,
        weight = 5,
        slot_x = 2,
        slot_y = 1,
        color = gfx.kColorBlack
    },
    ["ARMOR_1X1"] = {
        name = "Armor",
        hp = 10,
        weight = 2,
        slot_x = 1,
        slot_y = 1,
        color = gfx.kColorBlack
    },
    ["FRAME_3X1"] = {
        name = "Light Frame",
        hp = 15,
        weight = 3,
        slot_x = 3,
        slot_y = 1,
        color = gfx.kColorBlack
    }
}

return parts_data