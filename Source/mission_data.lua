-- mission_data.lua
-- 導出所有任務的目標、場景配置和獎勵 (已移除中文字符)

return {
    ["M001"] = {
        id = "M001", 
        name = "TRAINING MISSION 1", 
        category = "ELIMINATION", 
        description = "Eliminate all incoming trainer units and learn movement controls.",
        
        -- 關卡場景設定
        scene = {
            width = 800, 
            ground_y = 220, 
            
            -- 場景障礙物件
            obstacles = {
            },
            
            -- 可互動物件（石頭）
            stones = {
                { x = 400, y = 0 },  -- x, y 為初始位置，y=0 表示在地面上
            },
            
            -- 任務敵人
            enemies = {
            },
            
            mission_objects = {} 
        },
        
        reward_money = 50,
        reward_part_id = "MISSILE_V2"
    }
}