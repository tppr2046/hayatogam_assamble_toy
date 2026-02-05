-- enemy_data.lua
-- 導出所有敵人類型的詳細屬性 (已移除中文字符)

return {
    ["BASIC_ENEMY"] = {
        name = "BASIC TRAINER UNIT", hp = 20, attack = 5, 
        move_type = "MOVE FORWARD/BACK", attack_type = "FIRE BULLET",
        -- 移動參數
        move_probability = 0.7,  -- 70% 機率會移動
        move_range = 100,        -- 移動範圍（像素）
        move_speed = 20,         -- 移動速度
        -- 砲彈屬性 multiplier：水平速度相對於玩家移動速度、以及重力的倍率
        projectile_speed_mult = 30, -- 30 = 水平速度接近玩家感覺
        projectile_grav_mult = 20,  -- 20 = 重力感接近玩家
        -- 敵人圖片
        image = "images/enemy1",
        -- 子彈發射位置（相對於敵人左上角的偏移，x, y）
        bullet_offset_x = 4,  -- 從敵人中心發射
        bullet_offset_y = 6   -- 從敵人中間高度發射
    },
    
    ["HEAVY_ENEMY"] = {
        name = "HEAVY ARMOR UNIT", hp = 80, attack = 10, 
        move_type = "IMMOBILE", attack_type = "SWING ATTACK",
        -- 敵人圖片
        image = "images/enemy2",
        -- 子彈發射位置
        bullet_offset_x = 4,
        bullet_offset_y = 6
    },
    
    ["JUMP_ENEMY"] = {
        name = "JUMP UNIT", hp = 15, attack = 8,
        move_type = "JUMP", attack_type = "CONTACT",
        -- 跳躍參數
        jump_velocity = -6.0,     -- 跳躍初速度
        jump_cooldown = 2.0,      -- 跳躍間隔（秒）
        jump_horizontal = 30,     -- 水平移動速度
        -- 敵人圖片（3-frame imagetable）
        -- Frame 1: 站立, Frame 2: 跳起, Frame 3: 空中
        image = "images/enemy_jump"
    },
    
    ["SWORD_ENEMY"] = {
        name = "SWORD UNIT", hp = 30, attack = 12,
        move_type = "IMMOBILE", attack_type = "SWING SWORD",
        -- 劍揮動參數
        sword_swing_cooldown = 3.0,  -- 揮動間隔（秒）
        sword_swing_speed = 180,     -- 揮動速度（度/秒）
        sword_swing_min = -180,         -- 揮動最小角度（度）
        sword_swing_max = 0,       -- 揮動最大角度（度）
        -- 劍旋轉軸心位置偏移（相對於敵人中心的偏移，x, y）
        sword_pivot_offset_x = 0,    -- 軸心 X 偏移（正值向右）
        sword_pivot_offset_y = 0,    -- 軸心 Y 偏移（正值向下）
        -- 劍圖內部旋轉軸心偏移（相對於劍圖中心的偏移，x, y）
        sword_image_pivot_offset_x = -16,  -- 劍圖軸心 X 偏移（正值向右）
        sword_image_pivot_offset_y = 0,  -- 劍圖軸心 Y 偏移（正值向下）
        -- 敵人圖片
        image = "images/enemy2",
        -- 劍圖片（可選，若不指定則使用預設的直線繪制）
        sword_image = "images/enemy2_sword"
    },
    
    ["MINE"] = {
        name = "MINE", hp = 1, attack = 20,
        move_type = "IMMOBILE", attack_type = "EXPLODE",
        -- 爆炸參數
        explode_delay = 2.0,      -- 觸發後爆炸延遲（秒）
        explode_radius = 50,      -- 爆炸範圍（像素）
        explode_damage = 20,      -- 爆炸傷害
        -- 敵人圖片
        image = "images/mine"
    },

    ["SHIELD_ROBOT"] = {
        name = "SHIELD ROBOT", hp = 10, attack = 8,
        move_type = "SHIELD_MOVEMENT", attack_type = "SHIELD_FIRE",
        -- 盾牌參數
        shield_up_duration = 3.0,     -- 盾牌舉起時間（秒）
        shield_down_duration = 2.0,   -- 盾牌收起時間（秒）
        shield_raised = true,         -- 初始盾牌狀態（true=舉起）
        shield_width = 16,            -- 盾牌寬度（像素）
        shield_height = 20,           -- 盾牌高度（像素）
        shield_offset_x = -20,        -- 盾牌相對於敵人的 X 偏移（向左）
        shield_offset_y = 6,          -- 盾牌相對於敵人的 Y 偏移（向下）
        -- 移動參數（盾牌收起時）
        move_speed = 25,
        move_range = 80,
        -- 砲彈屬性（盾牌收起時發射）
        projectile_speed_mult = 25,
        projectile_grav_mult = 15,
        fire_cooldown = 1.5,
        -- 敵人圖片
        image = "images/enemy1",
        bullet_offset_x = 4,
        bullet_offset_y = 6
    },

    ["DRONE"] = {
        name = "DRONE", hp = 10, attack = 6,
        move_type = "AERIAL", attack_type = "FIRE BULLET",
        -- 飛行參數
        flight_height_min = 40,       -- 最小飛行高度（像素，相對於地面向上）
        flight_height_max = 80,       -- 最大飛行高度（像素）
        flight_speed = 30,            -- 飛行速度（像素/秒）
        vertical_oscillation = 20,    -- 上下振幅（像素）
        vertical_speed = 1.5,         -- 上下運動速度（1 = 1 個單位/秒）
        -- 砲彈屬性
        projectile_speed_mult = 35,   -- 直射速度倍率
        projectile_grav_mult = 0.1,   -- 低重力（直射）
        fire_cooldown = 1.2,
        -- 敵人圖片
        image = "images/enemy1",
        bullet_offset_x = 4,
        bullet_offset_y = 6
    }
}