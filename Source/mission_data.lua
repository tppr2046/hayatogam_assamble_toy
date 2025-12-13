-- mission_data.lua
-- 導出所有任務的目標、場景配置和獎勵 (已移除中文字符)

local missions = {
    ["M001"] = {
        id = "M001", 
        name = "TRAINING MISSION 1", 
        category = "ELIMINATION", 
        description = "Eliminate all incoming trainer units and learn movement controls.",
        
        -- 關卡目標
        objective = {
            type = "ELIMINATE_ALL",  -- 可選: "ELIMINATE_ALL", "DELIVER_STONE"
            description = "Defeat all enemies"
        },
        
        -- 關卡場景設定
        scene = {
            width = 800, 
            ground_y = 220, 
            
            -- 場景障礙物件
            obstacles = {
            },
            
            -- 可互動物件（石頭）
            stones = {
--                { x = 400, y = 0 },  -- x, y 為初始位置，y=0 表示在地面上
            },
            
            -- 任務敵人（添加測試敵人）
            enemies = {
                { type = "BASIC_ENEMY", x = 300, y = 0 },
                { type = "BASIC_ENEMY", x = 500, y = 0 },
            },
            
            -- 石頭目標地點（用於 DELIVER_STONE 目標）
            delivery_zone = nil  -- { x = 600, y = 200, width = 40, height = 40 }
        },
        
        -- 任務獎勵（資源）
        reward_steel = 30,
        reward_copper = 20,
        reward_rubber = 15
    }
}

return missions