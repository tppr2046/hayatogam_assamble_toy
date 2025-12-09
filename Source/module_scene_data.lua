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
            { x = 350, width = 50, height = 30 },
            { x = 550, width = 80, height = 60 },
        },

        -- 測試用敵人列表
        enemies = {
            { x = 300, y = 0, type = "BASIC_ENEMY" },
        },
    }
}

return SceneData