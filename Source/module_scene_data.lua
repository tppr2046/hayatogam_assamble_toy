-- module_scene_data.lua
-- 關卡場景資料定義

SceneData = {}

-- 關卡 1: 初級訓練場
SceneData = {
    Level1 = {
    -- 關卡總長度 (決定場景捲動的極限)
    width = 800, 
    
    -- 地面高度 (與 state_mission.lua 中的 GROUND_Y = 200 保持一致)
    ground_y = 200, 
    
    -- 障礙物定義
    -- 格式: {x, width, height}
    -- Y 座標由 ground_y 決定，障礙物會坐在地面上
    obstacles = {
        -- 示例障礙物 1: 矮箱子 (機甲無法直接通過，但可跳躍)
        {x = 350, width = 50, height = 30}, 
        
        -- 示例障礙物 2: 較高的障礙
        {x = 550, width = 80, height = 60},
    },
    }

    -- 敵人或其他物件 (暫時留空)

}

return SceneData