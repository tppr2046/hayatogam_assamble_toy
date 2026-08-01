-- boss_data.lua
-- [[ S6 BOSS ]] BOSS 註冊表（5 隻 roster 的家）。BOSS = 核心 + 依序外掛的可破壞武器零件。
-- 每個階段只露出一個零件當弱點，打爆進下一階段；最後一個 reveal="internal" 的內部武器顯現。
--
-- 美術：sprite 為 72x72 的 imagetable（各格「原位對齊」＝同一個 72x72 座標系），
-- 由左至右：1 身體 / 2 上身(未露核心武器時顯示，會上下震動) / 3 後輪 / 4 前輪 /
-- 5 武器1 / 6 武器2 / 7 核心雷射槍(僅最終階段顯示)。
-- dx/dy/w/h＝該零件在 72x72 內的實際圖形範圍（＝弱點命中框，與畫面一致）。
-- muzzle_x/muzzle_y＝槍口在 72x72 內的座標（子彈與雷射由此射出）。

local bosses = {
    ["BOSS1"] = {
        name = "ASSEMBLY CORE",
        sprite = "images/boss1",     -- imagetable：boss1-table-72-72.png
        body_w = 72, body_h = 72,
        -- sprite 各格索引（1-based）
        cell_body = 1, cell_upper = 2, cell_wheel_rear = 3, cell_wheel_front = 4,
        cell_weapon1 = 5, cell_weapon2 = 6, cell_laser = 7,
        -- 輪子旋轉中心（72x72 內座標）
        wheel_rear  = { cx = 48,   cy = 63,   r = 9 },
        wheel_front = { cx = 17.5, cy = 68.5, r = 4 },
        upper_vibrate = -2,           -- 上身上下震動幅度（px）
        move_speed = 16,             -- ≈ 一般敵人
        move_range = 90,             -- 以出生點為中心左右巡邏
        trans_time = 1.0,            -- 階段轉場無敵秒數（閃爍、不攻擊、免傷）
        parts = {
            -- speed_mult / grav_mult 與一般敵人同尺度（敵人為 25~35 / 15~20）。
            -- 階段1：武器1（單發）
            -- aim=true：武器會旋轉瞄準玩家（繞 pivot 轉；圖的靜止方向為朝左）
            { id = "ARM", label = "ARM", hp = 40, cell = 5,
              dx = 0, dy = 28, w = 31, h = 17, muzzle_x = 0, muzzle_y = 36,
              aim = true, pivot_x = 22, pivot_y = 36, reveal = "outer",
              -- aim_time：發射前先轉動瞄準的秒數；aim_speed：轉動角速度（度/秒）
              attack = { type = "VOLLEY", n = 1, cooldown = 2.0, aim_time = 1.2, aim_speed = 60,
                         damage = 5, speed_mult = 30, grav_mult = 18 } },
            -- 階段2：武器2（散射）
            { id = "CANNON", label = "CANNON", hp = 60, cell = 6,
              dx = 32, dy = 25, w = 30, h = 15, muzzle_x = 32, muzzle_y = 32,
              aim = true, pivot_x = 55, pivot_y = 32, reveal = "outer",
              attack = { type = "VOLLEY", n = 3, spread = true, cooldown = 1.8, aim_time = 0.8, aim_speed = 60,
                         damage = 8, speed_mult = 33, grav_mult = 18 } },
            -- 階段3：核心雷射槍（前兩階段隱藏；此時上身隱藏、雷射槍顯現）
            -- LASER 流程：charge 充能預告（細線警告）→ beam 開火（粗光束，一次只扣一次）→ cooldown。
            -- mirror_when_right：玩家在右側時整把雷射槍水平鏡射（本體不鏡射）
            { id = "CORE", label = "CORE", hp = 80, cell = 7,
              dx = 4, dy = 16, w = 44, h = 19, muzzle_x = 4, muzzle_y = 30,
              mirror_when_right = true, reveal = "internal",
              attack = { type = "LASER", charge = 0.9, beam_time = 0.4, cooldown = 1.6,
                         damage = 5, thickness = 5 } },
        },
    },
}

return bosses
