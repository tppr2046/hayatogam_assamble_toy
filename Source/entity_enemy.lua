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

function Enemy:init(x, y, type_id, ground_y)
    local data = EnemyData[type_id]
    
    -- 載入敵人圖片或imagetable
    local enemy_img = nil
    local enemy_imagetable = nil
    local img_width = 24
    local img_height = 32
    if data.image then
        -- JUMP_ENEMY: 嘗試載入imagetable
        if type_id == "JUMP_ENEMY" then
            local ok_table, imagetable = pcall(function()
                return playdate.graphics.imagetable.new(data.image)
            end)
            if ok_table and imagetable then
                enemy_imagetable = imagetable
                -- 取得第一幀的大小
                local frame1 = imagetable:getImage(1)
                if frame1 then
                    local ok_size, w, h = pcall(function() return frame1:getSize() end)
                    if ok_size and w and h then
                        img_width = w
                        img_height = h
                    end
                end
                enemy_img = imagetable:getImage(1)  -- 預設顯示第1幀
            else
                -- imagetable失敗，回退到普通image
                local ok_img, img = pcall(function()
                    return playdate.graphics.image.new(data.image)
                end)
                if ok_img and img then
                    enemy_img = img
                    local ok_size, w, h = pcall(function() return img:getSize() end)
                    if ok_size and w and h then
                        img_width = w
                        img_height = h
                    end
                end
            end
        else
            -- 其他敵人: 使用普通image
            local ok, img = pcall(function()
                return playdate.graphics.image.new(data.image)
            end)
            if ok and img then
                enemy_img = img
                local ok_size, w, h = pcall(function() return img:getSize() end)
                if ok_size and w and h then
                    img_width = w
                    img_height = h
                end
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
        imagetable = enemy_imagetable,  -- JUMP_ENEMY 的 imagetable
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
    local start_x = self.x + self.bullet_offset_x
    local start_y = self.y + self.bullet_offset_y
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
        -- 調試：顯示當前爆炸影格
        playdate.graphics.drawText("EXP:" .. tostring(current_frame) .. "/" .. tostring(frame_count), draw_x, draw_y - 10)
    elseif self.is_triggered and not self.is_exploded then
        local blink_speed = 10
        if math.floor(self.explode_timer * blink_speed) % 2 == 0 then
            playdate.graphics.setColor(playdate.graphics.kColorWhite)
            playdate.graphics.fillRect(screen_x - 2, self.y - 2, self.width + 4, self.height + 4)
        end
    end
end

function Enemy:draw(camera_x)
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
            local sword_length = 30
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

