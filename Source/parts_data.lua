-- parts_data.lua
import "CoreLibs/graphics"
local gfx = playdate.graphics

local parts_data = {
    ["GUN"] = {
        name = "GUN",
        part_type = "GUN",  -- 功能類別
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
    ["WHEEL1"] = {
        name = "WHEEL",
        part_type = "WHEEL",  -- 功能類別
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
        name = "WHEEL",
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


    ["SWORD"] = {
        name = "SWORD",
        part_type = "SWORD",  -- 功能類別
        hp = 40,
        weight = 5,
        attack = 20,  -- 攻擊力
        slot_x = 2,
        slot_y = 1,
        -- 購買成本
        cost_steel = 70,
        cost_copper = 15,
        cost_rubber = 35,
            color = gfx.kColorBlack,
            image = "images/sword.png",
            placement_row = "TOP",
        align_image_top = false,  -- 圖片底部對齊格子底部（預設行為）
        -- UI 操作介面圖片
        ui_panel = "images/sword_panel.png",
        ui_stick = "images/sword_stick.png",
        operation_hint = "Swing Sword with Crank",
    },
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