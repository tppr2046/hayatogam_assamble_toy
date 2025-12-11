-- module_scene_data.lua
-- 關卡場景資料定義

SceneData = {}

-- 關卡 1: 初級訓練場
SceneData = {
    Level1 = {
        -- 關卡總長度 (決定場景捲動的極限)
        width = 800,

        -- 地面高度
        ground_y = 200,

        -- 障礙物定義
        obstacles = {

        },
        
        -- 可互動物件（石頭）
        stones = {
            { x = 400, y = 0 },  -- x, y 為初始位置，y=0 表示在地面上
        },

        -- 測試用敵人列表
        enemies = {

        },
    }
}

return SceneData