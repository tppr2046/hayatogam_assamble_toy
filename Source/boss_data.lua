-- boss_data.lua
-- [[ S6 BOSS ]] BOSS 註冊表（5 隻 roster 的家）。BOSS = 核心 + 依序外掛的可破壞武器零件。
-- 每個階段只露出一個零件當弱點，打爆進下一階段；最後一個 reveal="internal" 的內部武器顯現。
--
-- 美術：sprite 為 72x72 的 imagetable（各格「原位對齊」＝同一個 72x72 座標系）。
-- ★ 2026-08-11 改版：由 7 格改成 **6 格**，原本的「後輪／前輪」兩格合併為一條**履帶**。
-- 由左至右：
--   1 本體 / 2 管子(上下移動；最終階段隱藏) / 3 履帶 /
--   4 槍(階段1) / 5 canon(階段2) / 6 雷射槍(僅最終階段顯示)
-- ★ 顯示雷射槍時**本體要隱藏**（`hide_body_on_final`）—— 畫面剩「履帶＋雷射槍」。
-- dx/dy/w/h＝該零件在 72x72 內的實際圖形範圍（＝弱點命中框，與畫面一致）。
-- muzzle_x/muzzle_y＝槍口在 72x72 內的座標（子彈與雷射由此射出）。
-- ★ 以下座標全部量自新圖的像素（bbox 與圓心），不是估的；換圖後要重量一次。

local bosses = {
    ["BOSS1"] = {
        -- [[ 版面 ]] 血條標題＝「name  [label  n/3]」，總寬必須 ≤ 血條 220px。
        -- ★ 2026-08-11 重量：最長標籤已變成 CANON(5字) → 後綴 135px，所以 name 上限剩 85px。
        --   OVERSEER = 76px，只剩 9px 餘裕。
        --   ⚠️ 標籤不能寫成 "CANNON"（雙 N）—— 實測整行 221px，**超出 1px 就折行**。
        --   改名或改標籤前先量寬度（量法見 HANDOFF §5-4 的字寬腳本）。
        name = "OVERSEER",
        sprite = "images/boss1",     -- imagetable：boss1-table-72-72.png
        body_w = 72, body_h = 72,
        -- sprite 各格索引（1-based）。武器的格號寫在下面各 part 的 `cell`，
        -- 這裡**不要**再重複列一份（舊版有 cell_weapon1/2/laser 但程式從來沒讀，
        -- 留著只會與 parts[].cell 不同步）。
        cell_body = 1, cell_pipe = 2, cell_track = 3,
        -- ★ 履帶是整條 72×16（量得 bbox y=56~72），**不旋轉**，直接原位貼上。
        --   舊版是兩顆小輪各自 drawRotated，換圖後已移除。
        hide_body_on_final = true,    -- 最終階段（雷射槍）隱藏本體，只留履帶＋雷射槍
        pipe_vibrate = -2,            -- 管子上下移動幅度（px）；負值＝相位相反
        move_speed = 16,             -- ≈ 一般敵人
        move_range = 90,             -- 以出生點為中心左右巡邏
        trans_time = 1.0,            -- 階段轉場無敵秒數（閃爍、不攻擊、免傷）
        parts = {
            -- speed_mult / grav_mult 與一般敵人同尺度（敵人為 25~35 / 15~20）。
            -- 階段1：槍（第 4 格，雙管、朝左）單發
            -- aim=true：武器會旋轉瞄準玩家（繞 pivot 轉；圖的靜止方向為朝左）
            -- 量測：bbox (25,34)-(58,48)；上砲管內徑中心 y=39、管口在左緣 x=25 → muzzle (25,39)
            --       pivot 取右側機匣的掛載中心 (52,41)（與舊版慣例一致：軸心在靠機體那端）
            { id = "GUN", label = "GUN", hp = 40, cell = 4,
              dx = 25, dy = 34, w = 33, h = 14, muzzle_x = 25, muzzle_y = 39,
              aim = true, pivot_x = 52, pivot_y = 41, reveal = "outer",
              -- aim_time：發射前先轉動瞄準的秒數；aim_speed：轉動角速度（度/秒）
              attack = { type = "VOLLEY", n = 1, cooldown = 2.0, aim_time = 1.2, aim_speed = 60,
                         damage = 5, speed_mult = 30, grav_mult = 18 } },
            -- 階段2：canon（第 5 格，朝左）散射
            -- 量測：bbox (5,28)-(33,47)；砲管左端 x=5、管身中心 y=37 → muzzle (5,37)
            --       pivot 取後方線圈狀機構的圓心 (26,37)
            { id = "CANON", label = "CANON", hp = 60, cell = 5,
              dx = 5, dy = 28, w = 28, h = 19, muzzle_x = 5, muzzle_y = 37,
              aim = true, pivot_x = 26, pivot_y = 37, reveal = "outer",
              attack = { type = "VOLLEY", n = 3, spread = true, cooldown = 1.8, aim_time = 0.8, aim_speed = 60,
                         damage = 8, speed_mult = 33, grav_mult = 18 } },
            -- 階段3：核心雷射槍（前兩階段隱藏；此時**本體與管子都隱藏**、雷射槍顯現）
            -- LASER 流程：charge 充能預告（細線警告）→ beam 開火（粗光束，一次只扣一次）→ cooldown。
            -- mirror_when_right：玩家在右側時整把雷射槍水平鏡射（履帶不鏡射）
            -- 量測：bbox (16,38)-(53,56)（含下方支架）；槍口在左緣 x=16、管身中心 y=45 → muzzle (16,45)
            { id = "CORE", label = "CORE", hp = 80, cell = 6,
              dx = 16, dy = 38, w = 37, h = 18, muzzle_x = 16, muzzle_y = 45,
              mirror_when_right = true, reveal = "internal",
              attack = { type = "LASER", charge = 0.9, beam_time = 0.4, cooldown = 1.6,
                         damage = 5, thickness = 5 } },
        },
    },
}

return bosses
