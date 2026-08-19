-- parts_data.lua
import "CoreLibs/graphics"
local gfx = playdate.graphics

local parts_data = {
    ["GUN"] = {
        name = "GUN",
        part_type = "GUN",  -- 功能類別
        -- [[ §8.08 死鎖安全閥 ]] 初始零件不吃耐久、永不損壞。
        -- 「耐久 0 擋出擊」＋「重打不給關卡獎勵」會合成永久卡關：
        -- 零件全壞 → 不能出擊 → 賺不到資源 → 修不好 → 永遠不能出擊。
        -- 初始存檔就是 GUN + WHEEL1 且資源 0，所以那個狀態是真的到得了的。
        -- ★ 用資料欄位而不是在程式裡寫死 id 清單 —— 日後改由別的零件當保底只要改資料。
        indestructible = true,
        hp = 10,
        weight = 3,
        attack = 5,  -- 攻擊力
        slot_x = 1,
        slot_y = 1,
        -- 購買成本
        cost_steel = 10,
        cost_copper = 10,
        cost_rubber = 5,
            color = gfx.kColorBlack,
            image = "images/gun.png",
        -- placement_row: "TOP", "BOTTOM", or "BOTH"
        placement_row = "TOP",
        align_image_top = false,  -- 圖片底部對齊格子底部（預設行為）
        -- UI 操作介面圖片
        ui_panel = "images/gun_panel.png",
        operation_hint = "Auto Fire",
        operable = false,  -- 全自動、無操作 → 不進入焦點切換循環（無法選中）
        requires_clear_right = true,  -- 槍口淨空：右側（同排）有零件則不可安裝，避免子彈穿過自己的零件
        -- GUN 特有屬性：砲彈發射
        fire_cooldown = 1.0,  -- 每 1 秒發射一次
        projectile_damage = 5,  -- 砲彈傷害
        projectile_speed_mult = 40,  -- 速度倍率（相對於基準速度）
        projectile_grav_mult = 0.2,  -- 重力倍率（相對於世界重力 0.5）
        -- GUN 會阻擋右方的發射
        block_directions = {"RIGHT"}
    },

    -- [[ 2026-08-11 ]] 雷射槍：GUN 的變體，發射**會往前飛的短光束**而非砲彈。
    -- 與 GUN 的三個差異：**手動按 A 發射**（GUN 是全自動）、**速度快很多**、**會貫穿**。
    -- ★ 因為 operable=true，它**不走** updateParts 的自動發射迴圈，
    --   而是走 updateActivePart 的 `part_type == "GUN"` 分支（焦點在它身上時按 A）。
    ["GUN2"] = {
        name = "LASER",
        part_type = "GUN",
        hp = 12,
        weight = 5,
        attack = 12,
        slot_x = 2,          -- 圖 32px 寬 = 2 格
        slot_y = 1,
        -- 購買成本（比 GUN 貴：射程雖短但會貫穿）
        cost_steel = 30,
        cost_copper = 35,
        cost_rubber = 10,
            color = gfx.kColorBlack,
            image = "images/gun02.png",
        placement_row = "TOP",
        align_image_top = false,
        ui_panel = "images/gun_panel.png",
        operation_hint = "A: Fire Laser",
        -- ★ 手動發射：進焦點循環，焦點在它身上時按 A 發射（與 CANON 同一套）。
        --   面板右格用共用的 canon_button（1=放開 / 2=按下）。
        operable = true,
        requires_clear_right = true,  -- 槍口淨空
        -- ★ 雷射參數（量自 gun02.png：32×16，槍口在**右端** x=31、管身中心 y=8）
        fire_type = "LASER",
        muzzle_x = 31,                -- 相對零件圖左上角
        muzzle_y = 8,
        fire_cooldown = 2.2,          -- ★ 比 GUN(1.0) 長
        -- 光束是**會往前飛的短線段**，不是瞬間命中（見 entity_controller:addPlayerLaser）
        laser_length = 40,            -- 線段本身的長度（★比 BOSS 的整條畫面短很多）
        laser_thickness = 3,          -- BOSS 是 5
        laser_speed_mult = 150,       -- ★ 比子彈快很多（GUN 的 projectile_speed_mult 是 40）
        laser_range = 420,            -- 飛超過這個距離就消失（保險，正常會先飛出畫面）
        projectile_damage = 12,       -- **貫穿**：同一發會打到路徑上每一隻，但每隻只吃一次
        block_directions = {"RIGHT"}
    },

    -- ================================================================
    -- [[ GDD §15.9 第一批輔助零件 ]] 2026-08-13
    -- 兩把都是 **1 格寬 + operable = false**（被動自動開火、不進焦點循環）
    -- → 切換壓力零增加，**既有 8 關的難度基準不變**。
    --
    -- ★ 1 格寬是重點：上排 3 格，10 個舊零件裡只有 GUN 是 1 格，
    --   所以「上層裝多個零件」以前幾乎不可能。加了這兩把才真的能組合。
    -- ================================================================

    -- 反向槍：往**左**射，掩護背後。
    -- ★ 存在理由見 GDD §8.08：敵人掉落物落在身後，折返撿資源時背後才是威脅。
    ["BACK_GUN"] = {
        name = "BACK GUN",
        part_type = "GUN",
        hp = 10,
        weight = 3,
        attack = 5,
        slot_x = 1,
        slot_y = 1,
        -- 比 GUN 略貴：它蓋住的是 GUN 蓋不到的方向，不該是純上位替代
        cost_steel = 15,
        cost_copper = 15,
        cost_rubber = 5,
        color = gfx.kColorBlack,
        image = "images/gun_back.png",
        placement_row = "TOP",
        align_image_top = false,
        ui_panel = "images/gun_panel.png",   -- 沿用 GUN 的面板（GUN2 也是這樣共用）
        operation_hint = "Auto Fire (Back)",
        operable = false,
        -- ★ 圖 24 寬、格子 16 寬 → 多出來的 8px 是槍口。
        --   繪製是**左對齊格子左緣**的，所以要往左推 8px 槍口才會朝左伸出格外；
        --   不推的話槍身會侵入右邊那一格。
        --   ⚠️ image_offset_x/y ＝「整個零件相對格子的位移」，**繪製端與槍口端共用同一組**。
        image_offset_x = -8,
        requires_clear_left = true,          -- 槍口淨空（GUN 的 requires_clear_right 的鏡像）
        fire_direction = "LEFT",             -- ★ 沒有這個欄位就會往右射（預設 RIGHT）
        fire_cooldown = 1.2,                 -- 比 GUN(1.0) 稍慢
        projectile_damage = 5,
        projectile_speed_mult = 40,
        projectile_grav_mult = 0.2,
        block_directions = {"LEFT"}
    },

    -- 高位槍：裝在較高的位置、攻擊力較弱（GDD §15.2）。
    -- 用途是打高處目標，以及在 CLAW(2格) 旁邊補一把槍。
    -- 高位槍：架高的**拋射**武器。2026-08-13 改版（使用者拍板）：
    --   1) 子彈**受重力影響** → 打的是弧線,不必再配合特定高度的敵人
    --   2) **手動發射**（按 A）
    --   3) **可與其他向前發射的武器並存**（拿掉槍口淨空）——
    --      但子彈若被自己的武器擋住就會消失（見 entity_controller 的 self-block）
    ["HIGH_GUN"] = {
        name = "HIGH GUN",
        part_type = "HIGH_GUN",              -- ★ 自己的型別：它不再走 GUN 的自動開火迴圈
        hp = 8,
        weight = 2,                          -- 比 GUN 輕（火力換重量）
        attack = 3,
        slot_x = 1,                          -- 1 格
        slot_y = 1,
        cost_steel = 10,
        cost_copper = 8,
        cost_rubber = 2,
        color = gfx.kColorBlack,
        image = "images/gun_high.png",
        placement_row = "TOP",
        align_image_top = false,
        ui_panel = "images/gun_panel.png",
        operation_hint = "A: Lob Shot",
        operable = true,                     -- ★ 手動：進焦點循環,按 A 發射
        -- 槍口相對**零件圖左上角**（與 GUN2 同一套慣例）。圖畫多高,槍口就自動多高。
        muzzle_x = 20,
        muzzle_y = 8,
        -- ★ **不設 requires_clear_right** —— 可以和 GUN/CANON 並排。
        --   代價是子彈可能被自己的武器擋掉（那是刻意的取捨,不是 bug）。
        fire_direction = "RIGHT",
        fire_cooldown = 1.4,
        projectile_damage = 3,               -- 「攻擊力較弱」（GUN 是 5）
        projectile_speed_mult = 26,          -- 比 GUN(40) 慢 → 弧線更明顯
        -- ★★ 這一項就是這次改版的核心：**受重力影響**。
        --   GUN 是 0.2（幾乎直線）；這裡拉到 18,打出明顯的拋物線,
        --   可以越過前方的敵人或障礙打到後面 —— 所以不必再依賴特定高度的敵人。
        projectile_grav_mult = 18,
        -- ★ 子彈會被自己的零件擋掉（見 EntityController 的 self_block）
        self_block = true,
        -- ⚠️ 不再宣告 block_directions —— 它不擋別人的射線,別人也不擋它的安裝。
    },

    -- ================================================================
    -- [[ GDD §15.2 第二批輔助零件 ]] 2026-08-13
    -- 寬度**依功能強度決定**（使用者拍板）：弱的 1 格、強的 2 格。
    -- ★ 上排只有 3 格,所以 2 格的輔助零件會**擠掉主武器** —— 那是刻意的取捨。
    -- ================================================================

    -- 防護罩：擋一次傷害後進入冷卻,冷卻完又能擋（使用者拍板：**有冷卻、會恢復**）。
    -- ★ 被動生效（operable = false）→ 不進焦點循環,切換壓力零增加。
    -- ★ 不碰傷害模型本身:它只是在傷害套用**之前**攔一次,共享血量池維持現狀。
    ["SHIELD"] = {
        name = "SHIELD",
        part_type = "SHIELD",
        hp = 15,
        weight = 4,
        slot_x = 1,          -- 1 格：被動、不直接輸出傷害 → 不該擠掉主武器
        slot_y = 1,
        cost_steel = 25,
        cost_copper = 20,
        cost_rubber = 15,
        color = gfx.kColorBlack,
        image = "images/shield_part.png",
        placement_row = "TOP",
        align_image_top = false,
        ui_panel = "images/gun_panel.png",   -- 暫時沿用,之後有專屬面板再換
        operation_hint = "Auto Block",
        operable = false,
        -- ★ 擋下一次攻擊後的冷卻秒數。調這個數字＝調「多久能擋一次」。
        shield_cooldown = 5.0,
        -- 護罩視覺半徑（以機體中心為圓心）。★ 目前**只是視覺**：
        -- 傷害是由 entity_controller 加總後才回傳一個數字,分不出來源方位,
        -- 所以護罩實際上是「擋下一次任何傷害」,不是按距離判定。
        -- 要做成真的按範圍擋,得改成逐傷害來源判斷（見 GDD §15.2 待議）。
        shield_radius = 42,
    },

    -- 追蹤飛彈：先往上發射,再搜尋敵人並轉向飛過去。
    -- ★ GDD §15.2 明寫「**轉向速度與飛行速度可調,且刻意不要太強**」——
    --   下面三個數字就是那個閥門,不要一次調滿。
    -- ★ 2 格寬 + operable = true：它是**強力主動武器**,要付出「佔格子」與「佔焦點」兩種成本
    --   （與雷射槍 GUN2 同一套定位）。
    ["MISSILE"] = {
        name = "MISSILE",
        part_type = "MISSILE",
        hp = 12,
        weight = 7,
        attack = 20,
        slot_x = 2,
        slot_y = 1,
        cost_steel = 50,
        cost_copper = 70,
        cost_rubber = 20,
        color = gfx.kColorBlack,
        image = "images/missile_part.png",
        placement_row = "TOP",
        align_image_top = false,
        ui_panel = "images/canon_panel.png", -- 暫時沿用
        operation_hint = "A: Fire Missile",
        operable = true,                     -- 手動：按 A 發射（進焦點循環）
        fire_cooldown = 3.0,                 -- ★ 比任何槍都長
        projectile_damage = 20,
        -- 飛彈參數（★ 這三個就是「刻意不要太強」的閥門）
        missile_launch_speed = 90,           -- 發射初速（先往上）
        missile_turn_rate = 120,             -- 每秒最多轉幾度 —— **越小越笨、越容易閃掉**
        missile_speed = 110,                 -- 巡航速度
        missile_life = 4.0,                  -- 存活秒數（找不到目標就自滅）
        missile_seek_range = 260,            -- 搜尋半徑
    },

    -- 偵測器：讓隱形敵人**隨時可見可打**（§15.2 + §15.4，兩者是一組）。
    -- ★ 1 格寬、被動：它本身不輸出傷害,只是把「看得到」這件事打開。
    -- ★ 沒裝的話隱形敵人只有現身那 1.5 秒能打 —— 這就是它的價值。
    ["DETECTOR"] = {
        name = "DETECTOR",
        part_type = "DETECTOR",
        hp = 8,
        weight = 3,
        slot_x = 1,
        slot_y = 1,
        cost_steel = 15,
        cost_copper = 40,
        cost_rubber = 5,
        color = gfx.kColorBlack,
        image = "images/detector_part.png",
        placement_row = "TOP",
        align_image_top = false,
        ui_panel = "images/gun_panel.png",   -- 暫時沿用
        operation_hint = "Reveals Cloaked",
        operable = false,
    },

    -- 吊索鉤：掛上場景的**吊索**後離開地面，沿索左右移動（§15.2 + §15.3，一組）。
    -- ★ operable = true → 進焦點循環,焦點在它身上時 **A = 掛上/放開**、左右 = 沿索移動。
    --   這與「跳躍綁在焦點上」是同一套模型（GDD §8.06）:移動能力要付出切換成本。
    -- ★ 放在**上排**：鉤子是往上勾的,裝在下排（移動零件那排）語意不對,
    --   而且下排 3 格已被輪子/腿佔滿。
    ["HOOK"] = {
        name = "HOOK",
        part_type = "HOOK",
        hp = 10,
        weight = 5,
        slot_x = 2,          -- 2 格：它提供一整套移動模式，不該只佔 1 格
        slot_y = 1,
        cost_steel = 30,
        cost_copper = 25,
        cost_rubber = 30,
        color = gfx.kColorBlack,
        image = "images/hook_part.png",
        placement_row = "TOP",
        align_image_top = false,
        ui_panel = "images/canon_panel.png", -- 2 格寬的面板（右格放 A 鈕）
        operation_hint = "A: Shoot Hook / Crank: Reel",
        operable = true,
        -- 鉤子往上發射的最大距離（機體頂端往上找索道）
        hook_reach = 96,
        -- 沿索移動速度（px/幀，與地面移動的 move_speed 同一個尺度）
        hook_speed = 2.4,
        -- 鉤索長度（機體頂端與索道的垂直距離）可調範圍
        hook_len_min = 16,
        hook_len_max = 110,
        -- crank 轉一整圈 → 收放這麼多 px
        hook_reel_per_rotation = 120,
    },

    ["WHEEL1"] = {
        name = "WHEEL 1",  -- [[ 2026-08-13 ]] 清單改顯示 name 後，兩顆輪子不能同名
        part_type = "WHEEL",  -- 功能類別
        indestructible = true,  -- [[ §8.08 死鎖安全閥 ]] 初始零件，永不損壞（理由見 GUN）
        hp = 35,
        weight = 4,
        slot_x = 3,
        slot_y = 1,
        -- 購買成本
        cost_steel = 10,
        cost_copper = 5,
        cost_rubber = 10,
            color = gfx.kColorBlack,
            image = "images/wheel.png",
            placement_row = "BOTTOM",
        align_image_top = false,  -- 圖片底部對齊格子底部（預設行為）
        -- UI 操作介面圖片
        ui_panel = "images/wheel_panel.png",
        ui_stick = "images/wheel_stick.png",
        operation_hint = "Left/Right to move, A to Jump",
        move_speed = 2.0,  -- 左右移動速度
        -- [[ 跳躍 ]] 跳躍高度（px）；實際 = 這個值 × 核心 jump_mult。輪子跳最低
        jump_height = 30,
        climb_power = 1  -- 爬坡力: 1=只能15度, 2=可爬15-30度, 3=可爬所有斜坡
    },

   ["CLAW"] = {
        name = "CLAW",
        part_type = "CLAW",  -- 功能類別
        hp = 45,
        weight = 8,
        attack = 5,  -- 攻擊力（揮動攻擊）
        slot_x = 2,
        slot_y = 1,
        -- 購買成本
        cost_steel = 35,
        cost_copper = 10,
        cost_rubber = 10,
        color = gfx.kColorBlack,
        image = "images/claw_base.png",  -- 主圖片為底座
        placement_row = "TOP",
        align_image_top = false,  -- 圖片底部對齊格子底部
        -- UI 操作介面圖片
        ui_panel = "images/claw_panel.png",
        operation_hint = "Crank: Arm / A: Grab-Release",
        -- CLAW 特有屬性（P3 改制：crank 控臂、A 抓/放、開合自動演出）
        arm_image = "images/claw_arm.png",  -- 臂的圖片
        -- [[ 支點 2026-08-08 ]] 全部是「圖片內的座標」，量自實際像素，換圖後重量即可。
        -- 1) 臂裝在底座的**右邊那顆齒輪**上（底座有兩顆齒輪，左 8.0 / 右 21.5）
        arm_mount_x = 21.5, arm_mount_y = 7.5,   -- claw_base.png(32×16) 內的右齒輪中心
        -- 2) 臂自己的旋轉中心＝左端（貼在齒輪上的那一端）
        arm_pivot_x = 0,    arm_pivot_y = 7.0,   -- claw_arm.png(44×16) 內
        -- 3) 爪子的開合軸＝臂右端那個圓盤的圓心（不是圖的右邊緣）
        claw_pivot_x = 35.5, claw_pivot_y = 7.5, -- claw_arm.png 內
        -- 4) 上下爪的鉸鏈點（各自圖內的座標，22×12）：
        --    **上爪＝左下角、下爪＝左上角** —— 兩爪的鉸鏈疊在同一根軸上，
        --    閉合時上爪往上長、下爪往下長，合起來是一支 24px 高的夾子。
        upper_pivot_x = 0, upper_pivot_y = 12,   -- claw_upper.png 左下角
        lower_pivot_x = 0, lower_pivot_y = 0,    -- claw_lower.png 左上角
        -- 5) 夾持點：從鉸鏈軸沿臂的方向再往前這麼多 px。
        --    量自爪圖的凹口（被爪體包住的透明區）中心 x=12 —— 石頭放在這裡才像「夾住」，
        --    放在鉸鏈軸上會看起來卡在關節裡。抓取判定也用同一點。
        grip_hold_dist = 12,
        upper_image = "images/claw_upper.png",  -- 上爪圖片
        lower_image = "images/claw_lower.png",  -- 下爪圖片
        arm_angle_min = -90,  -- 臂最小角度（度）
        arm_angle_max = 90,  -- 臂最大角度（度）
        claw_angle_min = 0,  -- 爪子閉合角度（度）
        claw_angle_max = 45,  -- 爪子張開角度（度）
        crank_degrees_per_rotation = 90,  -- crank 轉 1 圈產生的「臂」角度變化（A2 調校 180→90：全範圍 ±90° 需轉兩圈，強化手忙腳亂感）
        grip_anim_speed = 5,  -- 爪子開合自動演出速度（度/幀）
        throw_speed_mult = 5.0  -- 投擲物體的速度倍率
    },




    ["WHEEL2"] = {
        name = "WHEEL 2",  -- [[ 2026-08-13 ]] 清單改顯示 name 後，兩顆輪子不能同名
        part_type = "WHEEL",  -- 功能類別
        hp = 50,
        weight = 4,
        slot_x = 3,
        slot_y = 1,
        -- 購買成本
        cost_steel = 40,
        cost_copper = 15,
        cost_rubber = 50,
            color = gfx.kColorBlack,
            image = "images/wheel2.png",
            placement_row = "BOTTOM",
        -- [[ 2026-08-10 ]] 圖改成 48×20（原 48×16），比格子高 4px，
        -- 所以改成**與 FEET 同一套原則**：上緣對齊格子上緣，多出來的 4px 往下超出格子。
        align_image_top = true,
        -- UI 操作介面圖片
        ui_panel = "images/wheel_panel.png",
        ui_stick = "images/wheel_stick.png",
        operation_hint = "Left/Right to move, A to Jump",
        move_speed = 2.0,  -- 左右移動速度
        -- [[ 跳躍 ]] 跳躍高度（px）；實際 = 這個值 × 核心 jump_mult。比 WHEEL1 好一點
        jump_height = 42,
        climb_power = 2  -- 爬坡力: 1=只能15度, 2=可爬15-30度, 3=可爬所有斜坡
    },

    ["CANON1"] = {
        name = "CANON1",
        part_type = "CANON",  -- 功能類別
        hp = 30,
        weight = 10,
        slot_x = 2,
        slot_y = 1,
        -- 購買成本
        cost_steel = 20,
        cost_copper = 60,
        cost_rubber = 0,
            color = gfx.kColorBlack,
            image = "images/canon.png",  -- 砲管
            base_image = "images/canon_base.png",  -- 底座
        -- [[ 版面 2026-08-08 ]] 砲管相對「格子底部」的垂直偏移（負值＝往上）。
        -- 只移動砲管，底座不動。★旋轉軸心與**砲彈發射點**都會一起移，
        -- 否則砲彈會從砲管下方飛出來（軸心原本固定在格中心）。
        -- −2 的由來:讓砲管左端的圓與底座的圓形樞紐同心 —
        --   底座圓心在自己圖裡 y=6.0、砲管圓心 y=7.5 → 6.0−7.5 = −1.5，取整 −2。
        --   換圖後要重算的話,把兩張圖的像素攤開看圓心 y 差多少即可。
        barrel_offset_y = -2,
            placement_row = "TOP",
        align_image_top = false,  -- 圖片底部對齊格子底部（預設行為）
        -- UI 操作介面圖片
        ui_panel = "images/canon_panel.png",
        operation_hint = "Adjust Angle with Crank",
        -- CANON 特有屬性：砲彈發射
        fire_cooldown = 0.5,  -- 每 0.5 秒可以發射一次
        projectile_damage = 10,  -- 砲彈傷害
        projectile_speed_mult = 30,  -- 速度倍率（相對於基準速度）
        projectile_grav_mult = 20,  -- 重力倍率（相對於世界重力 0.5）
        -- CANON 轉動控制
        angle_min = 0,  -- 最小角度（度）
        angle_max = 90,  -- 最大角度（度）
        crank_degrees_per_rotation = 15,  -- crank 轉 1 圈（360度）產生的 canon 角度變化
        -- CANON 會阻擋右上方的發射方向
        block_directions = {"RIGHT_UP"}
    },
    -- [[ CANON3 迫擊砲 2026-08-08 ]] 高拋物線 + 落點範圍爆炸。
    -- 定位:打不到直線目標(掩體後、盾牌兵正面),但一發能清一小群。
    -- 與 CANON1/2 的差別全在數值:速度更慢、重力更大 → 弧度更彎;多了 blast_*。
    ["CANON3"] = {
        name = "CANON3",
        part_type = "CANON",  -- 功能類別（共用 CANON 的操作/繪製/面板）
        hp = 35,
        weight = 12,
        slot_x = 2,
        slot_y = 1,
        -- 購買成本
        cost_steel = 60,
        cost_copper = 100,
        cost_rubber = 20,
            color = gfx.kColorBlack,
            image = "images/canon3.png",  -- 砲管
            base_image = "images/canon_base.png",  -- 底座（與 CANON1/2 共用）
        barrel_offset_y = -2,
            placement_row = "TOP",
        align_image_top = false,
        -- UI 操作介面圖片（與 CANON1/2 共用）
        ui_panel = "images/canon_panel.png",
        operation_hint = "Adjust Angle with Crank",
        -- 砲彈：直擊傷害低，靠爆炸吃傷害
        fire_cooldown = 1.5,
        projectile_damage = 8,
        projectile_speed_mult = 24,   -- 比 CANON1(30)/CANON2(20) 慢
        projectile_grav_mult = 40,    -- 比 CANON1(20)/CANON2(25) 重 → 弧度最彎、飛得最慢
        -- 實測彈道(45°):CANON1 射程 359 / CANON2 127 / CANON3 114,但 CANON3 飛行 3.4 秒最久。
        -- 拉到 75° 時射程剩 58、最高點 53 —— 這就是它的用法:越過掩體砸下去。
        -- [[ 範圍爆炸 ]] 命中敵人或落地時引爆；範圍內敵人都吃 blast_damage
        blast_radius = 44,
        blast_damage = 18,
        -- CANON 轉動控制
        angle_min = 0,
        angle_max = 90,
        crank_degrees_per_rotation = 15,
        block_directions = {"RIGHT_UP"}
    },
  ["CANON2"] = {
        name = "CANON2",
        part_type = "CANON",  -- 功能類別
        hp = 40,
        weight = 10,
        slot_x = 2,
        slot_y = 1,
        -- 購買成本
        cost_steel = 40,
        cost_copper = 80,
        cost_rubber = 10,
            color = gfx.kColorBlack,
            image = "images/canon2.png",  -- 砲管
            base_image = "images/canon_base.png",  -- 底座
        -- [[ 版面 2026-08-08 ]] 砲管相對「格子底部」的垂直偏移（負值＝往上）。
        -- 只移動砲管，底座不動。★旋轉軸心與**砲彈發射點**都會一起移，
        -- 否則砲彈會從砲管下方飛出來（軸心原本固定在格中心）。
        -- −2 的由來:讓砲管左端的圓與底座的圓形樞紐同心 —
        --   底座圓心在自己圖裡 y=6.0、砲管圓心 y=7.5 → 6.0−7.5 = −1.5，取整 −2。
        --   換圖後要重算的話,把兩張圖的像素攤開看圓心 y 差多少即可。
        barrel_offset_y = -2,
            placement_row = "TOP",
        align_image_top = false,  -- 圖片底部對齊格子底部（預設行為）
        -- UI 操作介面圖片
        ui_panel = "images/canon_panel.png",
        operation_hint = "Adjust Angle with Crank",
        -- CANON 特有屬性：砲彈發射
        fire_cooldown = 1,  -- 每 0.5 秒可以發射一次
        projectile_damage = 20,  -- 砲彈傷害
        projectile_speed_mult = 20,  -- 速度倍率（相對於基準速度）
        projectile_grav_mult = 25,  -- 重力倍率（相對於世界重力 0.5）
        -- CANON 轉動控制
        angle_min = 0,  -- 最小角度（度）
        angle_max = 90,  -- 最大角度（度）
        crank_degrees_per_rotation = 15,  -- crank 轉 1 圈（360度）產生的 canon 角度變化
        -- CANON 會阻擋右上方的發射方向
        block_directions = {"RIGHT_UP"}
    },


--    ["SWORD"] = {
--        name = "SWORD",
--        part_type = "SWORD",  -- 功能類別
--        hp = 40,
--        weight = 5,
--        attack = 20,  -- 攻擊力
--        slot_x = 2,
--        slot_y = 1,
        -- 購買成本
--        cost_steel = 70,
--        cost_copper = 15,
--        cost_rubber = 35,
--            color = gfx.kColorBlack,
--            image = "images/sword.png",
--            placement_row = "TOP",
--        align_image_top = false,  -- 圖片底部對齊格子底部（預設行為）
        -- UI 操作介面圖片
--        ui_panel = "images/sword_panel.png",
--        ui_stick = "images/sword_stick.png",
--        operation_hint = "Swing Sword with Crank",
--    },
    ["FEET"] = {
        name = "FEET",
        part_type = "FEET",  -- 功能類別
        hp = 50,
        weight = 7,
        slot_x = 3,
        slot_y = 1,
        -- 購買成本
        cost_steel = 150,
        cost_copper = 80,
        cost_rubber = 35,
            color = gfx.kColorBlack,
            image = "images/feet.png",
            placement_row = "BOTTOM",
        -- FEET 特有屬性
        align_image_top = true,  -- 圖片上緣對齊格子上緣（圖片下半部會超出格子）
        -- UI 操作介面圖片（先用與 WHEEL 相同的圖）
        ui_panel = "images/wheel_panel.png",
        ui_stick = "images/wheel_stick.png",
        operation_hint = "Left/Right to move, A to Jump",
        move_speed = 2.0,  -- 左右移動速度（2026-08-07 由 3.0 調慢）
        -- [[ 手感 ]] 滑行衰減：腿是「踩」的，該停得快；輪子才該滑（見 MechController.COAST_FRICTION）
        coast_friction = 0.55,
        -- [[ 跳躍 ]] 跳躍高度（px）。實際高度 = 這個值 × 核心的 jump_mult。
        -- 腿＝跳最高。初速度由程式從高度反推，改這個數字就能直接看到跳多高。
        jump_height = 64,
        animation_walk = "images/feet_walk",  -- 行走動畫 imagetable 路徑
        climb_power = 3  -- 爬坡力: 1=只能15度, 2=可爬15-30度, 3=可爬所有斜坡
    },
 


}

-- [[ G2b ]] 商店文字說明（集中管理，一處編修）。key = 零件 id。
local descriptions = {
    GUN    = "Auto-firing gun. Shoots forward on its own.",
    WHEEL1 = "Basic wheel. Move left and right.",
    WHEEL2 = "Tougher wheel. Climbs steeper slopes.",
    CLAW   = "Crank to swing the arm. Press A to grab or release.",
    CANON1 = "Cannon. Aim the barrel with the crank.",
    CANON2 = "Heavy cannon. Stronger shots, slower fire.",
    CANON3 = "Mortar. Lobs shells that blast an area.",
    SWORD  = "Swing the blade with the crank.",
    FEET   = "Legs. Move around and press A to jump.",
}
for pid, d in pairs(descriptions) do
    if parts_data[pid] then parts_data[pid].description = d end
end

return parts_data