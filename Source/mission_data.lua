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
                {type = "CRATE", x = 350, y = 200, height = 20, width = 50, is_pushable = true},
                {type = "WALL", x = 600, y = 150, height = 70, width = 10, is_pushable = false}
            },
            
            -- 任務敵人
            enemies = {
                {type = "BASIC_ENEMY", x = 300, y = 0},
                {type = "BASIC_ENEMY", x = 450, y = 0}
            },
            
            mission_objects = {} 
        },
        
        reward_money = 50,
        reward_part_id = "MISSILE_V2"
    }
}