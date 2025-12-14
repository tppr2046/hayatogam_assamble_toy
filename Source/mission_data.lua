-- mission_data.lua
-- 導出所有任務的目標、場景配置和獎勵 (已移除中文字符)

local missions = {
    ["M001"] = {
        id = "M001", 
        name = "TRAINING MISSION 1", 
        category = "ELIMINATION", 
        description = "Eliminate all incoming trainer units and learn movement controls.",
        prerequisite = 0,  -- 0 表示初始任務，無前置要求
        time_limit = 60,  -- 關卡時間限制（秒），-1 表示無時間限制
        
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
            delivery_target = nil  -- { x = 600, y = 200, width = 40, height = 40 }
        },
        
        -- 任務獎勵（資源）
        reward_steel = 30,
        reward_copper = 20,
        reward_rubber = 15
    },
    ["M002"] = {
        id = "M002", 
        name = "TRAINING MISSION 2", 
        category = "ELIMINATION", 
        description = "Eliminate all incoming trainer units and learn movement controls.",
        prerequisite = "M001",  -- 需要完成 M001 才會顯示
        time_limit = -1,  -- 關卡時間限制（秒），-1 表示無時間限制
        
        -- 關卡目標
        objective = {
            type = "DELIVER_STONE",  -- 可選: "ELIMINATE_ALL", "DELIVER_STONE"
            description = "Deliver the stone to the target zone"
        },
        
        -- 關卡場景設定
        scene = {
            width = 800, 
            ground_y = 220, 
            
            -- 場景障礙物件
            obstacles = {
                 { x = 500, y = 0, image = "images/gun_panel.png" }  -- x, y 為位置，y=0 表示在地面上，image 為圖片路徑
            },
            
            -- 可互動物件（石頭）
            stones = {
                { x = 200, y = 0, target_id = "target1", image = "images/stone.png" },  -- x, y 為初始位置，y=0 表示在地面上，target_id 指定要放到哪個目標
                { x = 410, y = 0, target_id = "target2", image = "images/stone.png" },  -- x, y 為初始位置，y=0 表示在地面上，target_id 指定要放到哪個目標

            },
            
            -- 任務敵人（添加測試敵人）
            enemies = {
                { type = "BASIC_ENEMY", x = 300, y = 0 },
--                { type = "BASIC_ENEMY", x = 500, y = 0 },
            },
            
            -- 石頭目標物件（用於 DELIVER_STONE 目標）
            delivery_targets = {
                { id = "target1", x = 350, y = 0, width = 40, height = 40 },  -- id 用於匹配石頭的 target_id
                { id = "target2", x = 450, y = 0, width = 40, height = 40 }  -- id 用於匹配石頭的 target_id

            }
        },
        
        -- 任務獎勵（資源）
        reward_steel = 30,
        reward_copper = 20,
        reward_rubber = 15
    }


}

return missions