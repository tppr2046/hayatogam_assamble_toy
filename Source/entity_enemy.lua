-- entity_enemy.lua — Enemy 類別（敵人 AI/攻擊/移動/繪製）
-- [[ P1 拆檔 ]] 自 module_entities.lua 拆出；由 module_entities.lua（聚合器）載入

import "CoreLibs/graphics"

local gfx = playdate.graphics
local EnemyData = import "enemy_data" -- 確保載入敵人數據
-- Playdate 的 import 同一檔案只載一次、二次 import 拿不到回傳值，
-- 故掛上 _G 供 entity_controller.lua 取用（聚合器保證本檔先載入）
EnemyData = EnemyData or _G.EnemyData or {}
_G.EnemyData = EnemyData

-- [[ ========================================== ]]
-- [[  Enemy 類別 (敵人) ]]
-- [[ ========================================== ]]

Enemy = {}

-- [[ 演出 ]] BOSS 死亡爆炸的長度（秒）與連環爆的間隔（秒）。
-- 一般敵人仍是 exploding_duration = 1.0，只有 BOSS 拉長。
-- ★ 關卡的 BOSS_KILL 判定會等 is_exploding 結束，所以改這裡＝改「爆炸播完才過關」。
local BOSS_DEATH_DURATION = 3.0
local BOSS_DEATH_BURST_INTERVAL = 0.22

function Enemy:init(x, y, type_id, ground_y)
    local data = EnemyData[type_id]
    
    -- 載入敵人圖片或imagetable
    local enemy_img = nil
    local enemy_imagetable = nil
    local img_width = 24
    local img_height = 32
    if data.image then
        -- [[ 2026-08-09 ]] 一律「先試 imagetable、失敗才退回單張圖」。
        -- 舊版寫死只有 JUMP_ENEMY 走 imagetable，DRONE 換成 6 幀動畫後就吃不到；
        -- 改成這樣之後，之後任何敵人要動畫只要放 `-table-寬-高` 的圖即可，不必回來改程式。
        local ok_table, imagetable = pcall(function()
            return playdate.graphics.imagetable.new(data.image)
        end)
        if ok_table and imagetable then
            enemy_imagetable = imagetable
            enemy_img = imagetable:getImage(1)  -- 預設顯示第1幀
        else
            local ok_img, img = pcall(function()
                return playdate.graphics.image.new(data.image)
            end)
            if ok_img and img then enemy_img = img end
        end
        -- 尺寸一律讀「實際會畫出來的那張圖」
        if enemy_img then
            local ok_size, w, h = pcall(function() return enemy_img:getSize() end)
            if ok_size and w and h then
                img_width = w
                img_height = h
            end
        end
    end
    
    local e = {
        x = x,
        y = y,
        type_id = type_id,
        hp = data.hp,
        attack = data.attack,
        width = img_width,
        height = img_height,
        image = enemy_img,  -- 儲存圖片
        imagetable = enemy_imagetable,  -- 動畫用（JUMP_ENEMY 依狀態指定幀；其餘看 anim_fps）
        anim_fps = data.anim_fps,       -- 設了就循環播放 imagetable（見 update）
        anim_frame = 1, anim_timer = 0,
        ground_y = ground_y,
        vx = 1.0, -- 基礎水平速度
        vy = 0,   -- 垂直速度（跳躍用）
        move_dir = 1, -- 1 for right, -1 for left
        is_alive = true,
        is_grounded = true,  -- 是否在地面上
        jump_state = "grounded",  -- "grounded", "jumping", "landing"（用於 JUMP_ENEMY 動畫）
        landing_frame_timer = 0,  -- 著陸幀計時器
        move_timer = 0,
        fire_timer = 0,
        fire_cooldown = 2.0, -- 每 2 秒發射一次
        -- 子彈發射位置偏移
        bullet_offset_x = data.bullet_offset_x or (img_width / 2),
        bullet_offset_y = data.bullet_offset_y or (img_height / 2),
        -- 移動參數
        move_probability = data.move_probability or 0.5,
        move_range = data.move_range or 50,
        move_speed = data.move_speed or 20,
        origin_x = x,  -- 記錄初始位置
        -- 跳躍參數
        jump_velocity = data.jump_velocity or -6.0,
        jump_cooldown = data.jump_cooldown or 2.0,
        jump_horizontal = data.jump_horizontal or 30,
        jump_timer = 0,
        -- sword 參數
        sword_angle = 0,
        sword_swing_cooldown = data.sword_swing_cooldown or 3.0,
        sword_swing_speed = data.sword_swing_speed or 180,
        sword_swing_min = data.sword_swing_min or -45,
        sword_swing_max = data.sword_swing_max or 45,
        sword_timer = 0,
        sword_swinging = false,
        sword_direction = 1,  -- 1=前揮, -1=後揮
        sword_image = nil,  -- 劍圖片（可選）
        -- 地雷參數
        explode_delay = data.explode_delay or 2.0,
        explode_radius = data.explode_radius or 50,
        explode_damage = data.explode_damage or 20,
        is_triggered = false,
        explode_timer = 0,
        is_exploded = false,
        has_applied_explode_damage = false,
        -- 爆炸动画参數
        explode_image_table = nil,  -- 爆炸动画表
        explode_frame_index = 1,    -- 爆炸动画帧数
        explode_frame_timer = 0,    -- 爆炸动画身時間
        explode_frame_duration = 0.1, -- 每帧阻扣時間(秒)
        -- 敵人死亡爆炸狀態
        is_exploding = false,       -- 敵人是否正在爆炸
        exploding_frame_index = 0,  -- 爆炸動畫幀索引
        exploding_frame_timer = 0,  -- 爆炸動畫幀計時器
        exploding_image_table = nil, -- 爆炸動畫表
        exploding_duration = 1.0,   -- 爆炸動畫總時間
        -- 移動類型和攻擊類型
        move_type = data.move_type,
        attack_type = data.attack_type,
        -- 盾牌機器人參數
        shield_raised = data.shield_raised ~= false,  -- 默認舉起
        shield_timer = 0,
        shield_up_duration = data.shield_up_duration or 3.0,
        shield_down_duration = data.shield_down_duration or 2.0,
        shield_width = data.shield_width or 16,
        shield_height = data.shield_height or 20,
        shield_offset_x = data.shield_offset_x or 20,
        shield_offset_y = data.shield_offset_y or 6,
        -- 無人機參數
        flight_height_min = data.flight_height_min or 40,
        flight_height_max = data.flight_height_max or 80,
        flight_speed = data.flight_speed or 30,
        vertical_oscillation = data.vertical_oscillation or 20,
        vertical_speed = data.vertical_speed or 1.5,
        drone_vertical_offset = 0,  -- 無人機當前垂直位置（相對於中心高度）
        drone_vertical_time = 0     -- 無人機振動計時器
    }
    -- 處理敵人高度：y 參數表示相對於地面的偏移（負值=上方，0=地面）
    -- 如果 y <= 0，設置為地面上方；如果 y > 0，表示絕對位置
    if y <= 0 then
        -- y 是相對於地面的偏移，0表示地面上
        e.y = ground_y - e.height + y
    else
        -- y > 0 時，確保在地面上或以上
        e.y = math.min(y, ground_y - e.height)
    end
    
    -- 特殊處理：無人機應該在空中飛行
    if data and data.move_type == "AERIAL" then
        -- 無人機初始位置在飛行高度的中心
        local flight_height_center = (data.flight_height_min + data.flight_height_max) / 2
        e.y = ground_y - e.height - flight_height_center
    end
    setmetatable(e, { __index = Enemy })
    print("LOG: Created Enemy " .. type_id .. " at " .. x .. " (" .. img_width .. "x" .. img_height .. ")")
    -- 從敵人資料讀取砲彈 multiplier（可在 enemy_data.lua 調整）
    e.projectile_speed_mult = (data and data.projectile_speed_mult) or 1.0
    e.projectile_grav_mult = (data and data.projectile_grav_mult) or 1.0
    -- 載入劍圖片（若有提供）
    if data and data.sword_image then
        local ok_sword, sword_img = pcall(function()
            return playdate.graphics.image.new(data.sword_image)
        end)
        if ok_sword and sword_img then
            e.sword_image = sword_img
        end
    end
    return e
end

function Enemy:update(dt, mech_x, mech_y, mech_width, mech_height, controller)
    -- [[ S6 ]] BOSS 走專屬階段控制器
    if self.is_boss then
        return self:updateBoss(dt, mech_x, mech_y, mech_width, mech_height, controller)
    end
    -- 如果正在爆炸，更新爆炸動畫
    if self.is_exploding then
        self.exploding_frame_timer = self.exploding_frame_timer + dt
        if self.exploding_frame_timer >= self.exploding_duration then
            self.is_alive = false
            self.is_exploding = false
            print("LOG: Enemy explosion animation complete, marked as dead")
        end
        return
    end
    
    if not self.is_alive then return end

    -- [[ 2026-08-09 ]] 通用待機動畫：敵人資料設了 anim_fps 就循環播放 imagetable。
    -- JUMP_ENEMY 是自己依跳躍狀態指定幀（不設 anim_fps），所以不受影響。
    if self.anim_fps and self.imagetable then
        self.anim_timer = (self.anim_timer or 0) + dt
        local step = 1 / self.anim_fps
        if self.anim_timer >= step then
            self.anim_timer = self.anim_timer - step
            local n = self.imagetable:getLength() or 1
            self.anim_frame = ((self.anim_frame or 1) % n) + 1
            self.image = self.imagetable:getImage(self.anim_frame)
        end
    end

    -- [[ S5 護送戰 ]] 若場景有存活的 NPC → 敵人改為朝 NPC 移動並攻擊它（護送戰模式）
    if controller and controller.npc and (controller.npc.hp or 0) > 0 and not controller.npc.reached_goal then
        return self:updateAttackNPC(dt, controller)
    end

    self.move_timer = self.move_timer + dt
    self.fire_timer = self.fire_timer + dt
    
    -- 更新受擊震動效果（添加安全檢查）
    if self.hit_shake_timer and self.hit_shake_timer > 0 then
        self.hit_shake_timer = self.hit_shake_timer - dt
        -- 震動效果：左右擺動（增加振幅到 5 像素，增加頻率）
        self.hit_shake_offset_x = math.sin(self.hit_shake_timer * 80) * 5
    else
        self.hit_shake_offset_x = 0
    end

    -- 根據 move_type 處理移動
    if self.move_type == "MOVE FORWARD/BACK" then
        -- BASIC_ENEMY: 前後移動，檢查斜坡
        if self.move_timer > 2.0 then
            self.move_timer = 0
            -- 依照機率決定是否移動
            if math.random() < self.move_probability then
                self.move_dir = self.move_dir * -1
            end
        end
        
        local new_x = self.x + self.move_dir * self.move_speed * dt
        
        -- 檢查是否超出移動範圍
        if math.abs(new_x - self.origin_x) < self.move_range then
            -- 檢查新位置是否在斜坡上
            if controller then
                local terrain_type = controller:getTerrainType(new_x)
                if terrain_type == "flat" then
                    self.x = new_x
                else
                    -- 遇到斜坡，停止移動並換方向
                    self.move_dir = self.move_dir * -1
                end
            else
                self.x = new_x
            end
        else
            -- 超出範圍，換方向
            self.move_dir = self.move_dir * -1
        end
        
    elseif self.move_type == "JUMP" then
        -- 跳躍敵人
        self.jump_timer = self.jump_timer + dt
        
        -- 應用重力
        if not self.is_grounded then
            self.vy = self.vy + (controller and controller.GRAVITY or 0.5)
            self.y = self.y + self.vy
            self.x = self.x + self.move_dir * self.jump_horizontal * dt
            
            -- 更新動畫幀：在空中時使用第3幀
            if self.imagetable then
                self.image = self.imagetable:getImage(3)  -- Frame 3: 在空中
            end
            
            -- 檢查是否落地
            local ground_height = controller and controller:getGroundHeight(self.x) or self.ground_y
            if self.y >= ground_height - self.height then
                self.y = ground_height - self.height
                self.vy = 0
                self.is_grounded = true
                self.jump_state = "landing"  -- 進入著陸狀態
                self.landing_frame_timer = 0
            end
        end
        
        -- 著陸動畫：顯示第2幀然後回到第1幀
        if self.jump_state == "landing" and self.imagetable then
            self.landing_frame_timer = self.landing_frame_timer + dt
            if self.landing_frame_timer < 0.1 then
                -- 著陸後0.1秒內顯示第2幀
                self.image = self.imagetable:getImage(2)
            else
                -- 然後回到第1幀
                self.image = self.imagetable:getImage(1)
                self.jump_state = "grounded"
            end
        end
        
        -- 跳躍邏輯
        if self.is_grounded and self.jump_state ~= "landing" and self.jump_timer >= self.jump_cooldown then
            self.jump_timer = 0
            self.vy = self.jump_velocity
            self.is_grounded = false
            self.jump_state = "jumping"  -- 進入跳躍狀態
            -- 跳起時使用第2幀
            if self.imagetable then
                self.image = self.imagetable:getImage(2)  -- Frame 2: 跳起
            end
            -- 隨機決定跳躍方向
            if math.random() < 0.5 then
                self.move_dir = self.move_dir * -1
            end
        end
        
    elseif self.move_type == "IMMOBILE" then
        -- 不移動的敵人
    
    elseif self.move_type == "SHIELD_MOVEMENT" then
        -- 盾牌機器人：盾牌舉起時不移動，收起時移動
        self.shield_timer = self.shield_timer + dt
        
        -- 切換盾牌狀態
        if self.shield_raised and self.shield_timer >= self.shield_up_duration then
            self.shield_raised = false
            self.shield_timer = 0
        elseif not self.shield_raised and self.shield_timer >= self.shield_down_duration then
            self.shield_raised = true
            self.shield_timer = 0
        end
        
        -- 盾牌收起時移動
        if not self.shield_raised then
            self.move_timer = self.move_timer + dt
            if self.move_timer > 2.0 then
                self.move_timer = 0
                self.move_dir = self.move_dir * -1
            end
            
            local new_x = self.x + self.move_dir * self.move_speed * dt
            if math.abs(new_x - self.origin_x) <= self.move_range then
                self.x = new_x
            end
        end
    
    elseif self.move_type == "AERIAL" then
        -- 無人機：前後飛行 + 上下振動
        self.move_timer = self.move_timer + dt
        self.drone_vertical_time = self.drone_vertical_time + dt
        
        -- 定期改變方向
        if self.move_timer > 3.0 then
            self.move_timer = 0
            self.move_dir = self.move_dir * -1
        end
        
        -- 前後飛行
        local new_x = self.x + self.move_dir * self.flight_speed * dt
        if math.abs(new_x - self.origin_x) <= self.move_range then
            self.x = new_x
        end
        
        -- 上下振動（正弦波）
        self.drone_vertical_offset = math.sin(self.drone_vertical_time * self.vertical_speed) * self.vertical_oscillation
    end

    -- 根據 attack_type 處理攻擊
    if self.attack_type == "FIRE BULLET" then
        if self.fire_timer >= self.fire_cooldown then
            self:fire(mech_x, controller)
            self.fire_timer = 0
        end
        
    elseif self.attack_type == "SWING SWORD" then
        self.sword_timer = self.sword_timer + dt
        
        if self.sword_swinging then
            -- 正在揮劍
            self.sword_angle = self.sword_angle + self.sword_direction * self.sword_swing_speed * dt
            -- 到達邊界則反向或結束一次揮擊
            if self.sword_direction > 0 and self.sword_angle >= self.sword_swing_max then
                self.sword_direction = -1
            elseif self.sword_direction < 0 and self.sword_angle <= self.sword_swing_min then
                self.sword_swinging = false
                -- 重置至最小角或 0 視覺效果需求
                self.sword_angle = self.sword_swing_min
            end
        else
            -- 等待下次揮劍
            if self.sword_timer >= self.sword_swing_cooldown then
                self.sword_timer = 0
                self.sword_swinging = true
                self.sword_direction = 1
            end
        end
        
    elseif self.attack_type == "CONTACT" then
        -- 接觸傷害（跳躍敵人）
        -- 碰撞檢測由 EntityController:updateAll 處理
    
    elseif self.attack_type == "SHIELD_FIRE" then
        -- 盾牌機器人：盾牌收起時才發射
        if not self.shield_raised then
            if self.fire_timer >= self.fire_cooldown then
                self:fire(mech_x, controller)
                self.fire_timer = 0
            end
        end
    elseif self.attack_type == "EXPLODE" then
        -- 地雷逻辑
        if not self.is_triggered then
            -- 检查是否被触发（玩家或砲彈碰到）
            -- 这部分由 updateAll 或其他系统处理
        elseif not self.is_exploded then
            self.explode_timer = self.explode_timer + dt
            if self.explode_timer >= self.explode_delay then
                self.is_exploded = true
                -- 加载爆炸动画表（仅加载一次）
                if not self.explode_image_table then
                    local ok, table_img = pcall(function()
                        return playdate.graphics.imagetable.new("images/mine_explode")
                    end)
                    if ok and table_img then
                        self.explode_image_table = table_img
                        -- 確保從第一幀開始播放
                        self.explode_frame_index = 0
                        self.explode_frame_timer = 0
                        print("LOG: Loaded mine explosion animation, frames: " .. (table_img:getLength() or 0))
                    else
                        print("WARNING: Failed to load mine explosion animation")
                    end
                end
                -- 播放爆炸音效
                if _G.SoundManager and _G.SoundManager.playExplode then
                    _G.SoundManager.playExplode()
                end
            end
        else
            -- 爆炸正在进行：更新动画帧
            if self.explode_image_table then
                self.explode_frame_timer = self.explode_frame_timer + dt
                local frame_count = self.explode_image_table:getLength() or 3
                if self.explode_frame_timer >= self.explode_frame_duration then
                    self.explode_frame_timer = 0
                    self.explode_frame_index = self.explode_frame_index + 1
                    -- When all frames have been played, mark mine as dead
                    if self.explode_frame_index >= frame_count then
                        self.is_alive = false
                        -- [[ FIX ]] 自爆的地雷 hp 仍為初始值，ELIMINATE 勝利判定
                        -- 看 hp>0 會永遠不過關——自爆完成視同被消滅，hp 歸零
                        self.hp = 0
                    end
                end
            else
                -- No animation table, mark as dead (animation timeout)
                self.is_alive = false
                self.hp = 0
            end
        end
    end
end
-- 發射拋物線砲彈 (擊向機甲)
function Enemy:fire(target_x, controller)
    -- 使用敵人資料中定義的子彈發射位置
    -- ★ 要加上 drone_vertical_offset：無人機的上下浮動是在**繪製時**才套用的
    --   （見 Enemy:draw 的 draw_y），發射點不加就會從偏離機身的高度射出。
    local start_x = self.x + self.bullet_offset_x
    local start_y = self.y + (self.drone_vertical_offset or 0) + self.bullet_offset_y
    local target_dist = target_x - start_x
    -- 使砲彈水平方向速度接近玩家的移動速度（尊重敵人定義的 multiplier）
    local base_vx = (controller and controller.player_move_speed) or 2.0
    local speed_multiplier = self.projectile_speed_mult or 1.0
    local vx_sign = 1
    if target_dist < 0 then vx_sign = -1 end
    local vx = vx_sign * base_vx * speed_multiplier

    -- 以水平速度估算到達時間（避免除以 0）
    local time_to_target = math.max(1.0, math.abs(target_dist) / math.max(math.abs(vx), 0.1))

    -- 使用與玩家相同的重力感覺（controller.GRAVITY），並乘上敵人定義的 grav multiplier
    local grav_multiplier = self.projectile_grav_mult or 1.0
    local projectileGravity = (controller and controller.GRAVITY) and (controller.GRAVITY * grav_multiplier) or 0.5

    -- 計算垂直初速度，使砲彈在 time_to_target 時抵達 target_y
    local target_y = self.ground_y - 32 -- 假定機甲高度
    local delta_y = target_y - start_y
    local GRAVITY = projectileGravity
    local vy = (delta_y - 0.5 * GRAVITY * time_to_target^2) / time_to_target

    -- 建立砲彈並給予自定重力
    local projectile = Projectile:init(start_x, start_y, vx, vy, self.attack, false, self.ground_y)
    projectile.gravity = projectileGravity
    table.insert(controller.projectiles, projectile)
end

-- [[ S5 護送戰 ]] 敵人朝 NPC 移動並接觸攻擊（有 NPC 時取代一般巡邏/射擊）
function Enemy:updateAttackNPC(dt, controller)
    local npc = controller.npc
    local dir = (npc.x > self.x) and 1 or -1
    self.move_dir = dir
    self.x = self.x + dir * (self.move_speed or 20) * dt
    self.npc_attack_timer = (self.npc_attack_timer or 0) + dt
    if math.abs(self.x - npc.x) < (self.width or 24) then
        if self.npc_attack_timer >= 0.6 then
            self.npc_attack_timer = 0
            npc.hp = npc.hp - (self.attack or 5)
            if _G.SoundManager and _G.SoundManager.playHit then _G.SoundManager.playHit() end
        end
    end
end

-- ==========================================================================
-- [[ S6 BOSS ]] BOSS = 核心 + 依序外掛可破壞武器零件；一次只露出一個弱點
-- ==========================================================================

-- 建立 BOSS（特殊敵人）。edata = { type="BOSS", boss_id, x, y }
function Enemy:initBoss(edata, ground_y)
    local bd = (_G.BossData or {})[edata.boss_id]
    if not bd or not bd.parts or #bd.parts == 0 then
        print("ERROR: BossData missing for " .. tostring(edata.boss_id))
        return Enemy:init(edata.x, edata.y or 0, "BASIC_ENEMY", ground_y)  -- 安全回退
    end
    local body_w = bd.body_w or 56
    local body_h = bd.body_h or 64
    local e = {
        is_boss = true, type_id = "BOSS", boss_id = edata.boss_id,
        boss_data = bd, boss_parts = bd.parts, boss_phase = 1,
        boss_x = edata.x, boss_y = ground_y - body_h,
        boss_body_w = body_w, boss_body_h = body_h,
        boss_ground_y = ground_y, origin_x = edata.x,
        boss_speed = bd.move_speed or 16, boss_range = bd.move_range or 90,
        boss_trans_time = bd.trans_time or 1.0, boss_invuln = 0,
        move_dir = -1,
        -- 傷害/碰撞管線需要的欄位
        hp = bd.parts[1].hp, attack = (bd.parts[1].attack and bd.parts[1].attack.damage) or 5,
        ground_y = ground_y, is_alive = true, is_exploding = false,
        exploding_frame_timer = 0, exploding_duration = BOSS_DEATH_DURATION, exploding_frame_index = 0,
        exploding_image_table = nil, fire_timer = 0,
        projectile_speed_mult = 30, projectile_grav_mult = 18,   -- 同一般敵人尺度（拋物線）
        bullet_offset_x = 0, bullet_offset_y = 0, hit_shake_offset_x = 0,
        x = edata.x, y = ground_y - body_h, width = 26, height = 26,
    }
    setmetatable(e, { __index = Enemy })

    -- [[ 美術 ]] 載入 72x72 sprite（imagetable，各格原位對齊）
    if bd.sprite then
        local ok, tbl = pcall(function() return playdate.graphics.imagetable.new(bd.sprite) end)
        if ok and tbl then
            e.boss_sheet = tbl
            -- [[ 2026-08-11 ]] 舊版這裡把「後輪／前輪」兩格各裁成小圖再 drawRotated。
            -- 新圖第 3 格是一整條 72×16 的**履帶**，不能旋轉 → 裁切與旋轉都已移除，改成原位貼上。

            -- 可旋轉瞄準的武器：裁成「軸心置中」的小圖，之後用 drawRotated 繞軸心轉
            e.aim_imgs = {}
            for _, p in ipairs(bd.parts) do
                if p.aim and p.cell and p.pivot_x and p.pivot_y then
                    local src = tbl:getImage(p.cell)
                    if src then
                        local size = 96   -- 足夠涵蓋軸心到最遠端（含砲管）
                        local okc, buf = pcall(function() return playdate.graphics.image.new(size, size) end)
                        if okc and buf then
                            playdate.graphics.pushContext(buf)
                            playdate.graphics.clear(playdate.graphics.kColorClear)
                            src:draw(-(p.pivot_x - size / 2), -(p.pivot_y - size / 2))
                            playdate.graphics.popContext()
                            e.aim_imgs[p.id] = buf
                        end
                    end
                end
            end
        else
            print("WARNING: failed to load boss sprite " .. tostring(bd.sprite))
        end
    end
    e:bossPositionHitbox()
    print("LOG: Created BOSS " .. tostring(edata.boss_id) .. " at " .. edata.x)
    return e
end

-- 把命中框（x/y/width/height、子彈發射點、攻擊力）對齊「當前露出的零件」
function Enemy:bossPositionHitbox()
    local part = self.boss_parts[self.boss_phase]
    self.width = part.w; self.height = part.h
    self.x = self.boss_x + part.dx
    self.y = self.boss_y + part.dy
    -- [[ 美術 ]] 子彈由槍口射出：muzzle 為 72x72 內座標，換算成相對命中框原點的偏移
    if part.muzzle_x and part.muzzle_y then
        self.bullet_offset_x = part.muzzle_x - part.dx
        self.bullet_offset_y = part.muzzle_y - part.dy
    else
        self.bullet_offset_x = part.w / 2
        self.bullet_offset_y = part.h / 2
    end
    self.attack = (part.attack and part.attack.damage) or 5
    self.projectile_speed_mult = (part.attack and part.attack.speed_mult) or 30
    self.projectile_grav_mult = (part.attack and part.attack.grav_mult) or 18
end

-- [[ 美術 ]] 武器瞄準：回傳「相對靜止方向(朝左)的旋轉角度」與朝玩家的單位向量。
-- 圖的靜止方向為朝左（180°），故旋轉量 = 目標角度 − 180°。
function Enemy:bossAimFor(part)
    local px = self.boss_x + (part.pivot_x or 0)
    local py = self.boss_y + (part.pivot_y or 0)
    local tx = self.aim_mx or (px - 100)
    local ty = self.aim_my or py
    local dx, dy = tx - px, ty - py
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.001 then dx, dy, len = -1, 0, 1 end
    local deg = math.deg(math.atan(dy, dx))
    return (deg - 180), (dx / len), (dy / len), px, py
end

-- [[ 演出 ]] 武器目前的顯示角度（相對靜止方向的旋轉量；0＝維持原圖朝左）
function Enemy:bossWeaponAngle(part)
    return (self.weapon_angles and self.weapon_angles[part.id]) or 0
end

-- 依「目前顯示角度」求砲管方向與軸心世界座標（發射點＝軸心 + 方向 × 砲管長）
function Enemy:bossWeaponDir(part)
    local rad = math.rad(180 + self:bossWeaponAngle(part))
    return math.cos(rad), math.sin(rad),
           self.boss_x + (part.pivot_x or 0), self.boss_y + (part.pivot_y or 0)
end

-- [[ 演出 ]] 發射前先轉動瞄準：在冷卻結束前 aim_time 秒開始以固定角速度轉向玩家，
-- 讓玩家看見「那是會動的武器、而且正在對準我」，之後才開火。
function Enemy:bossUpdateAim(part, dt)
    if not (part and part.aim) then return end
    self.weapon_angles = self.weapon_angles or {}
    local atk = part.attack or {}
    local aim_time = atk.aim_time or 0.8
    local cooldown = atk.cooldown or 2.0
    if self.fire_timer < math.max(0, cooldown - aim_time) then return end  -- 尚未到瞄準時段：保持不動
    local target = self:bossAimFor(part)
    local cur = self.weapon_angles[part.id] or 0
    local diff = ((target - cur + 180) % 360) - 180
    local step = (atk.aim_speed or 200) * dt
    if math.abs(diff) <= step then cur = target
    else cur = cur + (diff > 0 and step or -step) end
    self.weapon_angles[part.id] = cur
end

-- 以出生點為中心左右巡邏（速度 ≈ 一般敵人）
function Enemy:bossMove(dt)
    -- [[ 2026-08-11 ]] 舊版在這裡把移動距離換算成輪子轉角（wheel_angle）。
    -- 新圖第 3 格是整條履帶、不旋轉，該計算已移除。
    self.boss_x = self.boss_x + self.move_dir * self.boss_speed * dt
    if self.boss_x > self.origin_x + self.boss_range then
        self.boss_x = self.origin_x + self.boss_range; self.move_dir = -1
    elseif self.boss_x < self.origin_x - self.boss_range then
        self.boss_x = self.origin_x - self.boss_range; self.move_dir = 1
    end
end

-- 發射當前零件的 VOLLEY（n 發，spread 為散射）
function Enemy:bossVolley(atk, mech_x, controller)
    local n = atk.n or 1
    self.attack = atk.damage or 5
    -- 與一般敵人同尺度：速度倍率 25~35、重力倍率 15~20（提供拋物線）
    self.projectile_speed_mult = atk.speed_mult or 30
    self.projectile_grav_mult = atk.grav_mult or 18

    -- [[ 美術 ]] 會旋轉瞄準的武器：發射點取「旋轉後的槍口」（軸心 + 瞄準方向 × 砲管長）
    local part = self.boss_parts[self.boss_phase]
    if part and part.aim and part.pivot_x then
        local ux, uy, pxw, pyw = self:bossWeaponDir(part)   -- 依「目前顯示角度」而非瞬時瞄準
        local bl = math.sqrt(((part.muzzle_x or 0) - part.pivot_x) ^ 2 +
                             ((part.muzzle_y or 0) - (part.pivot_y or 0)) ^ 2)
        self.bullet_offset_x = (pxw + ux * bl) - self.x
        self.bullet_offset_y = (pyw + uy * bl) - self.y
    end
    for i = 1, n do
        local off = 0
        if atk.spread and n > 1 then off = (i - (n + 1) / 2) * 60 end
        self:fire(mech_x + off, controller)
    end
end

function Enemy:updateBoss(dt, mech_x, mech_y, mech_width, mech_height, controller)
    -- [[ 美術 ]] 記住玩家中心，供武器旋轉瞄準與雷射鏡射判斷使用
    if mech_x then
        self.aim_mx = mech_x + (mech_width or 48) / 2
        self.aim_my = mech_y and (mech_y + (mech_height or 32) / 2) or self.aim_my
    end

    -- [[ 演出 ]] 零件爆炸特效計時（在轉場無敵期間播放）
    if self.part_explode_timer then
        self.part_explode_timer = self.part_explode_timer + dt
        if self.part_explode_timer >= (self.part_explode_duration or 0.8) then
            self.part_explode_timer = nil
        end
    end

    -- [[ 演出 ]] 受擊震動（命中時由 controller 設 hit_shake_timer=0.3，與一般敵人同一套）
    if self.hit_shake_timer and self.hit_shake_timer > 0 then
        self.hit_shake_timer = self.hit_shake_timer - dt
        self.hit_shake_offset_x = math.sin(self.hit_shake_timer * 80) * 5
    else
        self.hit_shake_offset_x = 0
    end
    -- 零件被打爆（管線把 hp 打到 0 → 設 is_exploding）
    if self.is_exploding then
        if self.boss_phase < #self.boss_parts then
            -- 還有零件 → 攔截爆炸，推進階段 + 無敵轉場
            self.is_exploding = false
            -- [[ 演出 ]] 被打爆的零件在原位播放爆炸特效（沿用 mine_explode 動畫表）
            local dead = self.boss_parts[self.boss_phase]
            if dead then
                self.part_explode_x = self.boss_x + dead.dx + dead.w / 2
                self.part_explode_y = self.boss_y + dead.dy + dead.h / 2
                self.part_explode_timer = 0
                self.part_explode_duration = 0.8
            end
            self.boss_phase = self.boss_phase + 1
            self.boss_invuln = self.boss_trans_time or 1.0
            self.hp = self.boss_parts[self.boss_phase].hp
            self:bossPositionHitbox()
            self.fire_timer = 0
            if _G.SoundManager and _G.SoundManager.playExplode then _G.SoundManager.playExplode() end
            print("LOG: Boss part destroyed -> phase " .. self.boss_phase .. "/" .. #self.boss_parts)
            return
        else
            -- 最後零件 → 真正死亡。
            -- [[ 演出 2026-08-08 ]] BOSS 的死亡爆炸拉長到 BOSS_DEATH_DURATION（3 秒），
            -- 期間在**機體各處連續炸開**（每 BOSS_DEATH_BURST_INTERVAL 秒隨機一發）。
            -- ★ 不是把單一動畫放慢 —— 那只會變成 1 秒 1 幀的投影片；
            --   連環爆才撐得住 3 秒，也才像一台大機器逐塊解體。
            -- 關卡端本來就會等 is_exploding 結束才過關（state_mission 的 BOSS_KILL 判定），
            -- 所以拉長這裡＝爆炸播完關卡才結束，不需要另外改。
            self.exploding_frame_timer = self.exploding_frame_timer + dt

            self.boss_burst_timer = (self.boss_burst_timer or 0) + dt
            if controller and controller.addBlastVisual
               and self.boss_burst_timer >= BOSS_DEATH_BURST_INTERVAL then
                self.boss_burst_timer = 0
                -- 在 BOSS 身體範圍內隨機取點
                local bx = self.boss_x + math.random(0, math.max(1, self.boss_body_w))
                local by = self.boss_y + math.random(0, math.max(1, self.boss_body_h))
                controller:addBlastVisual(bx, by)
                if _G.SoundManager and _G.SoundManager.playExplode then _G.SoundManager.playExplode() end
            end

            if self.exploding_frame_timer >= self.exploding_duration then
                self.is_alive = false; self.is_exploding = false
                print("LOG: BOSS defeated")
            end
            return
        end
    end
    if not self.is_alive then return end

    -- 轉場無敵：閃爍、不攻擊、免傷（把 hp 釘在當前零件滿血）
    if self.boss_invuln and self.boss_invuln > 0 then
        self.boss_invuln = self.boss_invuln - dt
        self.hp = self.boss_parts[self.boss_phase].hp
        self:bossMove(dt); self:bossPositionHitbox()
        return
    end

    -- 正常階段：移動 + 依冷卻發射當前零件武器
    self:bossMove(dt); self:bossPositionHitbox()

    -- [[ 演出 ]] BOSS 與玩家「同時在畫面上」才開始瞄準與攻擊（畫面外不偷打）
    local cam = (controller and controller.camera_x) or 0
    local SCREEN_W = 400
    local boss_on = (self.boss_x + (self.boss_body_w or 72) > cam) and (self.boss_x < cam + SCREEN_W)
    local mech_on = mech_x and (mech_x + (mech_width or 48) > cam) and (mech_x < cam + SCREEN_W)
    if not (boss_on and mech_on) then
        self.fire_timer = 0     -- 離開畫面時重置節奏，下次入畫重新從瞄準開始
        return
    end

    self.fire_timer = self.fire_timer + dt
    -- [[ 演出 ]] 發射前先轉動瞄準（讓玩家看懂那是武器）
    self:bossUpdateAim(self.boss_parts[self.boss_phase], dt)
    local atk = self.boss_parts[self.boss_phase].attack
    if atk and atk.type == "LASER" then
        self:bossLaser(atk, dt, mech_x, mech_y, mech_width, mech_height)
    elseif atk and self.fire_timer >= (atk.cooldown or 2.0) then
        self.fire_timer = 0
        if atk.type == "VOLLEY" then self:bossVolley(atk, mech_x, controller) end
    end
end

-- [[ S6 ]] 雷射（內部武器）：cooldown → charge 充能預告 → beam 開火（矩形命中一次）
-- 光束為水平橫向，從零件中心朝機體所在方向射出，貫穿整個畫面寬度。
function Enemy:bossLaser(atk, dt, mech_x, mech_y, mech_width, mech_height)
    self.laser_phase = self.laser_phase or "cooldown"
    self.laser_timer = (self.laser_timer or 0) + dt

    if self.laser_phase == "cooldown" then
        if self.laser_timer >= (atk.cooldown or 1.6) then
            self.laser_phase = "charge"
            self.laser_timer = 0
            -- 充能時鎖定方向與高度（之後開火不再追蹤，玩家可以閃開）
            -- [[ 美術 ]] 由雷射槍槍口射出
            local part = self.boss_parts[self.boss_phase]
            self.laser_dir = (mech_x + (mech_width or 0) / 2 < self.x) and -1 or 1
            if part and part.muzzle_x and part.muzzle_y then
                local mx = part.muzzle_x
                -- 玩家在右側且此零件會鏡射（雷射槍）：槍口位置也要水平鏡射
                if part.mirror_when_right and self.laser_dir > 0 then
                    mx = (self.boss_body_w or 72) - part.muzzle_x
                end
                self.laser_x = self.boss_x + mx
                self.laser_y = self.boss_y + part.muzzle_y
            else
                self.laser_x = self.x
                self.laser_y = self.y + (self.height or 28) / 2
            end
            self.laser_hit_applied = false
        end
    elseif self.laser_phase == "charge" then
        if self.laser_timer >= (atk.charge or 0.9) then
            self.laser_phase = "beam"
            self.laser_timer = 0
            if _G.SoundManager and _G.SoundManager.playCanonFire then _G.SoundManager.playCanonFire() end
        end
    elseif self.laser_phase == "beam" then
        -- 命中判定：機體矩形是否與光束（水平帶）相交；一次光束只扣一次
        if not self.laser_hit_applied and mech_x and mech_y then
            local half = (atk.thickness or 8) / 2
            local top, bot = self.laser_y - half, self.laser_y + half
            local mech_top, mech_bot = mech_y, mech_y + (mech_height or 32)
            local beam_x0, beam_x1
            if self.laser_dir < 0 then beam_x0, beam_x1 = self.x - 1000, self.x
            else beam_x0, beam_x1 = self.x, self.x + 1000 end
            local mech_left, mech_right = mech_x, mech_x + (mech_width or 48)
            if bot >= mech_top and top <= mech_bot and mech_right >= beam_x0 and mech_left <= beam_x1 then
                self.pending_mech_damage = (self.pending_mech_damage or 0) + (atk.damage or 15)
                self.laser_hit_applied = true
            end
        end
        if self.laser_timer >= (atk.beam_time or 0.4) then
            self.laser_phase = "cooldown"
            self.laser_timer = 0
        end
    end
end

function Enemy:drawBoss(camera_x)
    local g = playdate.graphics
    -- [[ 演出 ]] 受擊震動：整台 BOSS 水平抖動
    local bx = self.boss_x - camera_x + (self.hit_shake_offset_x or 0)
    local by = self.boss_y
    local bd = self.boss_data
    local sheet = self.boss_sheet
    local invuln = self.boss_invuln and self.boss_invuln > 0
    local blink = (math.floor(playdate.getCurrentTimeMilliseconds() / 100) % 2 == 0)

    if sheet then
        -- [[ 美術 ]] 以 72x72 sprite 合成：各格原位對齊，直接疊畫於同一原點
        local function drawCell(idx, ox, oy)
            if not idx then return end
            local img = sheet:getImage(idx)
            if img then pcall(function() img:draw(bx + (ox or 0), by + (oy or 0)) end) end
        end

        -- 履帶：整條原位貼上（不旋轉）。先畫＝在本體之下
        drawCell(bd.cell_track)

        -- [[ 2026-08-11 ]] 最終階段（雷射槍）**本體與管子都隱藏**，畫面只剩履帶＋雷射槍
        local final_phase = (self.boss_phase >= #self.boss_parts)
        if not (final_phase and bd.hide_body_on_final) then
            drawCell(bd.cell_body)
        end

        -- 管子：未進入最終階段才顯示，並上下移動
        if not final_phase then
            local amp = bd.pipe_vibrate or 2
            local vib = math.floor(math.sin(playdate.getCurrentTimeMilliseconds() / 70) * amp + 0.5)
            drawCell(bd.cell_pipe, 0, vib)
        end

        -- 武器零件：已破壞→不畫；當前弱點→轉場時閃爍；內部武器僅最終階段顯示
        for i, part in ipairs(self.boss_parts) do
            local is_current = (i == self.boss_phase)
            local destroyed = (i < self.boss_phase)
            local hidden_internal = (part.reveal == "internal") and (i > self.boss_phase)
            if (not destroyed) and (not hidden_internal) then
                if not (is_current and invuln and blink) then
                    local aim_img = self.aim_imgs and self.aim_imgs[part.id]
                    if part.aim and aim_img then
                        -- 旋轉瞄準的武器：繞軸心轉（角度為瞄準演出的當前值）
                        local rot = self:bossWeaponAngle(part)
                        pcall(function()
                            aim_img:drawRotated(bx + part.pivot_x, by + part.pivot_y, rot)
                        end)
                    elseif part.mirror_when_right and (self.aim_mx or 0) > (self.boss_x + (bd.body_w or 72) / 2) then
                        -- 玩家在右側：雷射槍水平鏡射（本體不鏡射）
                        local img = sheet:getImage(part.cell)
                        if img then
                            pcall(function() img:draw(bx, by, playdate.graphics.kImageFlippedX) end)
                        end
                    else
                        drawCell(part.cell)
                    end
                end
                -- [[ 演出 ]] 弱點提示：當前零件上方的向下箭頭，上下微幅浮動（取代舊的方框）
                if is_current and not invuln then
                    local ax = bx + part.dx + part.w / 2
                    local bob = math.sin(playdate.getCurrentTimeMilliseconds() / 180) * 3
                    local ay = by + part.dy - 12 + bob
                    -- 先畫白色外廓，1-bit 下在深色處也看得見
                    g.setColor(g.kColorWhite)
                    g.fillTriangle(ax - 8, ay - 10, ax + 8, ay - 10, ax, ay + 2)
                    g.setColor(g.kColorBlack)
                    g.fillTriangle(ax - 6, ay - 8, ax + 6, ay - 8, ax, ay)
                end
            end
        end
    else
        -- 佔位圖形（sprite 載入失敗時的備援）
        g.setColor(g.kColorWhite); g.fillRect(bx, by, self.boss_body_w, self.boss_body_h)
        g.setColor(g.kColorBlack); g.drawRect(bx, by, self.boss_body_w, self.boss_body_h)
        for i, part in ipairs(self.boss_parts) do
            local px, py = bx + part.dx, by + part.dy
            if i == self.boss_phase then
                if not (invuln and blink) then
                    g.setColor(g.kColorBlack); g.fillRect(px, py, part.w, part.h)
                end
                if not invuln then
                    g.setColor(g.kColorBlack); g.setLineWidth(1)
                    g.drawRect(px - 3, py - 3, part.w + 6, part.h + 6)
                end
            elseif i > self.boss_phase and part.reveal ~= "internal" then
                g.setColor(g.kColorBlack); g.drawRect(px, py, part.w, part.h)
            end
        end
    end

    -- [[ 演出 ]] 零件被打爆的爆炸特效（沿用 mine_explode 動畫表，與敵人死亡共用）
    if self.part_explode_timer then
        if not self.part_explode_table then
            local okt, tbl = pcall(function() return playdate.graphics.imagetable.new("images/mine_explode") end)
            if okt and tbl then self.part_explode_table = tbl end
        end
        if self.part_explode_table then
            local dur = self.part_explode_duration or 0.8
            local n = self.part_explode_table:getLength() or 3
            local idx = math.floor((self.part_explode_timer / dur) * n) + 1
            if idx < 1 then idx = 1 elseif idx > n then idx = n end
            local frame = self.part_explode_table:getImage(idx)
            if frame then
                local fw, fh = frame:getSize()
                pcall(function()
                    frame:draw((self.part_explode_x or self.boss_x) - camera_x - fw / 2,
                               (self.part_explode_y or self.boss_y) - fh / 2)
                end)
            end
        end
    end

    -- [[ S6 ]] 雷射：充能＝細虛線警告（閃爍）；開火＝粗光束（含外圈白邊更醒目）
    if self.laser_phase == "charge" or self.laser_phase == "beam" then
        local ly = self.laser_y or (self.y + 14)
        local sx = (self.laser_x or self.x) - camera_x
        local ex = (self.laser_dir or 1) < 0 and -20 or 420
        if self.laser_phase == "charge" then
            if (math.floor(playdate.getCurrentTimeMilliseconds() / 60) % 2) == 0 then
                g.setColor(g.kColorBlack); g.setLineWidth(1)
                g.drawLine(sx, ly, ex, ly)
            end
        else
            local atk = self.boss_parts[self.boss_phase].attack
            local th = (atk and atk.thickness) or 8
            g.setColor(g.kColorWhite); g.setLineWidth(th + 4)
            g.drawLine(sx, ly, ex, ly)
            g.setColor(g.kColorBlack); g.setLineWidth(th)
            g.drawLine(sx, ly, ex, ly)
        end
        g.setLineWidth(1)
    end

    self:drawBossHpBar()
end

-- 螢幕上方固定：BOSS 名稱、階段進度、當前零件血條
function Enemy:drawBossHpBar()
    local g = playdate.graphics
    local part = self.boss_parts[self.boss_phase]
    local ratio = math.max(0, math.min(1, self.hp / (part.hp or 1)))
    local bw, bh = 220, 8
    local bx = (400 - bw) / 2
    local by = 22
    local title = (self.boss_data.name or "BOSS") .. "  [" .. (part.label or "?") ..
        "  " .. self.boss_phase .. "/" .. #self.boss_parts .. "]"

    -- [[ 可讀性 ]] 先鋪白底再畫：BOSS 血條在畫面上方，會被天空層的黑雲吃掉
    -- （同 state_mission 的 HUD 白底處理）。白底範圍涵蓋標題與血條，寬度取兩者較大值。
    local tw = g.getTextSize(title)
    local pad = 3
    local top = by - 16
    local block_w = math.max(tw, bw) + pad * 2
    local block_h = (by + bh) - top + pad * 2
    g.setColor(g.kColorWhite)
    g.fillRect(bx - pad, top - pad, block_w, block_h)

    g.setColor(g.kColorBlack)
    g.drawText(title, bx, top)
    g.drawRect(bx, by, bw, bh)
    g.fillRect(bx, by, math.floor(bw * ratio), bh)
end

function Enemy:drawMineExplosion(screen_x)
    if self.is_exploded and self.explode_image_table then
        -- Get frame with 1-based indexing (Playdate imagetable uses 1-based indexing)
        local frame_count = self.explode_image_table:getLength() or 3
        local current_frame = self.explode_frame_index + 1
        if current_frame < 1 then current_frame = 1 end
        if current_frame > frame_count then current_frame = frame_count end
        local frame = nil
        local ok, img = pcall(function()
            return self.explode_image_table:getImage(current_frame)
        end)
        if ok then frame = img end
        -- Explosion animation: draw at enemy's top-left, moved up 20px
        local anim_size = 50
        local draw_x = screen_x
        local draw_y = self.y - 20
        if frame then
            frame:draw(draw_x, draw_y)
        else
            -- 後備：若影格取得失敗，以白框提示位置（避免“看不到”）
            playdate.graphics.setColor(playdate.graphics.kColorWhite)
            playdate.graphics.drawRect(draw_x, draw_y, anim_size, anim_size)
        end
    elseif self.is_triggered and not self.is_exploded then
        -- [[ 2026-08-10 ]] 觸發後的警示燈：mine 的 imagetable 第 2/3 格交替閃爍。
        -- 警示燈與本體（第 1 格）畫在同一張 32×16 畫布的上下兩段，
        -- 所以用「和本體完全相同的座標」疊畫就會對位，不要另外加偏移。
        -- 本體是由 Enemy:draw() 的一般路徑畫的（self.image = 第 1 格），這裡只負責疊燈。
        local ed = EnemyData[self.type_id] or {}
        local speed = ed.warn_blink_speed or 10
        local on = (math.floor(self.explode_timer * speed) % 2 == 0)
        local frame_idx = on and (ed.warn_frame_a or 2) or (ed.warn_frame_b or 3)
        local lamp = nil
        if self.imagetable then
            local ok, img = pcall(function() return self.imagetable:getImage(frame_idx) end)
            if ok then lamp = img end
        end
        if lamp then
            lamp:draw(screen_x, self.y)
        elseif on then
            -- 後備：沒有警示燈圖時沿用舊的白框閃爍
            playdate.graphics.setColor(playdate.graphics.kColorWhite)
            playdate.graphics.fillRect(screen_x - 2, self.y - 2, self.width + 4, self.height + 4)
        end
    end
end

function Enemy:draw(camera_x)
    -- [[ S6 ]] BOSS 專屬繪製（爆炸中則落到下方沿用死亡爆炸動畫）
    -- [[ 演出 2026-08-08 ]] BOSS **爆炸期間也照畫機體**。
    -- 連環爆是由 controller 畫在它身上的（見 updateBoss 的 addBlastVisual），
    -- 機體要等 is_alive 變 false 才消失 —— 這樣才有「一台大機器被逐塊炸開」的感覺。
    -- 若沿用下方的通用爆炸繪製，3 秒 ÷ 3 幀 = 1 秒 1 幀，會變成投影片。
    if self.is_boss then
        return self:drawBoss(camera_x)
    end
    -- 敌人死亡爆炸动画
    if self.is_exploding then
        local screen_x = self.x - camera_x + (self.hit_shake_offset_x or 0)
        if not self.exploding_image_table then
            local ok, table_img = pcall(function()
                return playdate.graphics.imagetable.new("images/mine_explode")
            end)
            if ok and table_img then
                self.exploding_image_table = table_img
            end
        end
        
        if self.exploding_image_table then
            local frame_count = self.exploding_image_table:getLength() or 3
            self.exploding_frame_index = math.floor((self.exploding_frame_timer / self.exploding_duration) * frame_count)
            if self.exploding_frame_index >= frame_count then
                self.exploding_frame_index = frame_count - 1
            end
            
            local frame_img = self.exploding_image_table:getImage(self.exploding_frame_index + 1)
            if frame_img then
                pcall(function()
                    frame_img:draw(screen_x, self.y)
                end)
            end
        end
        return
    end
    
    if not self.is_alive and not self.is_exploded then return end
    local screen_x = self.x - camera_x + (self.hit_shake_offset_x or 0)  -- 應用震動偏移
    
    -- 爆炸動畫播放中，只繪製爆炸效果（但地雷爆炸完成後不繪製）
    if self.attack_type == "EXPLODE" and self.is_exploded then
        -- 檢查爆炸動畫是否已完成
        if self.explode_image_table then
            local frame_count = self.explode_image_table:getLength() or 3
            if self.explode_frame_index >= frame_count then
                -- 爆炸動畫已完成，不繪製
                return
            end
        end
        self:drawMineExplosion(screen_x)
        return
    end
    
    -- 如果已死亡且不在爆炸中，不繪製
    if not self.is_alive then return end
    
    -- 無人機：應用垂直振幅偏移
    local draw_y = self.y
    if self.move_type == "AERIAL" then
        draw_y = self.y + self.drone_vertical_offset
    end
    
    -- 繪製敵人圖片或方塊
    if self.image then
        pcall(function() self.image:draw(screen_x, draw_y) end)
    else
        gfx.setColor(gfx.kColorBlack)
        gfx.fillRect(screen_x, draw_y, self.width, self.height)
    end
    
    -- 繪製盾牌（盾牌機器人）
    if self.type_id == "SHIELD_ROBOT" and self.shield_raised then
        local shield_x = screen_x + self.shield_offset_x
        local shield_y = draw_y + self.shield_offset_y
        gfx.setColor(gfx.kColorBlack)
        gfx.fillRect(shield_x, shield_y, self.shield_width, self.shield_height)
        gfx.setColor(gfx.kColorWhite)
        gfx.drawRect(shield_x, shield_y, self.shield_width, self.shield_height)
    end
    
    -- 繪製 HP 條
    local hp_max = EnemyData[self.type_id].hp
    local hp_percent = self.hp / hp_max
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(screen_x, draw_y - 5, self.width * hp_percent, 3) 
    
    -- 繪製劍（SWORD_ENEMY）
    if self.attack_type == "SWING SWORD" then
        local enemy_data = EnemyData[self.type_id] or {}
        local pivot_offset_x = enemy_data.sword_pivot_offset_x or 0
        local pivot_offset_y = enemy_data.sword_pivot_offset_y or 0
        
        -- 世界座標下的旋轉軸心
        local pivot_x = screen_x + self.width / 2 + pivot_offset_x
        local pivot_y = draw_y + self.height / 2 + pivot_offset_y
        local angle_rad = math.rad(self.sword_angle)
        
        if self.sword_image then
            -- 劍圖內部的旋轉軸心偏移（相對於劍圖中心）
            local img_pivot_offset_x = enemy_data.sword_image_pivot_offset_x or 0
            local img_pivot_offset_y = enemy_data.sword_image_pivot_offset_y or 0
            local cos_a = math.cos(angle_rad)
            local sin_a = math.sin(angle_rad)
            -- 將圖內偏移隨旋轉計算後套用到繪製位置
            local rotated_offset_x = img_pivot_offset_x * cos_a - img_pivot_offset_y * sin_a
            local rotated_offset_y = img_pivot_offset_x * sin_a + img_pivot_offset_y * cos_a
            local draw_x = pivot_x - rotated_offset_x
            local draw_y = pivot_y - rotated_offset_y
            pcall(function()
                self.sword_image:drawRotated(draw_x, draw_y, self.sword_angle)
            end)
        else
            -- 預設：直線繪制
            local sword_length = enemy_data.sword_length or 30
            local end_x = pivot_x + math.cos(angle_rad) * sword_length
            local end_y = pivot_y + math.sin(angle_rad) * sword_length
            
            gfx.setLineWidth(3)
            gfx.drawLine(pivot_x, pivot_y, end_x, end_y)
            gfx.setLineWidth(1)
        end
    end

    if self.attack_type == "EXPLODE" then
        self:drawMineExplosion(screen_x)
    end
end

