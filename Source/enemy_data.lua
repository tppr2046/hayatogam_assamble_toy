-- enemy_data.lua
-- 導出所有敵人類型的詳細屬性 (已移除中文字符)

return {
    ["BASIC_ENEMY"] = {
        -- [[ §8.08 ]] 資源掉落：型別固定、數量小範圍隨機（射擊類＝銅）
        drop = { copper = {1, 2} },
        name = "BASIC TRAINER UNIT", hp = 20, attack = 5, 
        -- [[ 2026-08-20 ]] 由 "MOVE FORWARD/BACK"（持續移動）改為 **"MOVE_PAUSE"（走走停停）**。
        -- ★ 原因：新圖 enemy1 的第 1 格是**待機**，但舊的移動型別從來不會停下來
        --   （只是每 2 秒可能換方向），實測待機格一次都不會出現。
        -- ⚠️ 這會改變 **M001–M008 所有既有關卡**的敵人節奏 —— 使用者拍板要改。
        -- ★ **刻意不設 `fire_only_when_stopped`** —— 那是 WALKER 的特性。
        --   BASIC 的開火行為維持原樣，只有「移動」變成有停頓，戰鬥難度不受影響。
        move_type = "MOVE_PAUSE", attack_type = "FIRE BULLET",
        -- 移動參數
        move_duration = 2.0,     -- 走這麼久（比 WALKER 的 1.6 長 → 仍以移動為主，節奏接近原本）
        pause_duration = 1.0,    -- 停這麼久（待機格就是在這段時間出現）
        walk_fps = 8,            -- 移動中的換幀速度（目前只有 2 格，多格圖時才看得出差別）
        -- ★ MOVE_PAUSE 不讀 move_probability，保留給改回 MOVE FORWARD/BACK 時用
        move_probability = 0.7,
        move_range = 100,        -- 移動範圍（像素）
        move_speed = 20,         -- 移動速度
        -- 砲彈屬性 multiplier：水平速度相對於玩家移動速度、以及重力的倍率
        projectile_speed_mult = 30, -- 30 = 水平速度接近玩家感覺
        projectile_grav_mult = 20,  -- 20 = 重力感接近玩家
        -- 敵人圖片
        -- [[ 2026-08-20 換圖 ]] 由單張 enemy01.png 改為 **enemy1-table-38-32.png（2 格）**。
        -- 第 1 格＝待機、第 2 格＝移動。
        -- ★ 換幀由 **MOVE_PAUSE 自己的走路動畫**負責（停下＝第 1 格、移動＝第 2 格起），
        --   所以這裡**不設** `anim_idle_move` —— 兩邊都寫 self.image 就會變成兩個計算點。
        -- ★ 也不要設 `anim_fps`（那是無條件循環，會讓它站著也在走路）。
        image = "images/enemy1",
        -- 子彈發射位置（相對於敵人左上角的偏移，x, y）
        bullet_offset_x = 4,  -- 從敵人中心發射
        bullet_offset_y = 6   -- 從敵人中間高度發射
    },
    
    ["HEAVY_ENEMY"] = {
        -- [[ §8.08 ]] 資源掉落：型別固定、數量小範圍隨機（最硬＝最值錢）
        drop = { steel = {4, 6} },
        name = "HEAVY ARMOR UNIT", hp = 80, attack = 10, 
        move_type = "IMMOBILE", attack_type = "SWING ATTACK",
        -- 敵人圖片
        image = "images/enemy2",
        -- 子彈發射位置
        bullet_offset_x = 4,
        bullet_offset_y = 6
    },
    
    ["JUMP_ENEMY"] = {
        -- [[ §8.08 ]] 資源掉落：型別固定、數量小範圍隨機（彈跳＝橡膠）
        drop = { rubber = {1, 2} },
        name = "JUMP UNIT", hp = 15, attack = 8,
        move_type = "JUMP", attack_type = "CONTACT",
        -- 跳躍參數
        jump_velocity = -6.0,     -- 跳躍初速度
        jump_cooldown = 2.0,      -- 跳躍間隔（秒）
        jump_horizontal = 30,     -- 水平移動速度
        -- 敵人圖片（3-frame imagetable）
        -- Frame 1: 站立, Frame 2: 跳起, Frame 3: 空中
        image = "images/enemy_jump"
    },
    
    ["SWORD_ENEMY"] = {
        -- [[ §8.08 ]] 資源掉落：型別固定、數量小範圍隨機（刀刃＝鋼）
        drop = { steel = {2, 3} },
        name = "SWORD UNIT", hp = 30, attack = 12,
        move_type = "IMMOBILE", attack_type = "SWING SWORD",
        -- 劍揮動參數
        sword_swing_cooldown = 3.0,  -- 揮動間隔（秒）
        sword_swing_speed = 180,     -- 揮動速度（度/秒）
        sword_swing_min = -180,         -- 揮動最小角度（度）
        sword_swing_max = 0,       -- 揮動最大角度（度）
        -- 劍旋轉軸心位置偏移（相對於敵人中心的偏移，x, y）
        sword_pivot_offset_x = 0,    -- 軸心 X 偏移（正值向右）
        sword_pivot_offset_y = 0,    -- 軸心 Y 偏移（正值向下）
        -- 劍圖內部旋轉軸心偏移（相對於劍圖中心的偏移，x, y）
        -- ★ 2026-08-10 量自新圖：enemy2_sword.png 48×16，握把圓環中心 (7.0, 8.0)
        --   → 相對圖中心 (24, 8) 的偏移 = (-17, 0)。舊圖圓環在 (8.0, 8.0) 故舊值為 -16。
        sword_image_pivot_offset_x = -17,  -- 劍圖軸心 X 偏移（正值向右）
        sword_image_pivot_offset_y = 0,  -- 劍圖軸心 Y 偏移（正值向下）
        -- 劍長（軸心到劍尖，像素）。★繪製端與命中判定端共用這組欄位，改一邊等於兩邊都改
        --   量自新圖：圓環中心 x=7.0 → 劍尖 x=48.0，故 41
        sword_length = 41,
        -- 敵人圖片
        image = "images/enemy2",
        -- 劍圖片（可選，若不指定則使用預設的直線繪制）
        sword_image = "images/enemy2_sword"
    },
    
    ["MINE"] = {
        -- [[ §8.08 ]] ★ 不設 drop ＝ 不掉資源。地雷是**陷阱**不是敵人，
        --   會掉的話等於在地上放免費資源。
        name = "MINE", hp = 1, attack = 20,
        move_type = "IMMOBILE", attack_type = "EXPLODE",
        -- 爆炸參數
        explode_delay = 2.0,      -- 觸發後爆炸延遲（秒）
        explode_radius = 50,      -- 爆炸範圍（像素）
        explode_damage = 20,      -- 爆炸傷害
        -- 敵人圖片（2026-08-10 由單張 mine.png 改為 mine-table-32-16.png，3 格）
        --   第 1 格 = 地雷本體（畫布下緣 y=9~15，踩在地面上），一直畫
        --   第 2/3 格 = 警示燈（畫布上緣 y=2~9），★與本體同一張 32×16 畫布，
        --   所以同座標直接疊畫就會對位，不需要額外偏移
        image = "images/mine",
        -- 觸發後的警示燈閃爍
        warn_frame_a = 2,         -- 交替的第一格
        warn_frame_b = 3,         -- 交替的第二格
        warn_blink_speed = 10     -- 每秒切換次數（越大閃越快）
    },

    ["SHIELD_ROBOT"] = {
        -- [[ §8.08 ]] 資源掉落：型別固定、數量小範圍隨機（裝甲類＝鋼）
        drop = { steel = {1, 2} },
        name = "SHIELD ROBOT", hp = 10, attack = 8,
        move_type = "SHIELD_MOVEMENT", attack_type = "SHIELD_FIRE",
        -- 盾牌參數
        shield_up_duration = 3.0,     -- 盾牌舉起時間（秒）
        shield_down_duration = 2.0,   -- 盾牌收起時間（秒）
        shield_raised = true,         -- 初始盾牌狀態（true=舉起）
        -- [[ 2026-08-12 ]] 盾牌改用專屬圖 shield.png（16×32），原本是程式畫的黑底白框。
        -- ★ 這四個值**同時是「畫在哪」與「擋子彈的判定框」**（entity_controller 的
        --   SHIELD_ROBOT 分支讀同一組），所以尺寸必須與圖一致，否則會出現
        --   「看起來擋住卻被打到」或「明明沒碰到卻被擋」。
        shield_image = "images/shield",
        shield_width = 16,            -- ＝ shield.png 寬
        shield_height = 32,           -- ＝ shield.png 高（原本 20，與新圖不符）
        shield_offset_x = -14,        -- 向左；-14 讓盾稍微疊在車體上，看起來像被持著
        shield_offset_y = 0,          -- 與敵人同底（敵人也是 32 高），盾才會站在地面線上
        -- 移動參數（盾牌收起時）
        move_speed = 25,
        move_range = 80,
        -- 砲彈屬性（盾牌收起時發射）
        projectile_speed_mult = 25,
        projectile_grav_mult = 15,
        fire_cooldown = 1.5,
        -- 敵人圖片（2026-08-07 由 enemy1 改為專屬圖 enemy02，32×32）
        image = "images/enemy02",
        bullet_offset_x = 4,
        bullet_offset_y = 6
    },

    -- [[ 2026-08-12 ]] 本切片最後一種新敵人。行為＝BASIC 的變體：
    --   **移動較快、會週期性停下，而且只在停下時開火**（移動中不攻擊）。
    ["WALKER_ENEMY"] = {
        -- [[ §8.08 ]] 資源掉落：型別固定、數量小範圍隨機（射擊類＝銅）
        drop = { copper = {1, 2} },
        name = "WALKER UNIT", hp = 18, attack = 6,
        move_type = "MOVE_PAUSE", attack_type = "FIRE BULLET",
        -- 移動／停頓的循環（秒）
        move_duration = 1.6,          -- 走這麼久
        pause_duration = 1.4,         -- 停這麼久（只有停下時會開火）
        move_speed = 55,              -- ★ 比 BASIC(20) 快很多
        move_range = 120,
        -- ★ 只在停下時開火（移動中不攻擊）
        fire_only_when_stopped = true,
        fire_cooldown = 1.0,
        projectile_speed_mult = 30,
        projectile_grav_mult = 20,
        -- 敵人圖片（3 格 40×32：第 1 格＝站立、第 2~3 格＝走路循環）
        -- ★ 走路動畫由 MOVE_PAUSE 分支自己控制，**不要設 anim_fps**
        --   （那會讓它無論停走都一直循環播放）
        image = "images/enemy04",
        walk_fps = 8,                 -- 移動中的換幀速度
        -- [[ 2026-08-13 ]] ★ 圖已由使用者改成**朝左**（正確方向），所以 `flip_x` 拿掉了。
        --   舊版是 `flip_x = true`，因為原圖朝右、要靠程式鏡射（本作敵人一律面向左）。
        --   ⚠️ **不要再加回來** —— 現在再鏡射一次會變成朝右。
        --   驗證方式：新圖與 git 舊版**逐格水平鏡射後差異 0.0%**，確認是整批鏡射過的。
        --   `flip_x` 欄位本身保留在 `entity_enemy.lua`，以後有畫反方向的敵人仍可用。
        -- 槍口：舊圖砲管末端在 (34, 7)，鏡射後 x = 40 − 34 = 6。
        -- ★ 新圖＝舊圖的鏡射版，所以**顯示結果與之前完全相同**，這個值不必改。
        bullet_offset_x = 6,
        bullet_offset_y = 7
    },

    -- [[ §15.4 隱形敵人 ]] 平時隱形（打不到），只在**短暫現身攻擊**時可被打到。
    -- ★ 裝了偵測器（§15.2）就**隨時可見可打** —— 兩者是一組,單做任一個都沒意義。
    -- ★ 現身/隱形是固定節奏,不是隨機 —— 玩家要能學會節奏、抓時機打,
    --   隨機的話就變成純運氣,那不是設計目的。
    ["STEALTH_ENEMY"] = {
        -- [[ §8.08 ]] 電子類＝銅（與 DRONE 同族）
        drop = { copper = {2, 3} },
        name = "PHANTOM", hp = 14, attack = 7,
        -- ★ 沿用 BASIC 的移動型別（"PATROL" 不是有效值，會變成完全不動）
        -- [[ 2026-08-20 ]] 跟著 BASIC 一起改成走走停停（理由見 BASIC）。
        -- ★ 停頓比 BASIC 短一點：它的隱形節奏是 3 秒隱形／1.5 秒現身，
        --   停太久會常常「現身時剛好站著不動」，看起來像卡住。
        move_type = "MOVE_PAUSE", attack_type = "FIRE BULLET",
        move_duration = 2.2,
        pause_duration = 0.8,
        walk_fps = 8,
        move_probability = 0.7,   -- ★ MOVE_PAUSE 不讀，保留給改回舊型別時用
        move_speed = 24,
        move_range = 90,
        -- 隱形節奏（秒）：隱形 3 秒 → 現身 1.5 秒（現身時才開火、才打得到）
        cloak_duration  = 3.0,
        reveal_duration = 1.5,
        projectile_speed_mult = 30,
        projectile_grav_mult = 0.2,
        fire_cooldown = 1.0,
        -- 暫時沿用 BASIC 的圖（隱形是靠「畫不畫」表現,不需要專屬圖也能測）
        -- [[ 2026-08-20 換圖 ]] 由單張 enemy01.png 改為 **enemy1-table-38-32.png（2 格）**。
        -- 第 1 格＝待機、第 2 格＝移動。換幀由 **MOVE_PAUSE 自己的走路動畫**負責，
        -- 所以**不設** `anim_idle_move`（兩邊都寫 self.image 就成了兩個計算點）。
        image = "images/enemy1",
        bullet_offset_x = 4,
        bullet_offset_y = 16
    },

    ["DRONE"] = {
        -- [[ §8.08 ]] 資源掉落：型別固定、數量小範圍隨機（電子類＝銅）
        drop = { copper = {1, 2} },
        name = "DRONE", hp = 10, attack = 6,
        move_type = "AERIAL", attack_type = "FIRE BULLET",
        -- 飛行參數
        flight_height_min = 40,       -- 最小飛行高度（像素，相對於地面向上）
        flight_height_max = 80,       -- 最大飛行高度（像素）
        flight_speed = 30,            -- 飛行速度（像素/秒）
        vertical_oscillation = 20,    -- 上下振幅（像素）
        vertical_speed = 1.5,         -- 上下運動速度（1 = 1 個單位/秒）
        -- 砲彈屬性
        projectile_speed_mult = 35,   -- 直射速度倍率
        projectile_grav_mult = 0.02,   -- 低重力（直射）
        fire_cooldown = 1.2,
        -- 敵人圖片（2026-08-09 由借用的 enemy1 換成專屬 6 幀動畫）
        image = "images/enemy_drone",
        anim_fps = 12,                -- 旋翼循環播放（6 幀 / 12fps = 0.5 秒一圈）
        -- ★ 子彈從**下方槍口**射出。座標量自 sprite（32×32）：
        --   槍管在 x=13~18、y=20~23，所以出口＝(16, 24)。換圖後重量即可。
        bullet_offset_x = 6,
        bullet_offset_y = 24
    },

    -- ======================================================================
    -- [[ §15.4 爬牆敵人 ]] 2026-08-19
    -- ----------------------------------------------------------------------
    -- ★ 貼在側面牆上、沿 `scene.walls` 的軌道**上下**移動。
    --   牆本身是**純背景圖**，軌道只是資料（不碰撞、不擋子彈）——
    --   GDD §15.3「側面牆面」那項需求因此**整個消失**，不是延後。
    -- ★ 定位是**壓制型**（使用者拍板）：持續騷擾、不致命。
    --   所以 attack 低、冷卻中等、彈道明顯可預測 —— 它負責讓玩家「不能站著不動」，
    --   不負責殺死玩家。要致命的角色已經有 SHIELD_ROBOT / BOSS 了。
    -- ⚠️ 軌道的 y_bottom 要壓夠低，它爬下來時**水平槍打得到** ——
    --   否則會變成「不裝 CANON 就過不了」，違反「零件是取捨不是鑰匙」。
    -- ⚠️ 美術未做：GDD 註明它需要**另一套朝向的圖**（玩家看到的是它的頂面）。
    --   目前沿用 DRONE 的圖當佔位（與 PHANTOM 當初的作法一致）。
    -- ======================================================================
    ["WALL_ENEMY"] = {
        -- [[ §8.08 ]] 電子類＝銅（與 DRONE 同族）
        drop = { copper = {1, 2} },
        name = "CRAWLER", hp = 12, attack = 4,   -- ★ attack 低＝壓制不致命
        move_type = "WALL", attack_type = "FIRE BULLET",
        -- 軌道參數（實際的上下界由 scene.walls 決定）
        climb_speed = 26,          -- 爬升/下降速度（px/秒）
        climb_pause_time = 0.5,    -- 爬到端點的停頓（秒）。★ 沒有停頓會像鐘擺，不像生物
        -- 砲彈：明顯的拋物線，看得出來、閃得掉 —— 壓制型的重點是**可預測**
        projectile_speed_mult = 26,
        projectile_grav_mult = 8,
        fire_cooldown = 1.6,
        image = "images/enemy_drone",   -- 佔位
        anim_fps = 12,
        bullet_offset_x = 6,
        bullet_offset_y = 24
    },

    -- ======================================================================
    -- [[ §15.4 追擊型敵人 ]] 2026-08-19　自爆 BOMBER ／ 衝擊 RAMMER
    -- ----------------------------------------------------------------------
    -- ★★ 這兩隻是本作**第一種會朝玩家移動**的敵人。在此之前所有敵人都是
    --   繞出生點巡邏或原地不動，所以「背後有東西逼近」做不出來 ——
    --   **反向槍 BACK_GUN 一直沒有場合，就是卡在這裡。**
    --   （現有關卡的重生點也全部在最右邊：M008 三個場景都是 x=760／場景寬 800。）
    -- ★ 追法（使用者拍板）：偵測範圍內才追、脫離就放棄回原位。
    --   走位是有效解法；一路追到底的話玩家無法脫離、只能硬打。
    -- ⚠️ 兩隻都**不會走進 pit**（見 entity_enemy 的 CHASE 分支）——
    --   會的話玩家只要站在坑後面就無敵了。
    -- ⚠️ 美術未做：兩隻都沿用既有圖佔位。
    -- ======================================================================

    -- 自爆：靠近 → 停下 → 閃爍倒數 → 必爆（使用者拍板）
    ["BOMBER_ENEMY"] = {
        -- [[ §8.08 ]] 會掉資源（與 MINE 不同：MINE 是陷阱，這隻是敵人）
        drop = { steel = {1, 2} },
        name = "BOMBER", hp = 8, attack = 0,
        move_type = "CHASE", attack_type = "EXPLODE",
        -- 追擊
        detect_range = 170,
        give_up_range = 260,
        chase_speed = 46,      -- 比玩家慢一些 → 逃得掉，但要花時間
        return_speed = 26,
        -- ★ 距離引爆：不必碰到。倒數一開始就**必爆**（跑掉也爆）——
        --   可取消的話玩家後退一步就完全免疫，那就不是攻擊而是陷阱了。
        explode_trigger_range = 46,
        explode_delay = 1.0,   -- 反應窗口（MINE 是 2.0；這隻是主動撲上來的，給短一點）
        explode_radius = 56,
        explode_damage = 16,
        image = "images/enemy1",    -- 佔位（沿用 BASIC 的 2 格圖：待機／移動）
        anim_idle_move = true,
        warn_blink_speed = 12,      -- 沒有警示燈圖 → 走既有的「白框閃爍」後備
        bullet_offset_x = 4,
        bullet_offset_y = 16
    },

    -- 衝擊：撞到就把玩家推開一段（一次性），傷害低
    ["RAMMER_ENEMY"] = {
        drop = { steel = {2, 3} },
        -- ★ attack 低是刻意的：它的殺傷力來自**把玩家推下 pit**，不是扣血。
        name = "RAMMER", hp = 22, attack = 4,
        move_type = "CHASE", attack_type = "RAM",
        detect_range = 190,
        give_up_range = 300,
        chase_speed = 58,      -- 比自爆快 → 甩不太掉，但撞完會冷卻
        return_speed = 30,
        ram_push = 44,         -- 一次撞擊把機體推開幾 px　⚠️ 與 pit 的組合很致命，要試玩
        ram_cooldown = 1.2,    -- 撞完的冷卻：玩家有時間重新站位
        -- 佔位：用單張 enemy02。★ 不要用 enemy04 —— 那是 WALKER 的 imagetable，
        -- 換幀邏輯寫在 MOVE_PAUSE 分支裡，CHASE 型別不會推進它，只會定格第 1 格。
        image = "images/enemy02",
        bullet_offset_x = 4,
        bullet_offset_y = 16
    }
}