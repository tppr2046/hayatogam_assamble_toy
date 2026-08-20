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
        -- [[ §8.08 ]] 資源掉落：**只掉一點**。BOSS 的報酬主要來自首過關獎勵與核心，
        -- 掉太多會讓「重打 BOSS 關」變成最佳刷法，蓋過首過關獎勵的推進動力。
        drop = { steel = {5, 8}, copper = {5, 8}, rubber = {5, 8} },
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

    -- ======================================================================
    -- [[ §15.5a 巨大 BOSS ]] 2026-08-19　**平行零件制**（part_mode = "PARALLEL"）
    -- ----------------------------------------------------------------------
    -- ★ 與 OVERSEER 的模型完全不同：頭與雙臂**同時活著**，各有 HP。
    --   頭 ＝ BOSS 本體（hp／命中框／死亡都走既有管線）；手臂 ＝ 代理實體。
    --   實作在 entity_boss_parallel.lua，那裡的檔頭有完整說明。
    -- ★ **只有打爆頭才算擊倒**。手臂是選擇：拆掉少一種攻擊，但雙臂全爆 → 頭部狂暴。
    --
    -- ⚠️ 美術尚未製作，**現在全部是程式繪製佔位**（白底黑框＋黑色頭＋白眼）。
    --   放圖即自動生效：`sprite` 給本體與頭的 imagetable、`arms.sprite` 給手臂
    --   （左右共用一套，右臂自動水平鏡射 —— §15.5a-7 的主要省圖點）。
    --
    -- 版面：遊戲可視高度只有 176px（240 − UI 64），地面線在 ground_y − 64。
    --   ground_y = 220 的場景 → 地面在 156 → 本體高 150 剛好「上半身佔滿畫面」。
    --   ★ 「只露上半身」在這裡不是靠裁切，而是**本體底邊就停在地面線**。
    -- ======================================================================
    ["BOSS2"] = {
        name = "COLOSSUS",              -- ⚠️ 血條標題寬度上限見 BOSS1 的註解
        part_mode = "PARALLEL",
        drop = { steel = {5, 8}, copper = {5, 8}, rubber = {5, 8} },
        -- ★ 路徑先指好：檔案不存在時載入會失敗（pcall）→ 自動走程式繪製佔位，
        --   把圖放進 Source/images/ 重新編譯就生效，不必回來改資料。
        sprite = "images/boss2",        -- boss2-table-130-150.png，3 格（本體／頭／頭-開火）
        body_w = 130, body_h = 150,
        cell_body = 1,
        move_speed = 0,                 -- ★ 固定不動（§15.5a-4 拍板）；戰場鎖定靠 scene.arena
        move_range = 0,
        trans_time = 0,

        -- 頭：弱點，也是 BOSS 本體的 hp
        head = {
            label = "HEAD",
            hp = 140,
            dx = 46, dy = 0, w = 40, h = 34,
            muzzle_x = 46, muzzle_y = 22,     -- 朝左射出
            cell = 2, cell_fire = 3,          -- 有圖時：平常／開火下探
            -- ★★ 下探是這隻 BOSS 的關鍵設計（§15.5a-3）：
            --   既是「要開火了」的預告，也是**水平槍唯一打得到頭的窗口**。
            --   只帶 GUN 的配裝就靠這個窗口，才談得上「不限制零件」。
            lower_dy = 26,
            attack = { type = "VOLLEY", n = 1, cooldown = 2.6, telegraph = 0.9,
                       strike_time = 0.15, recover = 0.5,
                       damage = 6, speed_mult = 30, grav_mult = 18 },
            -- 雙臂全爆後的狂暴（§15.5a-2：「全拆」要有代價）
            rage = { cooldown_mult = 0.5, n = 2 },
        },

        -- 雙臂：可個別打爆，**不是**過關條件
        arms = {
            hp = 90,
            sprite = "images/boss2_arm",  -- boss2_arm-table-30-100.png，2 格（待機／舉起）
                                          -- ★ 左右共用一套，右臂由程式水平鏡射
            w = 30, h = 100,
            mounts = {
                { id = "ARM_L", label = "L-ARM", dx = 2,  dy = 40, mirror = false },
                { id = "ARM_R", label = "R-ARM", dx = 98, dy = 40, mirror = true  },
            },
            -- 兩種攻擊**輪替**（打完換下一種），不是隨機 —— 玩家要學得起來節奏。
            attacks = {
                -- 拳擊地面：★ 不改變地形（§15.5a-5）。只有落點周圍的震波傷害。
                -- ★ 2026-08-19：舉在上方時**左右追著玩家移動**，停下來後才砸。
                --   track_range＝約一個本體寬（130）→ 玩家跑出這個範圍就打不到，
                --   「走位」因此是有效的解法；無限追蹤等於必中，那就沒得玩了。
                --   warn＝追蹤停止後的發招預告（地面落點閃爍）＝玩家的反應窗口。
                { type = "SLAM", cooldown = 3.2, telegraph = 0.9, raise = 28,
                  track = true, track_range = 130, track_speed = 95, warn = 0.35,
                  strike_time = 0.12, follow_through = 14, recover = 0.6,
                  -- ★ 傷害範圍＝**手臂寬度再加一點點**（半徑 = w/2 + radius_pad = 15+8 = 23）。
                  --   刻意做窄：範圍太大的話「拳頭追著你移動」就沒有意義了，
                  --   站哪裡都一樣被打到，追蹤與預告兩段演出就白做了。
                  --   要改成明確數值就直接寫 radius（會覆蓋這個計算）。
                  damage = 10, radius_pad = 8 },
                -- 投擲石頭：owner="BOSS" → 飛行中只傷玩家；落地後轉中性＝玩家的彈藥
                -- ★ 2026-08-19：改成**算彈道丟到玩家身上**（舊版固定速度，一律落在玩家前方）。
                --   speed_max 越大＝飛得越平越快；min/max_frames 夾住飛行時間。
                { type = "THROW", cooldown = 4.2, telegraph = 0.7, raise = 24,
                  strike_time = 0.12, follow_through = 8, recover = 0.5,
                  -- ★ despawn＝**臨時石頭**：落地 3 秒後消失（2026-08-19 拍板）。
                  --   撿了要馬上用，不能囤一地 —— BOSS 供應的彈藥是有時限的。
                  --   抓在爪子上不倒數；打中 BOSS 就沒了；沒打中落地後重新計時。
                  damage = 12, speed_max = 9, min_frames = 22, max_frames = 55, spread = 0.6,
                  despawn = 3.0 },
            },
        },
    },

    -- ======================================================================
    -- [[ §15.5b 高速飛行 BOSS ]] 2026-08-19　`move_mode = "FLIGHT"`
    -- ----------------------------------------------------------------------
    -- ★★ 結構是**序列制**（與 OVERSEER 同一套 parts / boss_phase），
    --   本隻只多一套「移動與出招的狀態機」（entity_boss_flight.lua）。
    -- ★★ 「快」的感覺來自 `scene.sky_scroll`（天空自動捲動），**不是**它自己的移動速度 ——
    --   它若真的飛很快，玩家武器裡只有追蹤飛彈打得到，就變成「不裝飛彈過不了」。
    -- ★ 硬直（RECOVER）是核心節奏：每次出手完停在**畫面內**、可被打。
    --   窗口長度依階段縮短 1.5 → 1.1 → 0.8，難度曲線就在這三個數字上。
    --   ⚠️ 1.0 秒是門檻：GUN 冷卻 1.0 且**現在是手動**，窗口低於它＝手動槍一發都打不到。
    -- ⚠️ 美術未做 → 走既有的程式繪製佔位（白底黑框 + 弱點方塊）。
    -- ======================================================================
    ["BOSS3"] = {
        name = "COMET",                 -- ⚠️ 血條標題寬度上限見 BOSS1 的註解
        move_mode = "FLIGHT",
        drop = { steel = {5, 8}, copper = {5, 8}, rubber = {5, 8} },
        -- ★ 同 BOSS2：路徑先指好，放圖即生效。
        --   boss3-table-64-40.png，4 格（本體／ENGINE／PODS／CORE），
        --   ★ 每格都是整張 64×40 的畫布、只畫該部位、其餘透明（與 boss1 同慣例）
        sprite = "images/boss3",
        body_w = 64, body_h = 40,
        cell_body = 1,
        move_speed = 0, move_range = 0, -- 不走 bossMove（巡邏），由飛行狀態機接管
        trans_time = 1.0,
        flight = {
            cruise_speed   = 70,        -- ★ 螢幕上的速度：刻意慢到瞄得準
            bob_amp = 10, bob_speed = 1.6,
            margin = 30, base_y = 34,
            exit_speed = 260,
            offscreen_time = 1.0,       -- 空白期（拍板 0.8~1.2）
            warn_before = 0.5,          -- 入畫預告箭頭提前多久
            dash_speed = 300,
            dash_damage = 8, dash_push = 44,
            spawn_type = "DRONE",
            spawn_max = 3,              -- ⚠️ 上限：沒有的話玩家不清就滾雪球
        },
        parts = {
            -- 階段 1：引擎。只有掠過投彈，窗口最寬 —— 教玩家這場戰鬥的節奏。
            { id = "ENGINE", label = "ENGINE", hp = 55, cell = 2,
              dx = 44, dy = 8, w = 20, h = 18, muzzle_x = 30, muzzle_y = 30,
              reveal = "outer",
              flight_phase = { attacks = { "BOMB" }, cruise_time = 2.0,
                               telegraph = 0.6, recover = 1.5 },
              attack = { damage = 6, speed_mult = 24, bomb_grav_mult = 14, bomb_n = 2 } },

            -- 階段 2：武器莢艙。加入俯衝（出畫 → 衝回來）與定點齊射。
            { id = "PODS", label = "PODS", hp = 70, cell = 3,
              dx = 8, dy = 22, w = 34, h = 14, muzzle_x = 20, muzzle_y = 32,
              reveal = "outer",
              flight_phase = { attacks = { "DASH", "VOLLEY" }, cruise_time = 1.7,
                               telegraph = 0.5, recover = 1.1 },
              attack = { damage = 7, speed_mult = 30, grav_mult = 12, n = 3 } },

            -- 階段 3：核心。全招式 + 放小兵，窗口最短。
            { id = "CORE", label = "CORE", hp = 85, cell = 4,
              dx = 24, dy = 12, w = 22, h = 20, muzzle_x = 28, muzzle_y = 30,
              reveal = "internal",
              flight_phase = { attacks = { "BOMB", "DASH", "VOLLEY", "SPAWN" },
                               cruise_time = 1.4, telegraph = 0.4, recover = 0.8 },
              attack = { damage = 8, speed_mult = 32, grav_mult = 12, n = 3,
                         bomb_grav_mult = 16, bomb_n = 3 } },
        },
    },
}

return bosses
