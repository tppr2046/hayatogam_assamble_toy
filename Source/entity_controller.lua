-- entity_controller.lua — EntityController 類別（關卡總控：地形/實體管理/碰撞裁判）
-- [[ P1 拆檔 ]] 自 module_entities.lua 拆出；由 module_entities.lua（聚合器）載入

import "CoreLibs/graphics"

local gfx = playdate.graphics
-- EnemyData 由 entity_enemy.lua 載入並掛於 _G（Playdate import 同檔僅載一次，
-- 二次 import 拿不到回傳值，故經 _G 中繼；聚合器保證 entity_enemy 先載入）
local EnemyData = _G.EnemyData or {}

EntityController = {}

-- [[ 運送目標 target ]] 2026-08-09 改版：目標會浮空、上下飄、放上箱子後往左上飛走。
local TARGET_FLOAT_H    = 5     -- 浮在地面上方幾 px（指圖的底部離地）
local TARGET_BOB_AMP    = 3     -- 上下飄的振幅（px）
local TARGET_BOB_SPEED  = 2.2   -- 上下飄的速度（弧度/秒）
local TARGET_FRAME_TIME = 0.12  -- sprite sheet 換幀秒數
-- ★ 平台上表面在 sprite 內的 y（量自 target-table-32-32.png：0~7 列是空的，平台從 8 開始）。
--   箱子要「踩在平台上」＝箱底對齊這條線，不是對齊圖的中心。換圖後重量即可。
local TARGET_PLATFORM_TOP = 8
local TARGET_FLY_VX     = -70   -- 飛走的水平速度（往左）
local TARGET_FLY_VY     = -110  -- 飛走的起始垂直速度（往上）
local TARGET_FLY_ACC    = 220   -- 往上的加速度（px/s²）——起飛感，也縮短等待
local TARGET_FLY_MAX_T  = 3.0   -- 保險：超過這個秒數就強制結束（避免任何情況卡住）

-- [[ 懸崖判定 ]] 「腳掌」取樣的內縮比例（相對機體寬度）。
-- 中心點在 pit 缺口上方時，改看中心 ± 機寬×這個比例 的兩點，任一踩到實地就算站得住。
-- 越大＝跳躍落地越寬容，但走出崖邊時也會多懸空一段才掉下去（兩者是同一個數字）。
-- 0.25 對 48px 寬的機體＝左右各多 12px 的容錯。
local FOOT_INSET_RATIO = 0.25

-- [[ 懸崖判定 ]] 地面吸附的最大幅度（px）。機體底部低於地面超過這個值就不再吸附，
-- 代表它是「掉進懸崖」而非「落地」，應該繼續下墜。
-- ★ 下限受落地速度限制:最快的跳躍(CORE3 FEET, v≈9.1)落地當幀會陷入約 9px，
--   所以這個值必須 > 10，否則會有跳躍落不了地的 bug。
local STEP_UP_MAX = 12

-- [[ S5 護送 ]] NPC 領先玩家超過這個距離就停下來等（px）。
-- 螢幕寬 400、鏡頭把機體放在偏左位置，所以 140 大約是「NPC 快要走出畫面右緣」。
-- 可用關卡 JSON 的 scene.npc.wait_distance 個別覆寫。
local NPC_WAIT_DISTANCE = 140

-- [[ ========================================== ]]
-- [[  EntityController 類別 (實體總控制器) ]]
-- [[ ========================================== ]]

function EntityController:init(scene_data, enemies_data, player_move_speed, ui_offset)
    local ui_offset = ui_offset or 0  -- UI 區域偏移量
    local safe_ground_y = (scene_data and scene_data.ground_y) or 240
    -- 將地面往上移動 ui_offset
    safe_ground_y = safe_ground_y - ui_offset
    
    local controller = {
        obstacles = {},  -- 先初始化為空，稍後處理
        ground_y = safe_ground_y,
        terrain = {},  -- 地形數據
        backgrounds = {}, -- 背景層列表
        enemies = {}, -- 新增敵人列表
        projectiles = {}, -- 新增砲彈列表
        stones = {},  -- 新增石頭列表
        delivery_target = nil,  -- 交付目標物件
        GRAVITY = 0.5, -- 將重力常數傳入
        player_move_speed = player_move_speed or 2.0, -- 供敵人計算砲彈速度
        enemy_explosion_triggered = false  -- 標記是否有敵人爆炸被觸發
    }
    setmetatable(controller, { __index = EntityController })
    
    -- 初始化地形（64px單位）
    local terrain_data = (scene_data and scene_data.terrain) or {}
    for i, tdata in ipairs(terrain_data) do
        local terrain_type = tdata.type or "flat"
        local height_offset = tdata.height_offset or 0  -- 相對於 ground_y 的高度偏移
        table.insert(controller.terrain, {
            type = terrain_type,
            x = (i - 1) * 64,  -- 每單位64px寬
            width = 64,
            height_offset = height_offset
        })
    end
    
    -- [[ 天空層 ]] scene.sky = "images/bg_sky"：畫在所有 backgrounds 之後方（最遠層）。
    -- 與 backgrounds 的差別：橫向**平鋪**（backgrounds 只畫一次）、視差**更慢**、不需要 x/y 座標。
    -- 可選參數：scene.sky_parallax（預設 0.1，越小越遠）、scene.sky_y（預設 0）。
    controller.sky = nil
    controller.sky_parallax = (scene_data and scene_data.sky_parallax) or 0.1
    controller.sky_y = (scene_data and scene_data.sky_y) or 0
    controller.sky_w = 400
    if scene_data and scene_data.sky then
        local ok_sky, sky_img = pcall(function()
            return playdate.graphics.image.new(scene_data.sky)
        end)
        if ok_sky and sky_img then
            controller.sky = sky_img
            local ok_sz, sw = pcall(function() return sky_img:getSize() end)
            if ok_sz and sw and sw > 0 then controller.sky_w = sw end
        else
            print("SKY: 載入失敗 " .. tostring(scene_data.sky))
        end
    end

    -- 初始化背景層（兩層視差捲動）
    local bgs_data = (scene_data and scene_data.backgrounds) or {}
    for _, b in ipairs(bgs_data) do
        local bg = {
            layer = (b.layer or 0),
            x = b.x or 0,
            y = b.y or 0,
            image = nil,
            width = 0,
            height = 0
        }
        if b.image then
            local ok, img = pcall(function()
                return playdate.graphics.image.new(b.image)
            end)
            if ok and img then
                bg.image = img
                local ok_size, w, h = pcall(function() return img:getSize() end)
                if ok_size and w and h then
                    bg.width = w
                    bg.height = h
                end
            end
        end
        table.insert(controller.backgrounds, bg)
    end

    -- 初始化障礙物（加載圖片和計算尺寸）
    local obstacles_data = (scene_data and scene_data.obstacles) or {}
    for _, odata in ipairs(obstacles_data) do
        local obs = {
            x = odata.x,
            y = odata.y,
            width = 0,
            height = 0,
            image = nil
        }
        
        -- 加載圖片並獲取尺寸
        if odata.image then
            local ok, img = pcall(function()
                return playdate.graphics.image.new(odata.image)
            end)
            if ok and img then
                obs.image = img
                local ok_size, w, h = pcall(function() return img:getSize() end)
                if ok_size and w and h then
                    obs.width = w
                    obs.height = h
                end
            end
        else
            -- 如果沒有圖片，使用指定的寬高或預設值
            obs.width = odata.width or 40
            obs.height = odata.height or 40
        end
        
        table.insert(controller.obstacles, obs)
    end
    
    -- 初始化敵人（[[ S6 ]] type=="BOSS" 走 BOSS 工廠）
    for _, edata in ipairs(enemies_data or {}) do
        local enemy
        if edata.type == "BOSS" then
            enemy = Enemy:initBoss(edata, safe_ground_y)
        else
            enemy = Enemy:init(edata.x, edata.y, edata.type, safe_ground_y)
        end
        table.insert(controller.enemies, enemy)
    end

    -- [[ S4 ]] 敵人重生點（資料驅動）：{ type, x, y, interval 秒, max 上限(nil=無限) }
    controller.respawners = {}
    local respawns_data = (scene_data and scene_data.respawns) or {}
    for _, rd in ipairs(respawns_data) do
        table.insert(controller.respawners, {
            type = rd.type,
            x = rd.x or 0,
            y = rd.y or 0,
            interval = rd.interval or 3.0,
            max = rd.max,                 -- nil = 無上限
            timer = rd.interval or 3.0,    -- 首次生成前先等一個 interval
            spawned = 0,
        })
    end

    -- [[ S5 護送戰 ]] NPC（scene.npc）+ REACH 目標點（scene.reach）
    controller.npc = nil
    if scene_data and scene_data.npc then
        local n = scene_data.npc
        local ny = (n.y and n.y ~= 0) and n.y or (safe_ground_y - 36)
        controller.npc = {
            x = n.x or 100, y = ny, origin_x = n.x or 100,
            hp = n.hp or 60, max_hp = n.hp or 60,
            mode = n.mode or "HOLD",          -- "MOVE"（走到目標）/ "HOLD"（定點撐時間）
            goal_x = n.goal_x, range = n.range or 30, speed = n.speed or 12,
            duration = n.duration or 20,
            dir = 1, timer = 0, width = 36, height = 36,
            reached_goal = false, is_dead = false, protect_done = false,
            -- [[ 美術 ]] npc_walk-table-36-36.png：2 幀走路動畫
            frame = 1, frame_timer = 0, frame_delay = 0.16,
        }
        local okn, tbln = pcall(function() return playdate.graphics.imagetable.new("images/npc_walk") end)
        if okn and tbln then controller.npc_walk = tbln end
    end
    controller.reach = (scene_data and scene_data.reach) or nil
    controller.teleport = (scene_data and scene_data.teleport) or nil  -- [[ S1 ]] 出口（供繪製）
    controller.bunker = (scene_data and scene_data.bunker) or nil      -- [[ S5 ]] 護送終點（供繪製）

    -- [[ 前景層 ]] scene.foregrounds = { {x, y}, ... }：地面上的裝飾動圖（32x32、4 幀），
    -- 畫在「機體之上、UI 之下」，會擋住玩家但不會擋住操作面板。y 省略＝貼地。
    controller.foregrounds = {}
    for _, fd in ipairs((scene_data and scene_data.foregrounds) or {}) do
        table.insert(controller.foregrounds, { x = fd.x or 0, y = fd.y })
    end
    controller.fg_frame = 1
    controller.fg_timer = 0
    controller.fg_frame_delay = 0.40

    -- [[ S3 場景武器 ]] 可接管的場景武器（砲台）
    controller.weapons = {}
    local weapons_data = (scene_data and scene_data.weapons) or {}
    for _, wd in ipairs(weapons_data) do
        table.insert(controller.weapons, {
            type = wd.type or "TURRET",
            x = wd.x or 0,
            y = (wd.y and wd.y ~= 0) and wd.y or (safe_ground_y - 20),
            angle = wd.angle_init or 30,      -- 砲管仰角（度，往上為正、朝右發射）
            angle_min = wd.angle_min or 0,
            angle_max = wd.angle_max or 80,
            cooldown = wd.cooldown or 0.5,
            damage = wd.damage or 10,
            speed_mult = wd.speed_mult or 30,   -- 倍率（× base 2.0，對齊 CANON）
            bullet_size = wd.bullet_size or 8,
            grav_mult = wd.grav_mult or 40,     -- 拋物線弧度（對齊機體 CANON1 的 20；越大越彎）
            -- [[ 美術 ]] turret-table-32-32.png：第1格底座、第2格砲管（砲管靜止朝右）
            -- 32x32 框以「底部貼地、水平置中於 w.x」擺放；砲管繞 pivot 旋轉，子彈由槍口射出
            frame_w = 32, frame_h = 32,
            pivot_x = 10, pivot_y = 10,         -- 砲管旋轉軸心（框內座標）
            barrel_len = 21,                    -- 軸心→槍口距離
            crank_degrees_per_rotation = wd.crank_degrees_per_rotation,  -- nil＝用全域預設
        })
    end

    -- 初始化石頭
    local stones_data = (scene_data and scene_data.stones) or {}
    for _, sdata in ipairs(stones_data) do
        local stone_y = sdata.y == 0 and (safe_ground_y - 16) or sdata.y
        local stone = Stone:init(sdata.x, stone_y, safe_ground_y, sdata.target_id, sdata.image)
        table.insert(controller.stones, stone)
    end
    
    -- 初始化交付目標物件
    controller.delivery_targets = {}
    -- 支援單個目標（delivery_target）或多個目標（delivery_targets）
    local single_target = scene_data and scene_data.delivery_target
    local targets_data = (scene_data and scene_data.delivery_targets) or {}
    
    if single_target then
        local target_img = nil
        local target_width = 32
        local target_height = 32
        
        -- 加載圖片並獲取尺寸
        if single_target.image then
            local ok, img = pcall(function()
                return playdate.graphics.image.new(single_target.image)
            end)
            if ok and img then
                target_img = img
                local ok_size, w, h = pcall(function() return img:getSize() end)
                if ok_size and w and h then
                    target_width = w
                    target_height = h
                end
            end
        else
            -- 使用指定的寬高
            target_width = single_target.width or 32
            target_height = single_target.height or 32
        end
        
        local target_y = single_target.y == 0 and (safe_ground_y - target_height) or single_target.y
        local target = {
            id = single_target.id or "default",
            x = single_target.x,
            y = target_y,
            width = target_width,
            height = target_height,
            image = target_img,
            placed_stones = {},  -- 已放置的石頭列表
            is_completed = false  -- 是否已完成
        }
        table.insert(controller.delivery_targets, target)
    end
    
    for _, tdata in ipairs(targets_data) do
        local target_img = nil
        local target_width = 32
        local target_height = 32
        
        -- [[ 2026-08-09 ]] 目標改用 sprite sheet（images/target-table-32-32.png，4 幀循環）。
        -- 先試 imagetable，失敗才退回單張圖 —— 這樣舊關卡指到單張圖也不會壞。
        local target_sheet = nil
        local path = tdata.image or "images/target"
        local okT, tbl = pcall(function() return playdate.graphics.imagetable.new(path) end)
        if okT and tbl then
            target_sheet = tbl
            local f1 = tbl:getImage(1)
            if f1 then
                local ok_size, w, h = pcall(function() return f1:getSize() end)
                if ok_size and w and h then target_width, target_height = w, h end
            end
        else
            local ok, img = pcall(function() return playdate.graphics.image.new(path) end)
            if ok and img then
                target_img = img
                local ok_size, w, h = pcall(function() return img:getSize() end)
                if ok_size and w and h then target_width, target_height = w, h end
            else
                target_width = tdata.width or 32
                target_height = tdata.height or 32
            end
        end

        -- ★ 浮空：圖的底部離地 TARGET_FLOAT_H，再以 base_y 為中心上下飄
        local target_y = (tdata.y and tdata.y ~= 0) and tdata.y
                         or (safe_ground_y - target_height - TARGET_FLOAT_H)
        local target = {
            id = tdata.id or ("target" .. (#controller.delivery_targets + 1)),
            x = tdata.x,
            y = target_y,
            base_y = target_y,                       -- 飄浮的基準線
            bob_t = (#controller.delivery_targets) * 0.7,  -- 每個目標錯開相位，不會整排同步
            width = target_width,
            height = target_height,
            image = target_img,                      -- 單張圖（退回用）
            sheet = target_sheet,                    -- sprite sheet（優先）
            frame = 1, frame_timer = 0,
            fly_timer = nil,                         -- 非 nil＝正在往左上飛走
            placed_stones = {},  -- 已放置的石頭列表
            is_completed = false  -- 是否已完成
        }
        table.insert(controller.delivery_targets, target)
    end
    
    -- 計算每個目標需要的石頭數量
    for _, target in ipairs(controller.delivery_targets) do
        target.required_count = 0
        for _, stone in ipairs(controller.stones) do
            if stone.target_id == target.id then
                target.required_count = target.required_count + 1
            end
        end
    end
    
    print("LOG: EntityController initialized with " .. #controller.obstacles .. " obstacles and " .. #controller.enemies .. " enemies.")
    return controller
end

-- 添加玩家砲彈
-- blast_radius / blast_damage：命中或落地時的範圍爆炸（CANON3 的迫擊砲效果）。
-- 兩者都給才會生效；不給就是一般直擊砲彈，行為與以前完全相同。
function EntityController:addPlayerProjectile(x, y, vx, vy, damage, grav_mult, size, blast_radius, blast_damage)
    grav_mult = grav_mult or 1.0

    local projectile = Projectile:init(x, y, vx, vy, damage, true, self.ground_y)
    -- 設定重力（基準重力 * 重力倍率）
    projectile.gravity = (self.GRAVITY or 0.5) * grav_mult
    if size then projectile.width = size; projectile.height = size end  -- [[ S3 ]] 可指定子彈尺寸
    if blast_radius and blast_radius > 0 then
        projectile.blast_radius = blast_radius
        projectile.blast_damage = blast_damage or damage
    end
    table.insert(self.projectiles, projectile)
    print("LOG: Player fired projectile at (" .. math.floor(x) .. ", " .. math.floor(y) .. ") vx=" .. math.floor(vx) .. " grav_mult=" .. grav_mult)
end

-- [[ 命中特效 ]] 子彈擊中點的小火花。
-- 現階段**用程式繪製**（白色閃光 + 黑色放射線，1-bit 上在深色背景也看得見）。
-- ★ 之後放 `images/hit_spark-table-<寬>-<高>.png` 進 Source/images/ 就會自動改用圖，
--   本檔與呼叫端都不必改（幀數由 imagetable 的長度決定）。
local HIT_SPARK_FRAMES = 4        -- 程式繪製時的幀數
local HIT_SPARK_FRAME_TIME = 0.04 -- 每幀秒數（圖與程式繪製共用）

function EntityController:addHitSpark(x, y)
    if not self.spark_sheet_tried then
        self.spark_sheet_tried = true
        local ok, tbl = pcall(function() return playdate.graphics.imagetable.new("images/hit_spark") end)
        if ok and tbl then
            self.spark_sheet = tbl
            print("LOG: hit_spark imagetable loaded, frames = " .. tostring(tbl:getLength()))
        end
    end
    self.hit_sparks = self.hit_sparks or {}
    table.insert(self.hit_sparks, { x = x, y = y, frame = 1, timer = 0 })
end

-- [[ 運送目標 ]] 箱子放在目標上的位置：**水平置中、箱底踩在平台上表面**。
-- 放置當下與飛行途中都用這一個函式，兩邊才不會算出不同位置。
function EntityController:stoneRestPos(target, stone)
    local sw = (stone and stone.width) or 0
    local sh = (stone and stone.height) or 0
    return target.x + (target.width - sw) / 2,
           target.y + TARGET_PLATFORM_TOP - sh
end

-- [[ 爆炸視覺 ]] 只播動畫、不造成傷害。沿用地雷/敵人死亡的 mine_explode 圖表（不必新素材）。
-- 供 triggerBlast（範圍傷害）與 BOSS 死亡的連環爆炸共用。
function EntityController:addBlastVisual(x, y)
    if not self.blast_sheet_tried then
        self.blast_sheet_tried = true
        local ok, tbl = pcall(function() return playdate.graphics.imagetable.new("images/mine_explode") end)
        if ok and tbl then self.blast_sheet = tbl end
    end
    self.blasts = self.blasts or {}
    table.insert(self.blasts, { x = x, y = y, frame = 1, timer = 0 })
end

-- [[ 雷射槍 GUN2 2026-08-11 ]] 玩家的貫穿光束。
-- 與砲彈的三個差異：**不受重力**、**速度快很多**、**打到敵人不會消失（貫穿）**。
-- 每道光束記著自己打過誰（`hit` 集合），所以同一發不會對同一隻重複扣血，
-- 但會沿路把碰到的每一隻都打一次。
-- ★ 與 BOSS 雷射的差別：BOSS 是「瞬間一整條到畫面邊緣」，這裡是**會飛的短線段**。
function EntityController:addPlayerLaser(x, y, vx, vy, length, thickness, damage, max_range)
    self.player_lasers = self.player_lasers or {}
    table.insert(self.player_lasers, {
        x = x, y = y,
        vx = vx or 300, vy = vy or 0,
        length = length or 40,
        thickness = thickness or 3,
        damage = damage or 0,
        travelled = 0,
        max_range = max_range or 420,
        hit = {},           -- 已經打過的敵人（避免同一發重複扣血）
    })
end

-- 光束前進 + 貫穿命中判定
function EntityController:updatePlayerLasers(dt)
    if not (self.player_lasers and #self.player_lasers > 0) then return end
    for i = #self.player_lasers, 1, -1 do
        local L = self.player_lasers[i]
        local step = math.sqrt((L.vx * dt) ^ 2 + (L.vy * dt) ^ 2)
        L.x = L.x + L.vx * dt
        L.y = L.y + L.vy * dt
        L.travelled = L.travelled + step

        -- 命中：線段 [x, x+length] × [y ± 厚度/2] 與敵人矩形相交
        local half = L.thickness / 2
        local top, bot = L.y - half, L.y + half
        local x0 = math.min(L.x, L.x + L.length)
        local x1 = math.max(L.x, L.x + L.length)
        for _, enemy in ipairs(self.enemies or {}) do
            if enemy.is_alive and not L.hit[enemy] then
                local ex1 = enemy.x + (enemy.width or 0)
                local ey1 = enemy.y + (enemy.height or 0)
                if ex1 >= x0 and enemy.x <= x1 and ey1 >= top and enemy.y <= bot then
                    L.hit[enemy] = true      -- ★ 標記後就不再對這隻扣血（貫穿但不重複傷害）
                    -- 地雷：沿用既有的觸發機制（不是直接扣血）
                    if enemy.attack_type == "EXPLODE" and not enemy.is_triggered then
                        enemy.is_triggered = true
                        enemy.explode_timer = 0
                    else
                        -- 盾牌機器人：盾在左側，擋下由左往右的攻擊（與砲彈同一條規則）
                        local blocked = false
                        if enemy.type_id == "SHIELD_ROBOT" and enemy.shield_raised and L.vx > 0 then
                            local sx = enemy.x + (enemy.shield_offset_x or 0)
                            local st = enemy.y + (enemy.shield_offset_y or 0)
                            if bot >= st and top <= st + (enemy.shield_height or 0) then
                                blocked = true
                                self:addHitSpark(sx + (enemy.shield_width or 0), L.y)
                            end
                        end
                        if not blocked then
                            enemy.hp = enemy.hp - L.damage
                            enemy.hit_shake_timer = 0.3
                            enemy.hit_shake_offset_x = 0
                            self:addHitSpark(math.max(x0, math.min(enemy.x, x1)), L.y)
                            if enemy.hp <= 0 and not enemy.is_exploding then
                                enemy.is_exploding = true
                                enemy.exploding_frame_index = 0
                                enemy.exploding_frame_timer = 0
                                self.enemy_explosion_triggered = true
                            end
                        end
                    end
                end
            end
        end

        -- 飛太遠或飛出畫面就消失
        local screen_x = L.x - (self.camera_x or 0)
        if L.travelled >= L.max_range or screen_x > 400 or screen_x + L.length < 0 then
            table.remove(self.player_lasers, i)
        end
    end
end

-- [[ CANON3 範圍爆炸 ]] 在 (x,y) 引爆：範圍內所有存活敵人受傷 + 一次視覺爆炸。
-- 以「敵人中心與爆心的距離」判定，不用 AABB —— 圓形範圍比較符合爆炸的直覺。
-- 直擊的那隻已經吃過直擊傷害，這裡的範圍傷害會再疊加（＝直擊比擦到更痛，合理）。
function EntityController:triggerBlast(x, y, radius, damage)
    if not (radius and radius > 0) then return end
    damage = damage or 0

    for _, enemy in ipairs(self.enemies or {}) do
        if enemy.is_alive then
            local ex = enemy.x + (enemy.width or 0) / 2
            local ey = enemy.y + (enemy.height or 0) / 2
            local dx, dy = ex - x, ey - y
            if (dx * dx + dy * dy) <= radius * radius then
                -- 地雷被波及 → 連鎖引爆（沿用既有的觸發機制）
                if enemy.attack_type == "EXPLODE" and not enemy.is_triggered then
                    enemy.is_triggered = true
                    enemy.explode_timer = 0
                else
                    enemy.hp = enemy.hp - damage
                    enemy.hit_shake_timer = 0.3
                    enemy.hit_shake_offset_x = 0
                    if enemy.hp <= 0 and not enemy.is_exploding then
                        enemy.is_exploding = true
                        enemy.exploding_frame_index = 0
                        enemy.exploding_frame_timer = 0
                        self.enemy_explosion_triggered = true
                    end
                end
            end
        end
    end

    self:addBlastVisual(x, y)
    if _G.SoundManager and _G.SoundManager.playExplode then _G.SoundManager.playExplode() end
    print(string.format("LOG: blast at (%d,%d) r=%d dmg=%d", math.floor(x), math.floor(y), radius, damage))
end

-- [[ S3 ]] 找出機體附近可接管的場景武器（水平距離內）
function EntityController:weaponNear(mx, range)
    for _, w in ipairs(self.weapons or {}) do
        if math.abs(w.x - mx) <= (range or 40) then return w end
    end
    return nil
end

-- [[ S3 ]] 場景武器（砲台）依仰角發射玩家子彈（朝右上）
function EntityController:fireSceneWeapon(w)
    if not w then return end
    local rad = math.rad(w.angle or 30)
    -- 對齊機體 CANON 的速度尺度：base(2.0) × 倍率
    local speed = (self.player_move_speed or 2.0) * (w.speed_mult or 30)
    local dir_x, dir_y = math.cos(rad), -math.sin(rad)
    local vx = dir_x * speed
    local vy = dir_y * speed
    -- [[ 美術 ]] 由旋轉後的槍口射出：框底貼地、水平置中於 w.x，軸心 + 方向 × 砲管長
    local fw, fh = (w.frame_w or 32), (w.frame_h or 32)
    local pivot_x = w.x - fw / 2 + (w.pivot_x or 10)
    local pivot_y = self.ground_y - fh + (w.pivot_y or 10)
    local blen = w.barrel_len or 21
    self:addPlayerProjectile(pivot_x + dir_x * blen, pivot_y + dir_y * blen,
                             vx, vy, w.damage or 10, w.grav_mult or 0.3, w.bullet_size or 8)
end

function EntityController:updateAll(dt, mech_x, mech_y, mech_width, mech_height, mech_stats)
    local mech_damage_taken = 0

    -- [[ 運送目標 ]] 2026-08-09：浮空上下飄 + sprite sheet 換幀 + 放置後往左上飛走。
    -- （取代舊的「擴散圓環」特效，那段已移除。）
    for _, target in ipairs(self.delivery_targets or {}) do
        -- sprite sheet 換幀（飛走時也繼續播，看起來還在運作）
        if target.sheet then
            target.frame_timer = (target.frame_timer or 0) + dt
            if target.frame_timer >= TARGET_FRAME_TIME then
                target.frame_timer = 0
                local n = target.sheet:getLength() or 1
                target.frame = ((target.frame or 1) % n) + 1
            end
        end

        if target.fly_timer then
            -- 放上箱子後：往左上加速飛出畫面上緣才消失
            target.fly_timer = target.fly_timer + dt
            target.fly_vy = (target.fly_vy or TARGET_FLY_VY) - TARGET_FLY_ACC * dt
            target.x = target.x + TARGET_FLY_VX * dt
            target.y = target.y + target.fly_vy * dt
            -- ★ 箱子跟著一起飛：每幀重新對齊（不必記位移，也不會累積誤差）
            for _, s in ipairs(target.placed_stones or {}) do
                s.x, s.y = self:stoneRestPos(target, s)
            end
            -- 整個目標（含上方的箱子）都離開畫面上緣才算結束；
            -- MAX_T 只是保險，正常情況會先被上面那個條件終止。
            if (target.y + target.height) < 0 or target.fly_timer >= TARGET_FLY_MAX_T then
                target.fly_timer = nil
                target.is_completed = true      -- is_completed 之後就不再繪製
                -- 目標消失時，被帶走的箱子一起消失
                for _, s in ipairs(target.placed_stones or {}) do
                    s.is_hidden = true
                end
            end
        else
            -- 平常：以 base_y 為中心上下飄
            target.bob_t = (target.bob_t or 0) + dt * TARGET_BOB_SPEED
            target.y = (target.base_y or target.y) + math.sin(target.bob_t) * TARGET_BOB_AMP
        end
    end

    -- [[ 前景層 ]] 裝飾動圖換幀（4 幀循環）
    if self.foregrounds and #self.foregrounds > 0 then
        self.fg_timer = (self.fg_timer or 0) + dt
        if self.fg_timer >= (self.fg_frame_delay or 0.40) then
            self.fg_timer = 0
            local n = (self.fg_table and self.fg_table:getLength()) or 4
            self.fg_frame = ((self.fg_frame or 1) % n) + 1
        end
    end

    -- [[ S4 ]] 敵人重生器：計時到且未達上限 → 於重生點生成新敵人
    for _, r in ipairs(self.respawners or {}) do
        if (not r.max) or r.spawned < r.max then
            r.timer = r.timer - dt
            if r.timer <= 0 then
                r.timer = r.interval
                local e = Enemy:init(r.x, r.y, r.type, self.ground_y)
                table.insert(self.enemies, e)
                r.spawned = r.spawned + 1
                print("LOG: respawned " .. tostring(r.type) .. " (" .. r.spawned .. ")")
            end
        end
    end

    -- [[ S5 護送戰 ]] 更新 NPC：MOVE=自走向目標；HOLD=定點小移動並計時
    if self.npc and not self.npc.is_dead and not self.npc.reached_goal and not self.npc.protect_done then
        local npc = self.npc

        -- [[ S5 護送 ]] NPC 走太前面時停下來等玩家（2026-08-06 加入）。
        -- 只在「NPC 領先玩家超過 wait_distance」時停；玩家跑到前面時 NPC 照走。
        -- 每個 NPC 可用 scene.npc.wait_distance 覆寫；不設就用預設值。
        npc.waiting = false
        if npc.mode == "MOVE" then
            local lead = npc.x - (mech_x or npc.x)
            if lead > (npc.wait_distance or NPC_WAIT_DISTANCE) then
                npc.waiting = true
            end
        end

        -- [[ 美術 ]] 走路動畫換幀；停下來等的時候不換幀（否則會原地踏步看起來像卡住）
        if self.npc_walk and not npc.waiting then
            npc.frame_timer = (npc.frame_timer or 0) + dt
            if npc.frame_timer >= (npc.frame_delay or 0.16) then
                npc.frame_timer = 0
                local n = self.npc_walk:getLength() or 2
                npc.frame = ((npc.frame or 1) % n) + 1
            end
        end
        if npc.hp <= 0 then
            npc.is_dead = true
        elseif npc.mode == "MOVE" then
            if not npc.waiting then
                npc.x = npc.x + (npc.speed or 12) * dt
                if npc.goal_x and npc.x >= npc.goal_x then npc.x = npc.goal_x; npc.reached_goal = true end
            end
        else -- HOLD
            npc.x = npc.x + npc.dir * (npc.speed or 12) * dt
            if npc.x > npc.origin_x + (npc.range or 30) then npc.dir = -1
            elseif npc.x < npc.origin_x - (npc.range or 30) then npc.dir = 1 end
            npc.timer = npc.timer + dt
            if npc.timer >= (npc.duration or 20) then npc.protect_done = true end
        end
    end

    -- 1. 更新敵人 (讓敵人移動和射擊)
    for i, enemy in ipairs(self.enemies) do
        if enemy.is_alive then
            enemy:update(dt, mech_x, mech_y, mech_width, mech_height, self)

            -- [[ S6 BOSS ]] 由敵人自行判定的傷害（如 BOSS 雷射光束命中）在此收回累加
            if enemy.pending_mech_damage and enemy.pending_mech_damage > 0 then
                mech_damage_taken = mech_damage_taken + enemy.pending_mech_damage
                enemy.pending_mech_damage = 0
            end

            -- 檢查敵人與機甲碰撞 (扣 HP 邏輯)
            if self:checkMechCollision(mech_x, mech_y, mech_width, mech_height, enemy.x, enemy.y, enemy.width, enemy.height) then
                -- 特殊處理：地雷被玩家踩到時觸發
                if enemy.attack_type == "EXPLODE" and not enemy.is_triggered then
                    enemy.is_triggered = true
                    enemy.explode_timer = 0
                    print("LOG: Mine triggered by player!")
                end
                
                if enemy.attack_type == "CONTACT" then
                    -- 接觸傷害（一次性）
                    if not enemy.has_hit_player then
                        mech_damage_taken = mech_damage_taken + enemy.attack
                        enemy.has_hit_player = true
                    end
                elseif enemy.attack_type == "EXPLODE" then
                    -- 爆炸型敵人：只在爆炸時造成傷害
                    if enemy.is_exploded and not enemy.has_applied_explode_damage then
                        local distance = math.sqrt((mech_x - enemy.x)^2 + (mech_y - enemy.y)^2)
                        if distance < enemy.explode_radius then
                            mech_damage_taken = mech_damage_taken + enemy.explode_damage
                        end
                        enemy.has_applied_explode_damage = true
                    end
                else
                    -- 持續傷害
                    mech_damage_taken = mech_damage_taken + enemy.attack * dt
                end
            else
                enemy.has_hit_player = false  -- 離開碰撞範圍後重置
            end
            
            -- 檢查 sword 敵人的劍揮擊
            if enemy.attack_type == "SWING SWORD" and enemy.sword_swinging then
                -- 計算劍的位置（簡化為矩形區域）
                -- ★ 軸心與劍長一律讀 enemy_data，與 entity_enemy.lua 的繪製端同一組欄位，
                --   否則會出現「看起來砍到卻沒扣血」（2026-08-10 換圖時修）
                local ed = EnemyData[enemy.type_id] or {}
                local sword_length = ed.sword_length or 30
                local sword_x = enemy.x + enemy.width / 2 + (ed.sword_pivot_offset_x or 0)
                local sword_y = enemy.y + enemy.height / 2 + (ed.sword_pivot_offset_y or 0)
                
                -- 劍的角度決定攻擊範圍
                local angle_rad = math.rad(enemy.sword_angle)
                local sword_end_x = sword_x + math.cos(angle_rad) * sword_length
                local sword_end_y = sword_y + math.sin(angle_rad) * sword_length
                
                -- 簡化碰撞：檢查劍尖是否在機甲範圍內
                if sword_end_x >= mech_x and sword_end_x <= mech_x + mech_width and
                   sword_end_y >= mech_y and sword_end_y <= mech_y + mech_height then
                    if not enemy.sword_has_hit then
                        mech_damage_taken = mech_damage_taken + enemy.attack
                        enemy.sword_has_hit = true
                    end
                else
                    enemy.sword_has_hit = false
                end
            end
            
            -- 檢查地雷爆炸
            if enemy.attack_type == "EXPLODE" and enemy.is_exploded and not enemy.has_applied_explode_damage then
                local distance = math.sqrt((mech_x - enemy.x)^2 + (mech_y - enemy.y)^2)
                if distance < enemy.explode_radius then
                    mech_damage_taken = mech_damage_taken + enemy.explode_damage
                end
                enemy.has_applied_explode_damage = true  -- 只應用一次傷害
                -- 不要立即設置 is_alive = false，讓動畫播放完畢
            end
        end
    end

    -- 2. 更新砲彈 (處理物理與碰撞)
    for i = #self.projectiles, 1, -1 do
        local p = self.projectiles[i]
        if p.active then
            p:update(dt, self.GRAVITY, self)  -- 傳入 entity_controller

            -- [[ CANON3 ]] 砲彈在 update 中因撞地而失效 → 在落點引爆
            -- （命中敵人的引爆在下方的命中分支處理）
            if not p.active then
                if p.blast_radius then
                    self:triggerBlast(p.x, p.y, p.blast_radius, p.blast_damage)
                    p.blast_radius = nil   -- 防止同一發重複引爆
                else
                    self:addHitSpark(p.x, p.y)   -- [[ 命中特效 ]] 打到地形
                end
            end

            -- 檢查敵人砲彈是否擊中機甲
            if not p.is_player_bullet and self:checkMechCollision(mech_x, mech_y, mech_width, mech_height, p.x, p.y, p.width, p.height) then
                mech_damage_taken = mech_damage_taken + p.damage
                p.active = false -- 擊中後銷毀
                self:addHitSpark(p.x, p.y)   -- [[ 命中特效 ]]
            end
            
            -- 檢查玩家砲彈是否擊中敵人
            if p.is_player_bullet then
                for _, enemy in ipairs(self.enemies) do
                    if enemy.is_alive and self:checkMechCollision(enemy.x, enemy.y, enemy.width, enemy.height, p.x, p.y, p.width, p.height) then
                        -- 特殊處理：地雷被砲彈擊中時觸發
                        if enemy.attack_type == "EXPLODE" and not enemy.is_triggered then
                            enemy.is_triggered = true
                            enemy.explode_timer = 0  -- 重置計時器開始計數
                            p.active = false
                            print("LOG: Mine triggered by projectile!")
                            break
                        end
                        
                        -- 盾牌機器人的特殊邏輯
                        local shield_blocked = false
                        if enemy.type_id == "SHIELD_ROBOT" and enemy.shield_raised then
                            -- 盾牌在敵人左邊，阻擋從左邊來的子彈
                            local shield_x = enemy.x + enemy.shield_offset_x
                            local shield_right = shield_x + enemy.shield_width
                            local shield_top = enemy.y + enemy.shield_offset_y
                            local shield_bottom = shield_top + enemy.shield_height
                            
                            -- 判斷子彈是否在盾牌範圍內
                            if p.x >= shield_x and p.x <= shield_right and
                               p.y >= shield_top and p.y <= shield_bottom then
                                -- 子彈在盾牌範圍內，檢查擊中位置
                                -- 從左邊擊中時被擋（子彈向右移動 vx > 0）
                                if p.vx > 0 then
                                    p.active = false  -- 盾牌吸收子彈，不造成傷害
                                    shield_blocked = true
                                    self:addHitSpark(p.x, p.y)   -- [[ 命中特效 ]] 被盾擋下也有回饋
                                    print("LOG: Shield blocks projectile from left!")
                                end
                                -- 從其他方向（右邊、上方、下方）擊中時造成傷害，繼續進行
                            end
                        end
                        
                        -- 若盾牌未阻擋，則造成傷害
                        if not shield_blocked then
                            -- 擊中敵人
                            enemy.hp = enemy.hp - p.damage
                            p.active = false -- 砲彈銷毀
                            self:addHitSpark(p.x, p.y)   -- [[ 命中特效 ]]

                            -- [[ CANON3 ]] 直擊後在命中點引爆，波及周圍敵人
                            if p.blast_radius then
                                local br, bd = p.blast_radius, p.blast_damage
                                p.blast_radius = nil   -- 先清掉,避免 triggerBlast 內的連鎖再進來
                                self:triggerBlast(p.x, p.y, br, bd)
                            end

                            -- 播放擊中音效
                            if _G.SoundManager and _G.SoundManager.playHit then
                                _G.SoundManager.playHit()
                            end
                            
                            -- 敵人受擊震動
                            enemy.hit_shake_timer = 0.3
                            enemy.hit_shake_offset_x = 0
                            
                            print("LOG: Player projectile hit enemy! HP=" .. math.floor(enemy.hp))
                            
                            if enemy.hp <= 0 and not enemy.is_exploding then
                                enemy.is_exploding = true
                                enemy.exploding_frame_index = 0
                                enemy.exploding_frame_timer = 0
                                if _G.SoundManager and _G.SoundManager.playExplode then
                                    _G.SoundManager.playExplode()
                                end
                                -- 設置敵人爆炸標志
                                self.enemy_explosion_triggered = true
                                print("LOG: Enemy killed by player projectile, starting explosion animation")
                            end
                        end
                        break
                    end
                end
            end
            
        else
            table.remove(self.projectiles, i) -- 移除不活躍的砲彈
        end
    end

    -- [[ CANON3 ]] 更新爆炸動畫（每幀 0.05 秒，播完移除）
    if self.blasts and #self.blasts > 0 then
        local n = self.blast_sheet and self.blast_sheet:getLength() or 3
        for i = #self.blasts, 1, -1 do
            local b = self.blasts[i]
            b.timer = b.timer + dt
            if b.timer >= 0.05 then
                b.timer = 0
                b.frame = b.frame + 1
                if b.frame > n then table.remove(self.blasts, i) end
            end
        end
    end

    -- [[ 雷射槍 ]] 光束前進 + 貫穿命中
    self:updatePlayerLasers(dt)

    -- [[ 命中特效 ]] 更新火花（幀數：有圖就用圖的長度，沒圖用程式繪製的幀數）
    if self.hit_sparks and #self.hit_sparks > 0 then
        local n = (self.spark_sheet and self.spark_sheet:getLength()) or HIT_SPARK_FRAMES
        for i = #self.hit_sparks, 1, -1 do
            local sp = self.hit_sparks[i]
            sp.timer = sp.timer + dt
            if sp.timer >= HIT_SPARK_FRAME_TIME then
                sp.timer = 0
                sp.frame = sp.frame + 1
                if sp.frame > n then table.remove(self.hit_sparks, i) end
            end
        end
    end

    -- 3. 更新石頭
    for i = #self.stones, 1, -1 do
        local stone = self.stones[i]
        stone:update(dt, self.GRAVITY, self)  -- 傳入 entity_controller
        
        -- 檢查石頭是否與敵人碰撞（造成傷害）
        if not stone.is_grabbed and (stone.vx ~= 0 or stone.vy ~= 0) then
            for _, enemy in ipairs(self.enemies) do
                if enemy.is_alive and self:checkMechCollision(enemy.x, enemy.y, enemy.width, enemy.height, stone.x, stone.y, stone.width, stone.height) then
                    -- 特殊處理：地雷被石頭擊中時觸發
                    if enemy.attack_type == "EXPLODE" and not enemy.is_triggered then
                        enemy.is_triggered = true
                        enemy.explode_timer = 0  -- 重置計時器開始計數
                        print("LOG: Mine triggered by stone!")
                        break
                    end
                    
                    -- 石頭砸到敵人
                    enemy.hp = enemy.hp - stone.damage
                    enemy.hit_shake_timer = 0.3
                    enemy.hit_shake_offset_x = 0
                    
                    -- 播放擊中音效
                    if _G.SoundManager and _G.SoundManager.playHit then
                        _G.SoundManager.playHit()
                    end
                    
                    print("LOG: Stone hit enemy! HP=" .. math.floor(enemy.hp))
                    
                    if enemy.hp <= 0 and not enemy.is_exploding then
                        enemy.is_exploding = true
                        enemy.exploding_frame_index = 0
                        enemy.exploding_frame_timer = 0
                        if _G.SoundManager and _G.SoundManager.playExplode then
                            _G.SoundManager.playExplode()
                        end
                        -- 設置敵人爆炸標志
                        if self then
                            self.enemy_explosion_triggered = true
                        end
                        print("LOG: Enemy killed by stone, starting explosion animation")
                    end
                    
                    -- 石頭減速但繼續受重力影響
                    stone.vx = stone.vx * 0.5  -- 減少水平速度
                    -- 不強制設定 vy = 0，讓石頭繼續受重力影響
                    break
                end
            end
        end
    end
    
    return mech_damage_taken
end

-- 簡易 AABB 碰撞檢查 (通用)
function EntityController:checkMechCollision(mech_x, mech_y, mech_w, mech_h, entity_x, entity_y, entity_w, entity_h)
    return mech_x < entity_x + entity_w and
           mech_x + mech_w > entity_x and
           mech_y < entity_y + entity_h and
           mech_y + mech_h > entity_y
end

-- 檢查武器零件是否擊中敵人，並造成傷害
-- weapon_parts: 陣列，每個元素包含 {x, y, w, h, attack}
function EntityController:checkWeaponCollision(weapon_parts)
    local damage_dealt = 0
    
    for _, weapon in ipairs(weapon_parts or {}) do
        if not weapon.x or not weapon.y or not weapon.w or not weapon.h then
            goto next_weapon
        end
        
        for i, enemy in ipairs(self.enemies) do
            if enemy.is_alive and not enemy.is_exploding then
                -- AABB 碰撞檢查
                local collision = weapon.x < enemy.x + enemy.width and
                                 weapon.x + weapon.w > enemy.x and
                                 weapon.y < enemy.y + enemy.height and
                                 weapon.y + weapon.h > enemy.y
                
                if collision then
                    -- 擊中敵人，扣除 HP
                    local attack = weapon.attack or 0
                    enemy.hp = enemy.hp - attack
                    damage_dealt = damage_dealt + attack
                    
                    -- 播放擊中音效
                    if _G.SoundManager and _G.SoundManager.playHit then
                        _G.SoundManager.playHit()
                    end
                    
                    -- 調試輸出：顯示被攻擊敵人的 HP
                    print("LOG: Enemy hit! Type=" .. (enemy.type_id or "unknown") .. ", HP=" .. math.floor(enemy.hp) .. "/" .. (EnemyData[enemy.type_id] and EnemyData[enemy.type_id].hp or "?") .. ", Damage=" .. attack)
                    
                    -- 受擊效果：震動
                    enemy.hit_shake_timer = 0.3  -- 0.3 秒震動（增加持續時間）
                    enemy.hit_shake_offset_x = 0
                    
                    if enemy.hp <= 0 and not enemy.is_exploding then
                        -- [[ FIX ]] 近戰擊殺也要走爆炸狀態機（與砲彈擊殺一致），
                        -- 而非立即 is_alive=false——否則沒有爆炸特效，
                        -- 且最後一敵被近戰擊殺時會瞬間跳結算
                        enemy.is_exploding = true
                        enemy.exploding_frame_index = 0
                        enemy.exploding_frame_timer = 0
                        if _G.SoundManager and _G.SoundManager.playExplode then
                            _G.SoundManager.playExplode()
                        end
                        self.enemy_explosion_triggered = true
                        print("LOG: Enemy killed by melee weapon, starting explosion animation")
                    end
                end
            end
        end
        
        ::next_weapon::
    end
    
    return damage_dealt
end


-- [[ 前景層 ]] 畫在「機體之上、UI 之下」：由 state_mission 在繪製機甲後、繪製 HUD/面板前呼叫。
-- 會擋住玩家（營造前後景深），但不會蓋到操作介面。
function EntityController:drawForeground(camera_x)
    if not (self.foregrounds and #self.foregrounds > 0) then return end
    if not self.fg_tried then
        self.fg_tried = true
        local okf, tbl = pcall(function() return playdate.graphics.imagetable.new("images/forground") end)
        if okf and tbl then self.fg_table = tbl end
    end
    if not self.fg_table then return end
    local img = self.fg_table:getImage(self.fg_frame or 1)
    if not img then return end
    local iw, ih = img:getSize()
    for _, f in ipairs(self.foregrounds) do
        local sx = f.x - camera_x
        if sx > -iw and sx < 400 + iw then
            -- y 省略＝貼地（圖底部對齊地面線）；有給 y 則視為相對地面的偏移
            local dy = (self.ground_y - ih) + (f.y or 0)
            pcall(function() img:draw(sx - iw / 2, dy) end)
        end
    end
end

-- [[ 美術 ]] 目標標記：bunker 圖 + 上方 GOAL 字樣。
-- **REACH 目標點與護送終點 bunker 功能相同**（走到定點就達標），所以暫時共用同一張圖
-- （2026-08-06 決定；原本 REACH 是程式畫的旗桿 + 三角旗）。
-- 日後要各自專屬圖時，把 "images/bunker" 改成參數，兩個呼叫點各傳各的即可。
function EntityController:drawGoalMarker(screen_x, ground_y)
    if not self.bunker_tried then
        self.bunker_tried = true
        local okb, img = pcall(function() return playdate.graphics.image.new("images/bunker") end)
        if okb and img then self.bunker_img = img end
    end
    local bh = 32
    if self.bunker_img then
        local bw
        bw, bh = self.bunker_img:getSize()
        pcall(function() self.bunker_img:draw(screen_x - bw / 2, ground_y - bh) end)
    else
        -- 載入失敗時的白底黑框佔位
        gfx.setColor(gfx.kColorWhite); gfx.fillRect(screen_x - 16, ground_y - 32, 32, 32)
        gfx.setColor(gfx.kColorBlack); gfx.drawRect(screen_x - 16, ground_y - 32, 32, 32)
    end
    gfx.setColor(gfx.kColorBlack)
    local tw = gfx.getTextSize("GOAL")
    gfx.drawText("GOAL", screen_x - tw / 2, ground_y - bh - 14)
end

function EntityController:draw(camera_x)
    self.camera_x = camera_x   -- [[ S6 ]] 供 BOSS 判斷是否在畫面內（更新時取用上一幀的值）
    local ground_y = self.ground_y
    gfx.setColor(gfx.kColorBlack)
    
    -- [[ 天空層 ]] 最遠層：畫在所有背景之前，橫向平鋪，視差最慢（scene.sky）
    if self.sky then
        local sw = self.sky_w or 400
        -- 取模讓平鋪起點永遠落在畫面左緣外，最多畫 2 次
        local sx = -(((camera_x * (self.sky_parallax or 0.1)) % sw))
        while sx < 400 do
            local dx = sx
            pcall(function() self.sky:draw(dx, self.sky_y or 0) end)
            sx = sx + sw
        end
    end

    -- 繪製背景（先後景，再前景），背景隨畫面反向捲動；不重複平鋪
    if self.backgrounds and #self.backgrounds > 0 then
        local sorted = { }
        for _, bg in ipairs(self.backgrounds) do table.insert(sorted, bg) end
        table.sort(sorted, function(a, b) return (a.layer or 0) < (b.layer or 0) end)
        for _, bg in ipairs(sorted) do
            local parallax = (bg.layer == 1) and 0.6 or 0.3  -- 前景較快，後景較慢
            local screen_x = bg.x - (camera_x * parallax)
            local screen_y = bg.y
            if bg.image then
                -- 單次繪製，不進行重複平鋪
                pcall(function() bg.image:draw(screen_x, screen_y) end)
            end
        end
    end
    
    -- 繪製地形
    -- [[ 美術 ]] 地面＝純黑填充 + 沿地形線的「表面層」（白色帶狀，厚度 SURFACE_T）。
    -- 表面層沿著每段地形的線平移出等厚度的四邊形，斜坡也會自動貼合。
    local SURFACE_T = self.surface_thickness or 6
    for _, terrain in ipairs(self.terrain) do
        local screen_x = terrain.x - camera_x

        -- 只繪製在畫面內的地形；[[ S2 ]] pit（懸崖空洞）不畫→呈現視覺缺口
        if terrain.type ~= "pit" and screen_x < 400 and screen_x + 64 > 0 then
            local x1, y1, x2, y2 = self:getTerrainPoints(terrain.type, screen_x, ground_y, terrain.height_offset)
            local s1, s2 = y1 + SURFACE_T, y2 + SURFACE_T   -- 表面層下緣

            -- 1) 表面層以下：純黑填滿至畫面底部（遮住背景）
            gfx.setColor(gfx.kColorBlack)
            gfx.fillTriangle(x1, s1, x2, s2, x2, 240)
            gfx.fillTriangle(x1, s1, x1, 240, x2, 240)

            -- 2) 表面層：先填白（不透光，遮住背景），再疊 dither 黑點＝1-bit 的灰
            gfx.setColor(gfx.kColorWhite)
            gfx.fillTriangle(x1, y1, x2, y2, x2, s2)
            gfx.fillTriangle(x1, y1, x1, s1, x2, s2)
            gfx.setColor(gfx.kColorBlack)
            gfx.setDitherPattern(self.surface_dither or 0.5, gfx.image.kDitherTypeBayer8x8)
            gfx.fillTriangle(x1, y1, x2, y2, x2, s2)
            gfx.fillTriangle(x1, y1, x1, s1, x2, s2)

            -- 3) 表面層上下緣的線（讓厚度看得出來）
            gfx.setColor(gfx.kColorBlack)
            gfx.drawLine(x1, y1, x2, y2)
            gfx.drawLine(x1, s1, x2, s2)
        end
    end
    gfx.setColor(gfx.kColorBlack)

    -- 繪製障礙物
    for i, obs in ipairs(self.obstacles) do
        
        if not obs then goto next_obstacle end 
        
        local obs_width = obs.width or 0 
        local obs_height = obs.height or 0
        local obs_x = obs.x or 0

        local obs_screen_x = obs_x - camera_x
        local obs_y = ground_y - obs_height

        if obs_screen_x < 400 and obs_screen_x + obs_width > 0 then
            if obs.image then
                -- 繪製圖片
                pcall(function() obs.image:draw(obs_screen_x, obs_y) end)
            else
                -- 備用：繪製方塊
                gfx.setColor(gfx.kColorBlack)
                gfx.fillRect(obs_screen_x, obs_y, obs_width, obs_height)
            end
        end
        
        ::next_obstacle::
    end
    
    -- 繪製敵人
    for _, enemy in ipairs(self.enemies) do
        enemy:draw(camera_x)
    end

    -- [[ S5/美術 ]] 護送目標 bunker：由場景資料 scene.bunker = { x } 指定（非自動跟著 goal_x，
    -- 因為有些場景的終點是傳送點而不是 bunker）。上方顯示 GOAL 字樣。
    if self.bunker and self.bunker.x then
        local gx = self.bunker.x - camera_x
        if gx > -50 and gx < 450 then
            self:drawGoalMarker(gx, ground_y)
        end
    end

    -- [[ S5 護送戰 ]] 繪製 NPC（白底黑框 + HP 條）與 REACH 目標旗標
    if self.npc and not self.npc.is_dead then
        local npc = self.npc
        local sx = npc.x - camera_x
        if sx > -30 and sx < 430 then
            local top = ground_y - npc.height
            -- [[ 美術 ]] npc_walk 動畫；載入失敗時退回白底黑框佔位
            local drawn = false
            if self.npc_walk then
                local img = self.npc_walk:getImage(npc.frame or 1)
                if img then
                    pcall(function() img:draw(sx - npc.width / 2, top) end)
                    drawn = true
                end
            end
            if not drawn then
                gfx.setColor(gfx.kColorWhite); gfx.fillRect(sx - npc.width/2, top, npc.width, npc.height)
                gfx.setColor(gfx.kColorBlack); gfx.drawRect(sx - npc.width/2, top, npc.width, npc.height)
            end
            gfx.setColor(gfx.kColorBlack)
            local ratio = math.max(0, math.min(1, npc.hp / (npc.max_hp or 1)))
            -- HP 條寬度跟著圖寬走（換圖只要改 npc.width，這裡自動對位）
            local bar_w = npc.width
            local bar_x = sx - math.floor(bar_w / 2)
            gfx.drawRect(bar_x, top - 6, bar_w, 4)
            gfx.fillRect(bar_x, top - 6, math.floor(bar_w * ratio), 4)
            -- HOLD 模式顯示剩餘保護時間（貼在 HP 條右端外側）
            if npc.mode ~= "MOVE" then
                local remain = math.max(0, (npc.duration or 20) - (npc.timer or 0))
                gfx.drawText(string.format("%.0f", remain), bar_x + bar_w + 2, top - 12)
            elseif npc.waiting then
                -- [[ S5 護送 ]] 停下來等玩家時給明確回饋，否則會被誤認為卡住。
                -- 白底黑字（NPC 可能站在深色背景前，見 ArtAssets 的天空層可讀性規則）。
                -- 文字寬 68px > NPC 圖寬 36px，會左右各溢出 16px；置中對齊 NPC 中心即可。
                local wt = "PROTECT"
                local tw, th = gfx.getTextSize(wt)
                gfx.setColor(gfx.kColorWhite)
                gfx.fillRect(sx - tw / 2 - 2, top - 22, tw + 4, (th or 12) + 4)
                gfx.setColor(gfx.kColorBlack)
                gfx.drawText(wt, sx - tw / 2, top - 20)
            end
        end
    end
    -- [[ S5 ]] REACH 目標點：與 bunker 共用同一個標記（功能相同＝走到定點就達標）
    if self.reach and self.reach.x then
        local fx = self.reach.x - camera_x
        if fx > -50 and fx < 450 then
            self:drawGoalMarker(fx, ground_y)
        end
    end

    -- [[ S1/美術 ]] 傳送點（本場景出口）：arrow-table-32-32.png 三幀循環，每幀 0.5 秒
    if self.teleport and self.teleport.x then
        local tx = self.teleport.x - camera_x
        if tx > -40 and tx < 440 then
            if not self.arrow_tried then
                self.arrow_tried = true
                local oka, tbl = pcall(function() return playdate.graphics.imagetable.new("images/arrow") end)
                if oka and tbl then self.arrow_table = tbl end
            end
            if self.arrow_table then
                local n = self.arrow_table:getLength() or 3
                local idx = (math.floor(playdate.getCurrentTimeMilliseconds() / 500) % n) + 1
                local img = self.arrow_table:getImage(idx)
                if img then
                    local iw, ih = img:getSize()
                    pcall(function() img:draw(tx - iw / 2, ground_y - ih - 8) end)
                end
            else
                -- 佔位（載入失敗時）
                gfx.setColor(gfx.kColorBlack)
                gfx.fillTriangle(tx - 8, ground_y - 30, tx - 8, ground_y - 14, tx + 8, ground_y - 22)
            end
        end
    end

    -- [[ S3 場景武器 ]] 砲台：底座（第1格）+ 繞軸心旋轉的砲管（第2格，靜止朝右）
    if (self.weapons and #self.weapons > 0) and not self.turret_sheet_tried then
        self.turret_sheet_tried = true
        local okt, tbl = pcall(function() return playdate.graphics.imagetable.new("images/turret") end)
        if okt and tbl then
            self.turret_sheet = tbl
            -- 砲管裁成「軸心置中」的小圖，供 drawRotated 繞軸心旋轉
            local src = tbl:getImage(2)
            if src then
                local size = 64
                local okb, buf = pcall(function() return playdate.graphics.image.new(size, size) end)
                if okb and buf then
                    playdate.graphics.pushContext(buf)
                    playdate.graphics.clear(playdate.graphics.kColorClear)
                    src:draw(-(10 - size / 2), -(10 - size / 2))   -- pivot(10,10) 移到小圖中心
                    playdate.graphics.popContext()
                    self.turret_barrel_img = buf
                end
            end
        end
    end
    for _, w in ipairs(self.weapons or {}) do
        local sx = w.x - camera_x
        if sx > -40 and sx < 440 then
            local fw, fh = (w.frame_w or 32), (w.frame_h or 32)
            local fx = sx - fw / 2                 -- 32x32 框水平置中於 w.x
            local fy = ground_y - fh               -- 框底貼地
            if self.turret_sheet then
                local base = self.turret_sheet:getImage(1)
                if base then pcall(function() base:draw(fx, fy) end) end
                if self.turret_barrel_img then
                    -- 砲管靜止朝右（0°），仰角往上為正 → drawRotated 用負值（順時針為正）
                    pcall(function()
                        self.turret_barrel_img:drawRotated(fx + (w.pivot_x or 10), fy + (w.pivot_y or 10),
                                                           -(w.angle or 0))
                    end)
                end
            else
                -- 佔位圖形（sprite 載入失敗時的備援）
                local base_y = ground_y - 20
                gfx.setColor(gfx.kColorWhite); gfx.fillRect(sx - 12, base_y, 24, 20)
                gfx.setColor(gfx.kColorBlack); gfx.drawRect(sx - 12, base_y, 24, 20)
                local rad = math.rad(w.angle or 30)
                gfx.setLineWidth(3)
                gfx.drawLine(sx, base_y + 3, sx + math.cos(rad) * 22, base_y + 3 - math.sin(rad) * 22)
                gfx.setLineWidth(1)
            end
        end
    end

    -- 繪製石頭（已放上目標的改由下方的目標迴圈畫，才能疊在目標之上）
    for _, stone in ipairs(self.stones) do
        if not stone.is_placed then stone:draw(camera_x) end
    end
    
    -- 繪製目標物件
    for _, target in ipairs(self.delivery_targets) do
        -- [[ 2026-08-09 移除 ]] 原本這裡有「擴散雙圓環」的放置成功特效，
        -- 已改成目標本身往左上飛走（見 updateAll），故整段刪除。

        if not target.is_completed then  -- 只繪製未完成的目標
            local screen_x = target.x - camera_x
            if screen_x >= -target.width and screen_x <= 400 then
                if target.sheet then
                    -- sprite sheet：目前幀
                    local img = target.sheet:getImage(target.frame or 1)
                    if img then pcall(function() img:draw(screen_x, target.y) end) end
                elseif target.image then
                    -- 繪製圖片
                    pcall(function() target.image:draw(screen_x, target.y) end)
                else
                    -- 備用：繪製黑色方塊
                    gfx.setColor(gfx.kColorBlack)
                    gfx.fillRect(screen_x, target.y, target.width, target.height)
                end
                
                -- 在目標上方10px處繪製閃爍的"TARGET"文字
                local text = "TARGET"
                local text_width = gfx.getTextSize(text)
                local text_x = screen_x + (target.width - text_width) / 2
                local text_y = target.y - 10 - 8  -- 10px + 文字高度
                
                -- 實現閃爍效果（基於全局時間）
                local blink_time = playdate.getElapsedTime and playdate.getElapsedTime() or 0
                if math.floor(blink_time * 2) % 2 == 0 then
                    gfx.setColor(gfx.kColorBlack)
                    gfx.drawText(text, text_x, text_y)
                end

                -- ★ 被帶走的箱子畫在目標**之上**（上面的 stones 迴圈跳過 is_placed，
                --   否則箱子會被 32×32 的目標圖蓋住）
                for _, s in ipairs(target.placed_stones or {}) do
                    if not s.is_hidden then s:draw(camera_x) end
                end
            end
        end
    end
    
    -- 繪製砲彈
    for _, projectile in ipairs(self.projectiles) do
        projectile:draw(camera_x)
    end

    -- [[ CANON3 ]] 範圍爆炸的視覺（沿用 mine_explode 圖表，以爆心置中）
    if self.blast_sheet and self.blasts then
        for _, b in ipairs(self.blasts) do
            local img = self.blast_sheet:getImage(b.frame)
            if img then
                local ok, fw, fh = pcall(function() return img:getSize() end)
                fw = (ok and fw) or 50
                fh = (ok and fh) or 50
                pcall(function() img:draw(b.x - camera_x - fw / 2, b.y - fh / 2) end)
            end
        end
    end

    -- [[ 雷射槍 ]] 玩家光束：白外框 + 黑芯（與 BOSS 雷射同一套畫法，只是短很多）
    for _, L in ipairs(self.player_lasers or {}) do
        local sx = L.x - camera_x
        local ex = sx + L.length
        gfx.setColor(gfx.kColorWhite); gfx.setLineWidth(L.thickness + 4)
        gfx.drawLine(sx, L.y, ex, L.y)
        gfx.setColor(gfx.kColorBlack); gfx.setLineWidth(L.thickness)
        gfx.drawLine(sx, L.y, ex, L.y)
        gfx.setLineWidth(1)
    end

    -- [[ 命中特效 ]] 子彈擊中點的小火花。有圖用圖，沒圖用程式繪製。
    for _, sp in ipairs(self.hit_sparks or {}) do
        local sx = sp.x - camera_x
        if self.spark_sheet then
            local img = self.spark_sheet:getImage(sp.frame)
            if img then
                local ok, fw, fh = pcall(function() return img:getSize() end)
                fw = (ok and fw) or 16
                fh = (ok and fh) or 16
                pcall(function() img:draw(sx - fw / 2, sp.y - fh / 2) end)
            end
        else
            -- 程式繪製：擴散的環 + 四向放射線，逐幀放大。
            -- ★ 每個形狀都畫兩次：先白色粗線當描邊、再黑色細線 —— 這樣在白色天空與
            --   純黑地面上都看得見（單一顏色的話一定會有一種背景吃掉它）。
            local t = (sp.frame - 1) / math.max(1, HIT_SPARK_FRAMES - 1)
            local r = 2 + 8 * t
            local function stroke(w, color)
                gfx.setColor(color)
                gfx.setLineWidth(w)
                gfx.drawCircleAtPoint(sx, sp.y, r)
                for i = 0, 3 do
                    local a = math.rad(i * 90 + 45)
                    local c, s = math.cos(a), math.sin(a)
                    gfx.drawLine(sx + c * (r + 1), sp.y + s * (r + 1),
                                 sx + c * (r + 4), sp.y + s * (r + 4))
                end
            end
            stroke(3, gfx.kColorWhite)   -- 描邊
            stroke(1, gfx.kColorBlack)   -- 本體
            gfx.setLineWidth(1)
        end
    end
end

-- 獲取地形兩端點坐標
function EntityController:getTerrainPoints(terrain_type, screen_x, base_y, height_offset)
    local y_start = base_y + (height_offset or 0)
    local x1, y1, x2, y2 = screen_x, y_start, screen_x + 64, y_start
    
    if terrain_type == "up15" then
        y2 = y_start - 17  -- tan(15°) ≈ 0.27, 64 * 0.27 ≈ 17
    elseif terrain_type == "up30" then
        y2 = y_start - 37  -- tan(30°) ≈ 0.58, 64 * 0.58 ≈ 37
    elseif terrain_type == "up45" then
        y2 = y_start - 64  -- tan(45°) = 1, 64 * 1 = 64
    elseif terrain_type == "down15" then
        y2 = y_start + 17
    elseif terrain_type == "down30" then
        y2 = y_start + 37
    elseif terrain_type == "down45" then
        y2 = y_start + 64
    end
    
    return x1, y1, x2, y2
end

-- 獲取指定X位置的地面高度
function EntityController:getGroundHeight(world_x)
    -- 找到對應的地形單位
    for _, terrain in ipairs(self.terrain) do
        if world_x >= terrain.x and world_x < terrain.x + 64 then
            local base_y = self.ground_y + (terrain.height_offset or 0)
            local relative_x = world_x - terrain.x  -- 在地形單位內的相對位置
            local progress = relative_x / 64  -- 0到1的進度
            
            if terrain.type == "pit" then
                -- [[ S2 懸崖 ]] 空洞：回傳極大值＝此處無地面，機甲不會被夾住而下墜
                return base_y + 10000
            elseif terrain.type == "flat" then
                return base_y
            elseif terrain.type == "up15" then
                return base_y - (17 * progress)
            elseif terrain.type == "up30" then
                return base_y - (37 * progress)
            elseif terrain.type == "up45" then
                return base_y - (64 * progress)
            elseif terrain.type == "down15" then
                return base_y + (17 * progress)
            elseif terrain.type == "down30" then
                return base_y + (37 * progress)
            elseif terrain.type == "down45" then
                return base_y + (64 * progress)
            end
        end
    end
    
    -- 預設返回基準地面高度
    return self.ground_y
end

-- 獲取指定X位置的地形類型
function EntityController:getTerrainType(world_x)
    for _, terrain in ipairs(self.terrain) do
        if world_x >= terrain.x and world_x < terrain.x + 64 then
            return terrain.type
        end
    end
    return "flat"
end

-- 獲取指定X位置的地形角度（度數）
function EntityController:getTerrainAngle(world_x)
    local terrain_type = self:getTerrainType(world_x)
    
    if terrain_type == "up15" then
        return -15
    elseif terrain_type == "up30" then
        return -30
    elseif terrain_type == "up45" then
        return -45
    elseif terrain_type == "down15" then
        return 15
    elseif terrain_type == "down30" then
        return 30
    elseif terrain_type == "down45" then
        return 45
    else
        return 0
    end
end

-- 檢查移動方向是否能爬上斜坡
-- direction: 1=向右, -1=向左
function EntityController:canClimbSlope(world_x, direction, climb_power)
    local terrain_type = self:getTerrainType(world_x)
    
    -- 向右移動時檢查向上斜坡
    if direction > 0 then
        if terrain_type == "up15" and climb_power >= 1 then
            return true
        elseif terrain_type == "up30" and climb_power >= 2 then
            return true
        elseif terrain_type == "up45" and climb_power >= 3 then
            return true
        elseif terrain_type:sub(1, 4) == "down" then
            return true  -- 下坡總是可以走
        elseif terrain_type == "flat" then
            return true
        end
    -- 向左移動時檢查向下斜坡（從左看是上坡）
    elseif direction < 0 then
        if terrain_type == "down15" and climb_power >= 1 then
            return true
        elseif terrain_type == "down30" and climb_power >= 2 then
            return true
        elseif terrain_type == "down45" and climb_power >= 3 then
            return true
        elseif terrain_type:sub(1, 2) == "up" then
            return true  -- 從左往右看的下坡
        elseif terrain_type == "flat" then
            return true
        end
    end
    
    return false
end

-- checkCollision 函式 (用於機甲與場景的垂直/水平碰撞檢查，包含地形)
local function checkCollision(self, target_x, target_y, mech_vy_current, mech_y_old, mech_width, mech_height)
    local mech_left = target_x
    local mech_right = target_x + mech_width
    local mech_top = target_y
    local mech_bottom = target_y + mech_height
    
    local horizontal_block = false
    local final_y_stop = nil
    
    local safe_ground_y = self.ground_y or 240 
    
    -- 1. 檢查地形碰撞
    -- 使用機甲中心點的地面高度，因為機甲會旋轉以匹配斜坡角度
    local center_x = target_x + mech_width / 2
    local terrain_y = self:getGroundHeight(center_x)

    -- [[ BUGFIX 2026-08-08 懸崖 ]] 中心點在 pit 缺口上方時，改用「腳掌左右緣」補判。
    -- 症狀:跳躍距離差一點時，機體右半已經在對岸實地上方，但**中心仍在缺口上**，
    --      於是繼續下墜；等中心越過邊緣才被吸附回地面 → 看起來是「掉下去又彈回來」。
    -- 只在中心無地面時才擴大取樣，所以**斜坡的貼合手感完全不變**（斜坡上中心一定有地面）。
    local PIT_SENTINEL = safe_ground_y + 1000     -- getGroundHeight 對 pit 回傳 base_y + 10000
    if terrain_y >= PIT_SENTINEL then
        local inset = mech_width * FOOT_INSET_RATIO
        local edge_y = math.min(self:getGroundHeight(center_x - inset),
                                self:getGroundHeight(center_x + inset))
        if edge_y < PIT_SENTINEL then terrain_y = edge_y end
    end

    -- 只要機甲底部觸碰或低於地面，就設置停靠點。
    -- ★ 但**吸附幅度有上限**（STEP_UP_MAX）：機體已經掉到地面線以下很多時不該被瞬間彈上去，
    --   那是「掉進懸崖」而不是「落地」，應該繼續往下掉直到判定失敗。
    --   斜坡爬升每幀只差不到 2px，不受影響。
    if mech_bottom >= terrain_y and (mech_bottom - terrain_y) <= STEP_UP_MAX then
        final_y_stop = terrain_y - mech_height
    end
    
    -- 2. 合併障礙物和石頭為檢查列表
    local all_obstacles = {}
    for _, obs in ipairs(self.obstacles) do
        table.insert(all_obstacles, {x = obs.x, width = obs.width, height = obs.height})
    end
    -- 添加石頭作為障礙物（未被抓住且在地面上）
    for _, stone in ipairs(self.stones or {}) do
        if not stone.is_grabbed and stone.is_grounded then
            local stone_height = stone.height
            table.insert(all_obstacles, {x = stone.x, width = stone.width, height = stone_height})
        end
    end

    -- 3. 檢查障礙物碰撞
    for i, obs in ipairs(all_obstacles) do
        
        if not obs then goto next_collision_check end 
        
        local obs_width = obs.width or 0 
        local obs_height = obs.height or 0
        local obs_x = obs.x or 0

        local obs_left = obs_x
        local obs_right = obs_left + obs_width
        local obs_top = safe_ground_y - obs_height 
        local obs_bottom = safe_ground_y          

        -- 廣義重疊檢查 (AABB 碰撞)
        if mech_right > obs_left and mech_left < obs_right and
           mech_bottom > obs_top and mech_top < obs_bottom then
            
            -- 細分碰撞類型
            
            -- **A. 垂直碰撞 (從上方落下)**
            if mech_vy_current >= 0 and mech_y_old + mech_height <= obs_top + 1 and mech_bottom > obs_top then
                
                local potential_y_stop = obs_top - mech_height
                
                if not final_y_stop or potential_y_stop < final_y_stop then 
                    final_y_stop = potential_y_stop
                end
            
            -- **B. 水平碰撞 (移動時撞到)**
            elseif mech_top < obs_bottom and mech_bottom > obs_top + 5 then -- 避免與腳下的物體判斷為水平碰撞
                horizontal_block = true
            end
        end

        ::next_collision_check::
    end
    
    return horizontal_block, final_y_stop
end
EntityController.checkCollision = checkCollision
