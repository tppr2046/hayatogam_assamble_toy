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
        align_image_top = false,  -- 圖片底部對齊格子底部（預設行為）
        -- GUN 特有屬性：砲彈發射
        fire_cooldown = 1.0,  -- 每 1 秒發射一次
        projectile_damage = 5,  -- 砲彈傷害
        projectile_speed_mult = 25,  -- 速度倍率（相對於基準速度）
        projectile_grav_mult = 1.0  -- 重力倍率（相對於世界重力 0.5）
    },
    ["WHEEL"] = {
        name = "WHEEL",
        hp = 12,
        weight = 4,
        slot_x = 3,
        slot_y = 1,
            color = gfx.kColorBlack,
            image = "images/wheel.png",
            placement_row = "BOTTOM",
        align_image_top = false,  -- 圖片底部對齊格子底部（預設行為）
        move_speed = 2.0  -- 左右移動速度
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
        align_image_top = false,  -- 圖片底部對齊格子底部（預設行為）
        -- CANON 特有屬性：砲彈發射
        fire_cooldown = 0.5,  -- 每 0.5 秒可以發射一次
        projectile_damage = 10,  -- 砲彈傷害
        projectile_speed_mult = 30,  -- 速度倍率（相對於基準速度）
        projectile_grav_mult = 20,  -- 重力倍率（相對於世界重力 0.5）
        -- CANON 轉動控制
        angle_range = 90,  -- 轉動角度範圍（總範圍，-45 到 +45 度）
        crank_degrees_per_rotation = 15  -- crank 轉 1 圈（360度）產生的 canon 角度變化
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
            placement_row = "TOP",
        align_image_top = false  -- 圖片底部對齊格子底部（預設行為）
    },
    ["FEET"] = {
        name = "FEET",
        hp = 12,
        weight = 7,
        slot_x = 3,
        slot_y = 1,
            color = gfx.kColorBlack,
            image = "images/feet.png",
            placement_row = "BOTTOM",
        -- FEET 特有屬性
        align_image_top = true,  -- 圖片上緣對齊格子上緣（圖片下半部會超出格子）
        move_speed = 3.0,  -- 左右移動速度
        jump_velocity = -8.0  -- 跳躍初速度（負值=向上）
    }


}

return parts_data