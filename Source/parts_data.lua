-- parts_data.lua
import "CoreLibs/graphics"
local gfx = playdate.graphics

local parts_data = {
    ["GUN"] = {
        name = "GUN",
        part_type = "GUN",  -- 功能類別
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
        -- UI 操作介面圖片
        ui_panel = "images/gun_panel.png",
        -- GUN 特有屬性：砲彈發射
        fire_cooldown = 1.0,  -- 每 1 秒發射一次
        projectile_damage = 5,  -- 砲彈傷害
        projectile_speed_mult = 40,  -- 速度倍率（相對於基準速度）
        projectile_grav_mult = 0.2  -- 重力倍率（相對於世界重力 0.5）
    },
    ["WHEEL1"] = {
        name = "WHEEL",
        part_type = "WHEEL",  -- 功能類別
        hp = 12,
        weight = 4,
        slot_x = 3,
        slot_y = 1,
            color = gfx.kColorBlack,
            image = "images/wheel.png",
            placement_row = "BOTTOM",
        align_image_top = false,  -- 圖片底部對齊格子底部（預設行為）
        -- UI 操作介面圖片
        ui_panel = "images/wheel_panel.png",
        ui_stick = "images/wheel_stick.png",
        move_speed = 2.0  -- 左右移動速度
    },
    ["WHEEL2"] = {
        name = "WHEEL",
        part_type = "WHEEL",  -- 功能類別
        hp = 12,
        weight = 4,
        slot_x = 3,
        slot_y = 1,
            color = gfx.kColorBlack,
            image = "images/wheel2.png",
            placement_row = "BOTTOM",
        align_image_top = false,  -- 圖片底部對齊格子底部（預設行為）
        -- UI 操作介面圖片
        ui_panel = "images/wheel_panel.png",
        ui_stick = "images/wheel_stick.png",
        move_speed = 2.0  -- 左右移動速度
    },

    ["CANON"] = {
        name = "CANON",
        part_type = "CANON",  -- 功能類別
        hp = 30,
        weight = 10,
        slot_x = 2,
        slot_y = 1,
            color = gfx.kColorBlack,
            image = "images/canon.png",
            placement_row = "TOP",
        align_image_top = false,  -- 圖片底部對齊格子底部（預設行為）
        -- UI 操作介面圖片
        ui_panel = "images/canon_panel.png",
        -- CANON 特有屬性：砲彈發射
        fire_cooldown = 0.5,  -- 每 0.5 秒可以發射一次
        projectile_damage = 10,  -- 砲彈傷害
        projectile_speed_mult = 30,  -- 速度倍率（相對於基準速度）
        projectile_grav_mult = 20,  -- 重力倍率（相對於世界重力 0.5）
        -- CANON 轉動控制
        angle_min = 0,  -- 最小角度（度）
        angle_max = 90,  -- 最大角度（度）
        crank_degrees_per_rotation = 15  -- crank 轉 1 圈（360度）產生的 canon 角度變化
    },
    ["SWORD"] = {
        name = "SWORD",
        part_type = "SWORD",  -- 功能類別
        hp = 10,
        weight = 5,
        attack = 3,  -- 攻擊力
        slot_x = 1,
        slot_y = 1,
            color = gfx.kColorBlack,
            image = "images/sword.png",
            placement_row = "TOP",
        align_image_top = false,  -- 圖片底部對齊格子底部（預設行為）
        -- UI 操作介面圖片
        ui_panel = "images/sword_panel.png",
        ui_stick = "images/sword_stick.png"
    },
    ["FEET"] = {
        name = "FEET",
        part_type = "FEET",  -- 功能類別
        hp = 12,
        weight = 7,
        slot_x = 3,
        slot_y = 1,
            color = gfx.kColorBlack,
            image = "images/feet.png",
            placement_row = "BOTTOM",
        -- FEET 特有屬性
        align_image_top = true,  -- 圖片上緣對齊格子上緣（圖片下半部會超出格子）
        -- UI 操作介面圖片（先用與 WHEEL 相同的圖）
        ui_panel = "images/wheel_panel.png",
        ui_stick = "images/wheel_stick.png",
        move_speed = 3.0,  -- 左右移動速度
        jump_velocity = -8.0,  -- 跳躍初速度（負值=向上）
        animation_walk = "images/feet_walk"  -- 行走動畫 imagetable 路徑
    },
    ["CLAW"] = {
        name = "CLAW",
        part_type = "CLAW",  -- 功能類別
        hp = 15,
        weight = 8,
        slot_x = 1,
        slot_y = 1,
        color = gfx.kColorBlack,
        image = "images/claw_base.png",  -- 主圖片為底座
        placement_row = "TOP",
        align_image_top = false,  -- 圖片底部對齊格子底部
        -- UI 操作介面圖片（先用與 CANON 相同的圖）
        ui_panel = "images/claw_control",
        -- CLAW 特有屬性
        arm_image = "images/claw_arm.png",  -- 臂的圖片
        upper_image = "images/claw_upper.png",  -- 上爪圖片
        lower_image = "images/claw_lower.png",  -- 下爪圖片
        arm_angle_min = -90,  -- 臂最小角度（度）
        arm_angle_max = 90,  -- 臂最大角度（度）
        arm_rotate_speed = 2.0,  -- 上下鍵每幀旋轉速度（度）
        claw_angle_min = 0,  -- 爪子閉合角度（度）
        claw_angle_max = 45,  -- 爪子張開角度（度）
        crank_degrees_per_rotation = 30,  -- crank 轉 1 圈產生的爪子角度變化
        grab_threshold = 20  -- 抓取/投擲的角度臨界值（度）
    }


}

return parts_data