-- boss_data.lua
-- [[ S6 BOSS ]] BOSS 註冊表（5 隻 roster 的家）。BOSS = 核心 + 依序外掛的可破壞武器零件。
-- 每個階段只露出一個零件當弱點，打爆進下一階段；最後一個 reveal="internal" 的內部武器顯現。
-- dx/dy = 相對核心本體左上角的偏移；attack 各零件不同（越後越強）；hp 為該零件（該階段）血量。

local bosses = {
    ["BOSS1"] = {
        name = "ASSEMBLY CORE",
        body_w = 56, body_h = 64,
        move_speed = 16,      -- ≈ 一般敵人
        move_range = 90,      -- 以出生點為中心左右巡邏
        trans_time = 1.0,     -- 階段轉場無敵秒數（閃爍、不攻擊、免傷）
        parts = {
            -- 階段1：基本武器（手臂機槍，單發）
            { id = "ARM", label = "ARM", hp = 40, dx = -6, dy = 10, w = 26, h = 26, reveal = "outer",
              attack = { type = "VOLLEY", n = 1, cooldown = 2.0, damage = 5, speed_mult = 1.0 } },
            -- 階段2：較強武器（散射砲）
            { id = "CANNON", label = "CANNON", hp = 60, dx = 36, dy = 8, w = 30, h = 22, reveal = "outer",
              attack = { type = "VOLLEY", n = 3, spread = true, cooldown = 1.8, damage = 8, speed_mult = 1.1 } },
            -- 階段3：內部武器（前兩階段隱藏，最後顯現，最強）
            { id = "CORE", label = "CORE", hp = 80, dx = 14, dy = 22, w = 28, h = 28, reveal = "internal",
              attack = { type = "VOLLEY", n = 5, spread = true, cooldown = 1.2, damage = 10, speed_mult = 1.2 } },
        },
    },
}

return bosses