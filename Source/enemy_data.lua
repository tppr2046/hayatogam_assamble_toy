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
        image = "images/enemy01",
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
        -- ★ 2026-08-10 量自新圖：enemy2_sword.png 48×16，握把圓環中心 (7.0, 8.0)
        --   → 相對圖中心 (24, 8) 的偏移 = (-17, 0)。舊圖圓環在 (8.0, 8.0) 故舊值為 -16。
        sword_image_pivot_offset_x = -17,  -- 劍圖軸心 X 偏移（正值向右）
        sword_image_pivot_offset_y = 0,  -- 劍圖軸心 Y 偏移（正值向下）
        -- 劍長（軸心到劍尖，像素）。★繪製端與命中判定端共用這組欄位，改一邊等於兩邊都改
        --   量自新圖：圓環中心 x=7.0 → 劍尖 x=48.0，故 41
        sword_length = 41,
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
        -- 敵人圖片（2026-08-10 由單張 mine.png 改為 mine-table-32-16.png，3 格）
        --   第 1 格 = 地雷本體（畫布下緣 y=9~15，踩在地面上），一直畫
        --   第 2/3 格 = 警示燈（畫布上緣 y=2~9），★與本體同一張 32×16 畫布，
        --   所以同座標直接疊畫就會對位，不需要額外偏移
        image = "images/mine",
        -- 觸發後的警示燈閃爍
        warn_frame_a = 2,         -- 交替的第一格
        warn_frame_b = 3,         -- 交替的第二格
        warn_blink_speed = 10     -- 每秒切換次數（越大閃越快）
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
        -- 敵人圖片（2026-08-07 由 enemy1 改為專屬圖 enemy02，32×32）
        image = "images/enemy02",
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
        projectile_grav_mult = 0.02,   -- 低重力（直射）
        fire_cooldown = 1.2,
        -- 敵人圖片（2026-08-09 由借用的 enemy1 換成專屬 6 幀動畫）
        image = "images/enemy_drone",
        anim_fps = 12,                -- 旋翼循環播放（6 幀 / 12fps = 0.5 秒一圈）
        -- ★ 子彈從**下方槍口**射出。座標量自 sprite（32×32）：
        --   槍管在 x=13~18、y=20~23，所以出口＝(16, 24)。換圖後重量即可。
        bullet_offset_x = 6,
        bullet_offset_y = 24
    }
}