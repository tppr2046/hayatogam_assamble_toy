-- parts_data.lua
import "CoreLibs/graphics"
local gfx = playdate.graphics

local parts_data = {
    ["GUN"] = {
        name = "GUN",
        hp = 10,
        weight = 3,
        attack = 5,  -- 攻擊力
        slot_x = 1,
        slot_y = 1,
            color = gfx.kColorBlack,
            image = "images/gun.png",
        -- placement_row: "TOP", "BOTTOM", or "BOTH"
        placement_row = "TOP",
        -- GUN 特有屬性：砲彈發射
        fire_cooldown = 1.0,  -- 每 1 秒發射一次
        projectile_vx = 50,  -- 砲彈水平速度
        projectile_vy = -2,  -- 砲彈垂直速度（負值=向上）
        projectile_damage = 5  -- 砲彈傷害
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
            placement_row = "TOP",
        -- CANON 特有屬性：砲彈發射
        fire_cooldown = 0.5,  -- 每 0.5 秒可以發射一次
        projectile_speed = 200,  -- 砲彈速度
        projectile_damage = 10  -- 砲彈傷害
    },
    ["SWORD"] = {
        name = "SWORD",
        hp = 10,
        weight = 5,
        attack = 3,  -- 攻擊力
        slot_x = 1,
        slot_y = 1,
            color = gfx.kColorBlack,
            image = "images/sword.png",
            placement_row = "TOP"
    }



}

return parts_data