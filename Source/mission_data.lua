-- mission_data.lua
-- 導出所有任務的目標、場景配置和獎勵 (已移除中文字符)

local missions = {
    ["M001"] = {
        id = "M001", 
        name = "MISSION 1", 
        category = "ELIMINATION", 
        description = "Eliminate all Enemies and learn movement controls.",
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
            -- 背景層設定：layer=0(後景,慢), layer=1(前景,快); x,y 為初始位置; image 為圖檔
            backgrounds = {
                { layer = 0, x = 50, y = 40, image = "images/bg_building3.png" },
                { layer = 1, x = 120, y = 70, image = "images/bg_building1.png" },
                { layer = 1, x = 260, y = 60, image = "images/bg_building2.png" },
                { layer = 0, x = 460, y = 60, image = "images/bg_building4.png" },
            },
            
            -- 地形配置（64px為一單位）
            -- 類型: "flat", "up15", "up30", "up45", "down15", "down30", "down45"
            -- height_offset: 相對於 ground_y 的高度偏移（負值=往上）
            terrain = {
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "up15", height_offset = 0 },     -- 從 height_offset=0 往上爬到17
                { type = "flat", height_offset = -17 },   -- 接續上一段的結束高度
                { type = "flat", height_offset = -17 },
                { type = "down15", height_offset = -17 }, -- 從 -17 往下降到17
                { type = "flat", height_offset = 0 },     -- 回到0
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 }
            },
            
            -- 場景障礙物件
            obstacles = {
            },
            
            -- 可互動物件（石頭）
            stones = {
--                { x = 400, y = 0 },  -- x, y 為初始位置，y=0 表示在地面上
            },
            
                -- 任務開始前對話（可選）：image 顯示在上方，lines 逐句以打字機顯示
                dialog = {
                    image = "images/dialog_bg",
                    lines = {
                        "Please...Pilot, the world is counting on you!",
                        "Choose your parts to operate your parts.",
                        "Defeat the enemies to complete the mission."
                    }
                },
            -- 任務敵人（y=0 表示在地面上，負值表示地面上方）
            enemies = {
                { type = "BASIC_ENEMY", x = 300, y = 0 },
                { type = "BASIC_ENEMY", x = 450, y = -17 },
            },
            
            -- 石頭目標地點（用於 DELIVER_STONE 目標）
            delivery_target = nil  -- { x = 600, y = 200, width = 40, height = 40 }
        },
        
        -- 任務獎勵（資源）
        reward_steel = 35,
        reward_copper = 10,
        reward_rubber = 15
    },
    ["M002"] = {
        id = "M002", 
        name = "Delivery Mission", 
        category = "DELIVER_STONE", 
        description = "Eliminate all incoming trainer units and learn movement controls.",
        prerequisite = "M001",  -- 需要完成 M001 才會顯示
        time_limit = -1,  -- 關卡時間限制（秒），-1 表示無時間限制
        
        -- 關卡目標
        objective = {
            type = "DELIVER_STONE",  -- 可選: "ELIMINATE_ALL", "DELIVER_STONE"
            description = "Deliver the stone to the target zone"
        },
        
                dialog = {
                    image = "images/dialog_bg",
                    lines = {
                        "There are many obstacles and rocks out there,",
                        "Remove all of the obstacles and put them to the target zone.",
                        "Good luck, Pilot!"
                    }
                },



        -- 關卡場景設定
        scene = {
            width = 1200, 
            ground_y = 220, 
            backgrounds = {
                { layer = 0, x = 30, y = 40, image = "images/bg_building2.png" },
                { layer = 1, x = 160, y = 70, image = "images/bg_building3.png" },
                { layer = 1, x = 200, y = 60, image = "images/bg_building1.png" },
                { layer = 0, x = 420, y = 60, image = "images/bg_building4.png" },
            },
            
            -- 地形配置（64px為一單位）
            -- 類型: "flat", "up15", "up30", "up45", "down15", "down30", "down45"
            terrain = {
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "up30", height_offset = 0 },     -- 從 height_offset=0 往上爬到17
                { type = "flat", height_offset = -35 },   -- 接續上一段的結束高度
                { type = "flat", height_offset = -35 },
                { type = "down30", height_offset = -35 }, -- 從 -17 往下降到17
                { type = "flat", height_offset = 0 },     -- 回到0
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "up15", height_offset = 0 },     -- 從 height_offset=0 往上爬到17
                { type = "flat", height_offset = -17 },   -- 接續上一段的結束高度
                { type = "flat", height_offset = -17 },
                { type = "down15", height_offset = -17 }, -- 從 -17 往下降到17
                { type = "flat", height_offset = 0 },     -- 回到0
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 }
            },
            
            -- 場景障礙物件
            obstacles = {
--                 { x = 500, y = 0, image = "images/obstacle" }  -- x, y 為位置，y=0 表示在地面上，image 為圖片路徑
            },
            
            -- 可互動物件（石頭）
            stones = {
                { x = 200, y = -5, target_id = "target1", image = "images/stone.png" },  -- x, y 為初始位置，y=0 表示在地面上，target_id 指定要放到哪個目標
                { x = 410, y = -5, target_id = "target2", image = "images/stone.png" },  -- x, y 為初始位置，y=0 表示在地面上，target_id 指定要放到哪個目標

            },
            
            -- 任務敵人（y=0 表示在地面上，負值表示地面上方）
            enemies = {
--                { type = "BASIC_ENEMY", x = 300, y = 0 },
            },
            
            -- 石頭目標物件（用於 DELIVER_STONE 目標）
            delivery_targets = {
                { id = "target1", x = 350, y = 0, image = "images/target_box" },  -- id 用於匹配石頭的 target_id，image 為顯示圖片
                { id = "target2", x = 600, y = 90, image = "images/target_box" }  -- id 用於匹配石頭的 target_id，image 為顯示圖片

            }
        },
        
        -- 任務獎勵（資源）
        reward_steel = 30,
        reward_copper = 20,
        reward_rubber = 15
    },
    ["M003"] = {
        id = "M003", 
        name = "Dangerous Delivery", 
        category = "DELIVER_STONE", 
        description = "Deliver the stone to the target zone.",
        prerequisite = "M002",  -- 需要完成 M002 才會顯示
        time_limit = 99,  -- 無時間限制
        
        -- 關卡目標
        objective = {
            type = "DELIVER_STONE",
            description = "Deliver the stone to the target zone"
        },
        
        -- 關卡場景設定
        scene = {
            width = 1200, 
            ground_y = 220, 
            -- 背景層設定應為純陣列，不含其他欄位
            backgrounds = {
                { layer = 0, x = 30, y = 65, image = "images/bg_building4.png" },
                { layer = 0, x = 300, y = 35, image = "images/bg_building2.png" },
                { layer = 1, x = 180, y = 75, image = "images/bg_building1.png" },
                { layer = 0, x = 500, y = 55, image = "images/bg_building4.png" },
                { layer = 1, x = 700, y = 65, image = "images/bg_building3.png"}
            },

            -- 測試對話（任務開始前顯示）：上方圖片 + 下方打字機文字
            dialog = {
                image = "images/dialog_bg",
                lines = {
                    "Thank you, Pilot, but the world is still in danger.",
                    "More stones, more enemies. We cannot live in peace yet.",
                    "Take stones to the targets.",
                    
                }
            },
            
            -- 地形配置（全平坦用於測試）
            terrain = {
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 }
            },
            
            obstacles = {},

            -- 可互動物件（石頭）
            stones = {
                { x = 200, y = -5, target_id = "target1", image = "images/stone.png" },  -- x, y 為初始位置，y=0 表示在地面上，target_id 指定要放到哪個目標
                { x = 510, y = -5, target_id = "target2", image = "images/stone.png" },  -- x, y 為初始位置，y=0 表示在地面上，target_id 指定要放到哪個目標

            },


            
            -- 測試所有敵人類型（y=0 表示在地面上，負值表示地面上方）
            enemies = {

--                { type = "JUMP_ENEMY", x = 450, y = 0 },       -- 跳躍敵人
--                { type = "SWORD_ENEMY", x = 650, y = 0 },      -- 劍敵人
                { type = "BASIC_ENEMY", x = 380, y = 0 },
                { type = "MINE", x = 250, y = 0 },             -- 地雷1
                { type = "MINE", x = 550, y = 0 },             -- 地雷2
                { type = "BASIC_ENEMY", x = 780, y = 0 },      
            },
            
            -- 石頭目標物件（用於 DELIVER_STONE 目標）
            delivery_targets = {
                { id = "target1", x = 350, y = 0, image = "images/target_box" },  -- id 用於匹配石頭的 target_id，image 為顯示圖片
                { id = "target2", x = 900, y = 0, image = "images/target_box" }  -- id 用於匹配石頭的 target_id，image 為顯示圖片

            },
        
        -- 任務獎勵（資源）
        reward_steel = 0,
        reward_copper = 40,
        reward_rubber = 25
    },

     
    },
    ["M004"] = {
        id = "M004", 
        name = "MORE ENEMIES", 
        category = "ELIMINATION", 
        description = "Eliminate all enemies.",
        prerequisite = "M002",  -- 需要完成 M002 才會顯示
        time_limit = -1,  -- 無時間限制
        
        -- 關卡目標
        objective = {
            type = "ELIMINATE_ALL",
            description = "Eliminate all enemies"
        },
        
        -- 關卡場景設定
        scene = {
            width = 1200, 
            ground_y = 220, 
            -- 背景層設定應為純陣列，不含其他欄位
            backgrounds = {
                { layer = 0, x = 30, y = 65, image = "images/bg_building4.png" },
                { layer = 0, x = 300, y = 35, image = "images/bg_building2.png" },
                { layer = 1, x = 180, y = 75, image = "images/bg_building1.png" },
                { layer = 0, x = 500, y = 55, image = "images/bg_building4.png" },
                { layer = 1, x = 700, y = 65, image = "images/bg_building3.png"}
            },

            -- 測試對話（任務開始前顯示）：上方圖片 + 下方打字機文字
            dialog = {
                image = "images/dialog_bg",
                lines = {
                    "Thank you, Pilot, now we will move to farther land to build our base.",
                    "More enemies out there trying to stop us.",
                    "Clear the area to ensure safe passage.",
                    
                }
            },
            
            -- 地形配置（全平坦用於測試）
            terrain = {
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "up15", height_offset = 0 },     -- 從 height_offset=0 往上爬到17
                { type = "flat", height_offset = -17 },   -- 接續上一段的結束高度
                { type = "flat", height_offset = -17 },
                { type = "flat", height_offset = -17 },
                { type = "down15", height_offset = -17 }, -- 從 -17 往下降到17
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 }
            },
            
            obstacles = {},

            -- 可互動物件（石頭）


            
            -- 測試所有敵人類型（y=0 表示在地面上，負值表示地面上方）
            enemies = {

                { type = "JUMP_ENEMY", x = 250, y = 0 },       -- 跳躍敵人
                { type = "BASIC_ENEMY", x = 320, y = 0 },
                { type = "SWORD_ENEMY", x = 380, y = -17 },
                { type = "BASIC_ENEMY", x = 450, y = -17 },            
                { type = "BASIC_ENEMY", x = 650, y = 0 },             
                { type = "BASIC_ENEMY", x = 780, y = 0 },
                { type = "SWORD_ENEMY", x = 950, y = 0 },      -- 劍敵人
            },
            
            -- 石頭目標物件（用於 DELIVER_STONE 目標）

        
        -- 任務獎勵（資源）
        reward_steel = 60,
        reward_copper = 10,
        reward_rubber = 5
    },

     
    },


    ["M005"] = {
        id = "M005", 
        name = "Brave Delivery", 
        category = "DELIVER_STONE", 
        description = "Deliver the stone to the target zone.",
        prerequisite = "M003",  -- 需要完成 M003 才會顯示
        time_limit = -1,  -- 無時間限制
        
        -- 關卡目標
        objective = {
            type = "DELIVER_STONE",
            description = "Deliver the stone to the target zone"
        },
        
        -- 關卡場景設定
        scene = {
            width = 1600, 
            ground_y = 220, 
            -- 背景層設定應為純陣列，不含其他欄位
            backgrounds = {
                { layer = 0, x = 30, y = 65, image = "images/bg_building4.png" },
                { layer = 1, x = 270, y = 35, image = "images/bg_building3.png" },
                { layer = 1, x = 380, y = 75, image = "images/bg_building2.png" },
                { layer = 0, x = 560, y = 55, image = "images/bg_building4.png" },
                { layer = 1, x = 800, y = 65, image = "images/bg_building1.png"},
                { layer = 0, x = 960, y = 55, image = "images/bg_building4.png" },
            },

            -- 測試對話（任務開始前顯示）：上方圖片 + 下方打字機文字
            dialog = {
                image = "images/dialog_bg",
                lines = {
                    "Thank you, Pilot, you save our civilization.",
                    "More stones, more enemies. We cannot live in peace yet.",
                    "Take stones to the targets.",
                    
                }
            },
            
            -- 地形配置（全平坦用於測試）
            terrain = {
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "up15", height_offset = 0 },     -- 從 height_offset=0 往上爬到17
                { type = "flat", height_offset = -17 },   -- 接續上一段的結束高度
                { type = "flat", height_offset = -17 },
                { type = "flat", height_offset = -17 },
                { type = "down15", height_offset = -17 }, -- 從 -17 往下降到17
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "up15", height_offset = 0 },     -- 從 height_offset=0 往上爬到17
                { type = "flat", height_offset = -17 },   -- 接續上一段的結束高度
                { type = "flat", height_offset = -17 },
                { type = "flat", height_offset = -17 },
                { type = "down15", height_offset = -17 }, -- 從 -17 往下降到17
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 }
            },
            
            obstacles = {},

            -- 可互動物件（石頭）
            stones = {
                { x = 200, y = -5, target_id = "target1", image = "images/stone.png" },  -- x, y 為初始位置，y=0 表示在地面上，target_id 指定要放到哪個目標
                { x = 720, y = -5, target_id = "target2", image = "images/stone.png" },  -- x, y 為初始位置，y=0 表示在地面上，target_id 指定要放到哪個目標

            },


            
            -- 測試所有敵人類型（y=0 表示在地面上，負值表示地面上方）
            enemies = {

--                { type = "JUMP_ENEMY", x = 450, y = 0 },       -- 跳躍敵人
--                { type = "SWORD_ENEMY", x = 650, y = 0 },      -- 劍敵人
                { type = "BASIC_ENEMY", x = 380, y = 0 },
                { type = "MINE", x = 250, y = 0 },             -- 地雷1
                { type = "MINE", x = 550, y = 0 },             -- 地雷2
                { type = "BASIC_ENEMY", x = 980, y = 0 },      
            },
            
            -- 石頭目標物件（用於 DELIVER_STONE 目標）
            delivery_targets = {
                { id = "target1", x = 450, y = 0, image = "images/target_box" },  -- id 用於匹配石頭的 target_id，image 為顯示圖片
                { id = "target2", x = 1200, y = 0, image = "images/target_box" }  -- id 用於匹配石頭的 target_id，image 為顯示圖片

            },
        
        -- 任務獎勵（資源）
        reward_steel = 30,
        reward_copper = 10,
        reward_rubber = 55
    },

     
    },
    ["M006"] = {
        id = "M006", 
        name = "MORE ENEMIES", 
        category = "ELIMINATION", 
        description = "Eliminate all enemies.",
        prerequisite = "M004",  -- 需要完成 M004 才會顯示
        time_limit = -1,  -- 無時間限制
        
        -- 關卡目標
        objective = {
            type = "ELIMINATE_ALL",
            description = "Eliminate all enemies"
        },
        
        -- 關卡場景設定
        scene = {
            width = 1200, 
            ground_y = 220, 
            -- 背景層設定應為純陣列，不含其他欄位
            backgrounds = {
                { layer = 0, x = 30, y = 65, image = "images/bg_building4.png" },
                { layer = 0, x = 300, y = 35, image = "images/bg_building2.png" },
                { layer = 1, x = 180, y = 75, image = "images/bg_building1.png" },
                { layer = 0, x = 500, y = 55, image = "images/bg_building4.png" },
                { layer = 1, x = 700, y = 65, image = "images/bg_building3.png"}
            },

            -- 測試對話（任務開始前顯示）：上方圖片 + 下方打字機文字
            dialog = {
                image = "images/dialog_bg",
                lines = {
                    "It's the final battle, Pilot.",
                    "Evil forces are gathering to stop us.",
                    "We will succeed, we trust in you.",
                    
                }
            },
            
            -- 地形配置（全平坦用於測試）
            terrain = {
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 },
                { type = "flat", height_offset = 0 }
            },
            
            obstacles = {},

            -- 可互動物件（石頭）


            
            -- 測試所有敵人類型（y=0 表示在地面上，負值表示地面上方）
            enemies = {

                { type = "JUMP_ENEMY", x = 250, y = 0 },       -- 跳躍敵人
                { type = "BASIC_ENEMY", x = 320, y = 0 },
                { type = "SWORD_ENEMY", x = 380, y = 0 },
                { type = "BASIC_ENEMY", x = 550, y = 0 },            
                { type = "BASIC_ENEMY", x = 750, y = 0 },
                { type = "MINE", x = 800, y = 0 },             -- 地雷2
                { type = "BASIC_ENEMY", x = 880, y = 0 },
                { type = "SWORD_ENEMY", x = 1050, y = 0 },      -- 劍敵人
            },
            
            -- 石頭目標物件（用於 DELIVER_STONE 目標）

        
        -- 任務獎勵（資源）
        reward_steel = 10,
        reward_copper = 60,
        reward_rubber = 35
    },

     
    },





}

return missions