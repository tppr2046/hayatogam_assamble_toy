-- module_entities.lua (最終穩定版 - 修正 'continue' 為 'goto'，新增 Enemy/Projectile 基礎)

import "CoreLibs/graphics"

local gfx = playdate.graphics
local EnemyData = import "enemy_data" -- 確保載入敵人數據

EntityController = {}
MechController = {}  -- 新增：機甲控制器

-- [[ ========================================== ]]
-- [[  MechController 類別 (機甲零件控制) ]]
-- [[ ========================================== ]]

function MechController:init()
    local mc = {
        -- 零件狀態
        active_part_id = nil,
        selected_part_slot = nil,  -- {col, row}
        
        -- SWORD 相關
        sword_angle = 0,
        sword_is_attacking = false,
        sword_last_attack_angle = nil,
        
        -- CANON 相關
        canon_angle = 0,
        canon_fire_timer = 0,
        
        -- GUN 相關
        gun_fire_timer = 0,
        
        -- FEET 相關（跳躍）
        velocity_y = 0,  -- 垂直速度
        is_grounded = true,  -- 是否在地面上
        feet_is_moving = false,  -- 是否正在移動
        feet_move_direction = 0,  -- 移動方向：1=向右, -1=向左, 0=靜止
        feet_animation = nil,  -- 動畫循環物件
        
        -- CLAW 相關
        claw_arm_angle = 0,  -- 臂的旋轉角度
        claw_arm_angle_prev = 0,  -- 上一幀的臂角度（用於計算旋轉速度）
        claw_grip_angle = 0,  -- 爪子的開合角度（0=閉合，max=張開）
        claw_grip_angle_prev = 0,  -- 上一幀的爪子角度（用於檢測開合狀態變化）
        claw_grabbed_stone = nil,  -- 當前抓住的石頭
        
        -- 玩家受擊效果
        hit_shake_timer = 0,
        hit_shake_offset = 0
    }
    setmetatable(mc, { __index = MechController })
    return mc
end

-- 處理零件選擇和激活
function MechController:handleSelection(mech_stats)
    local UI_GRID_COLS = 3
    local UI_GRID_ROWS = 2
    
    if not self.active_part_id then
        -- 未激活：方向鍵選擇
        if playdate.buttonJustPressed(playdate.kButtonUp) then
            if not self.selected_part_slot then
                self.selected_part_slot = {col = 1, row = 1}
            else
                self.selected_part_slot.row = math.min(UI_GRID_ROWS, self.selected_part_slot.row + 1)
            end
        elseif playdate.buttonJustPressed(playdate.kButtonDown) then
            if self.selected_part_slot then
                self.selected_part_slot.row = math.max(1, self.selected_part_slot.row - 1)
            end
        elseif playdate.buttonJustPressed(playdate.kButtonLeft) then
            if not self.selected_part_slot then
                self.selected_part_slot = {col = 1, row = 1}
            else
                self.selected_part_slot.col = math.max(1, self.selected_part_slot.col - 1)
            end
        elseif playdate.buttonJustPressed(playdate.kButtonRight) then
            if not self.selected_part_slot then
                self.selected_part_slot = {col = 1, row = 1}
            else
                self.selected_part_slot.col = math.min(UI_GRID_COLS, self.selected_part_slot.col + 1)
            end
        elseif playdate.buttonJustPressed(playdate.kButtonA) then
            -- 激活選中的零件
            if self.selected_part_slot and mech_stats then
                local eq = mech_stats.equipped_parts or {}
                for _, item in ipairs(eq) do
                    local slot_w = item.w or 1
                    local slot_h = item.h or 1
                    if self.selected_part_slot.col >= item.col and self.selected_part_slot.col < item.col + slot_w and
                       self.selected_part_slot.row >= item.row and self.selected_part_slot.row < item.row + slot_h then
                        self.active_part_id = item.id
                        break
                    end
                end
            end
        elseif playdate.buttonJustPressed(playdate.kButtonB) then
            self.selected_part_slot = nil
        end
    else
        -- 已激活：按 B 取消
        if playdate.buttonJustPressed(playdate.kButtonB) then
            self.active_part_id = nil
        end
    end
end

-- 處理零件操作（返回移動增量）
function MechController:handlePartOperation(mech_x, mech_y, mech_grid, entity_controller)
    local dx = 0
    local MOVE_SPEED = 2.0
    
    if self.active_part_id == "WHEEL" then
        -- WHEEL：左右移動
        if playdate.buttonIsPressed(playdate.kButtonLeft) then
            dx = dx - MOVE_SPEED
        end
        if playdate.buttonIsPressed(playdate.kButtonRight) then
            dx = dx + MOVE_SPEED
        end
        
    elseif self.active_part_id == "SWORD" then
        -- SWORD：crank 旋轉
        local crankChange = playdate.getCrankChange()
        if crankChange and math.abs(crankChange) > 0 then
            self.sword_angle = self.sword_angle + crankChange
            if self.sword_angle < 0 then self.sword_angle = 0 end
            if self.sword_angle > 180 then self.sword_angle = 180 end
            
            if not self.sword_last_attack_angle or math.abs(self.sword_angle - self.sword_last_attack_angle) >= 30 then
                self.sword_is_attacking = true
                self.sword_last_attack_angle = self.sword_angle
            else
                self.sword_is_attacking = false
            end
        else
            self.sword_is_attacking = false
        end
        
    elseif self.active_part_id == "CANON" then
        -- CANON：crank 旋轉 + A 發射
        local pdata = _G.PartsData and _G.PartsData["CANON"]
        local angle_min = pdata and pdata.angle_min or -45  -- 預設 -45 度
        local angle_max = pdata and pdata.angle_max or 45  -- 預設 +45 度
        local crank_ratio = pdata and pdata.crank_degrees_per_rotation or 15  -- 預設 crank 轉 1 圈產生 15 度變化
        
        local crankChange = playdate.getCrankChange()
        if crankChange and math.abs(crankChange) > 0 then
            -- crank 轉動量轉換為 canon 角度變化：crankChange 是度數，除以 360 得到圈數，乘以 crank_ratio 得到 canon 角度變化
            local canon_delta = (crankChange / 360.0) * crank_ratio
            self.canon_angle = self.canon_angle + canon_delta
            
            -- 限制角度在範圍內
            if self.canon_angle > angle_max then
                self.canon_angle = angle_max
            elseif self.canon_angle < angle_min then
                self.canon_angle = angle_min
            end
        end
        
        if playdate.buttonJustPressed(playdate.kButtonA) then
            if pdata and self.canon_fire_timer >= (pdata.fire_cooldown or 0.5) then
                local eq = _G.GameState.mech_stats.equipped_parts or {}
                for _, item in ipairs(eq) do
                    if item.id == "CANON" then
                        local cell_size = mech_grid.cell_size
                        local canon_x = mech_x + (item.col - 1) * cell_size + cell_size / 2
                        local canon_y = mech_y + (mech_grid.rows - item.row) * cell_size + cell_size / 2
                        
                        -- 使用與敵人相同的計算方式
                        local base_speed = entity_controller.player_move_speed or 2.0
                        local speed_mult = pdata.projectile_speed_mult or 1.0
                        local speed = base_speed * speed_mult
                        
                        local angle_rad = math.rad(self.canon_angle)
                        local vx = math.cos(angle_rad) * speed
                        local vy = -math.sin(angle_rad) * speed
                        local dmg = pdata.projectile_damage or 10
                        local grav_mult = pdata.projectile_grav_mult or 1.0
                        
                        entity_controller:addPlayerProjectile(canon_x, canon_y, vx, vy, dmg, grav_mult)
                        self.canon_fire_timer = 0
                        break
                    end
                end
            end
        end
    elseif self.active_part_id == "FEET" then
        -- FEET：左右移動 + 跳躍
        local pdata = _G.PartsData and _G.PartsData["FEET"]
        local move_speed = (pdata and pdata.move_speed) or 3.0
        
        local moving = false
        local direction = 0
        
        if playdate.buttonIsPressed(playdate.kButtonLeft) then
            dx = dx - move_speed
            moving = true
            direction = -1
        end
        if playdate.buttonIsPressed(playdate.kButtonRight) then
            dx = dx + move_speed
            moving = true
            direction = 1
        end
        
        self.feet_is_moving = moving
        self.feet_move_direction = direction
        
        -- A 鍵跳躍（只有在地面時才能跳）
        if playdate.buttonJustPressed(playdate.kButtonA) and self.is_grounded then
            local jump_vel = (pdata and pdata.jump_velocity) or -8.0
            self.velocity_y = jump_vel
            self.is_grounded = false
        end
        
    elseif self.active_part_id == "CLAW" then
        -- CLAW：上下鍵控制臂旋轉 + crank 控制爪子開合
        local pdata = _G.PartsData and _G.PartsData["CLAW"]
        local arm_angle_min = pdata and pdata.arm_angle_min or -90
        local arm_angle_max = pdata and pdata.arm_angle_max or 90
        local arm_rotate_speed = pdata and pdata.arm_rotate_speed or 2.0
        local claw_angle_min = pdata and pdata.claw_angle_min or 0
        local claw_angle_max = pdata and pdata.claw_angle_max or 45
        local crank_ratio = pdata and pdata.crank_degrees_per_rotation or 30
        
        -- 上下鍵控制臂的旋轉
        if playdate.buttonIsPressed(playdate.kButtonUp) then
            self.claw_arm_angle = self.claw_arm_angle + arm_rotate_speed
            if self.claw_arm_angle > arm_angle_max then
                self.claw_arm_angle = arm_angle_max
            end
        elseif playdate.buttonIsPressed(playdate.kButtonDown) then
            self.claw_arm_angle = self.claw_arm_angle - arm_rotate_speed
            if self.claw_arm_angle < arm_angle_min then
                self.claw_arm_angle = arm_angle_min
            end
        end
        
        -- Crank 控制爪子開合
        local crankChange = playdate.getCrankChange()
        if crankChange and math.abs(crankChange) > 0 then
            local claw_delta = (crankChange / 360.0) * crank_ratio
            self.claw_grip_angle = self.claw_grip_angle + claw_delta
            
            -- 限制爪子開合角度
            if self.claw_grip_angle > claw_angle_max then
                self.claw_grip_angle = claw_angle_max
            elseif self.claw_grip_angle < claw_angle_min then
                self.claw_grip_angle = claw_angle_min
            end
        end
        
        -- 自動抓取/投擲邏輯（基於爪子角度）
        if entity_controller then
            local grip_threshold = pdata and pdata.grab_threshold or 10  -- 從 parts_data 讀取抓取臨界值
            
            -- 檢測爪子從開啟變為關閉（抓取）
            if self.claw_grip_angle_prev >= grip_threshold and self.claw_grip_angle < grip_threshold then
                if not self.claw_grabbed_stone then
                    -- 嘗試抓取
                    self.try_grab = true
                end
            end
            
            -- 檢測爪子從關閉變為開啟（投擲）
            if self.claw_grip_angle_prev < grip_threshold and self.claw_grip_angle >= grip_threshold then
                if self.claw_grabbed_stone then
                    -- 投擲石頭
                    local stone = self.claw_grabbed_stone
                    
                    -- 計算拋射速度（根據臂的角度）
                    local angle_rad = math.rad(self.claw_arm_angle)
                    local launch_speed = 8
                    
                    -- 計算臂旋轉產生的額外速度（角速度轉線速度）
                    -- 假設臂長約 30 像素
                    local arm_length = 30
                    local arm_angular_velocity = self.claw_arm_angle - self.claw_arm_angle_prev  -- 度/幀
                    local arm_angular_velocity_rad = math.rad(arm_angular_velocity)  -- 弧度/幀
                    local arm_tangent_velocity = arm_length * arm_angular_velocity_rad  -- 像素/幀
                    
                    -- 基礎投擲速度 + 臂旋轉產生的速度
                    local vx = math.cos(angle_rad) * launch_speed + arm_tangent_velocity * math.cos(angle_rad + math.pi/2)
                    local vy = -math.sin(angle_rad) * launch_speed + arm_tangent_velocity * (-math.sin(angle_rad + math.pi/2))
                    
                    stone:launch(vx, vy)
                    self.claw_grabbed_stone = nil
                    print("LOG: Released stone with vx=" .. math.floor(vx) .. ", vy=" .. math.floor(vy) .. " (arm angular vel=" .. math.floor(arm_angular_velocity) .. "°)")
                end
            end
            
            -- 更新上一幀的爪子角度
            self.claw_grip_angle_prev = self.claw_grip_angle
        end
        
        -- 更新上一幀的臂角度
        self.claw_arm_angle_prev = self.claw_arm_angle
    end
    
    return dx
end

-- 更新零件計時器和自動功能
function MechController:updateParts(dt, mech_x, mech_y, mech_grid, entity_controller)
    -- 更新 CANON 冷卻
    self.canon_fire_timer = self.canon_fire_timer + dt
    
    -- GUN 自動發射
    self.gun_fire_timer = self.gun_fire_timer + dt
    local eq = _G.GameState.mech_stats.equipped_parts or {}
    for _, item in ipairs(eq) do
        local pdata = _G.PartsData and _G.PartsData[item.id]
        if item.id == "GUN" and pdata and pdata.fire_cooldown then
            if self.gun_fire_timer >= pdata.fire_cooldown then
                local cell_size = mech_grid.cell_size
                local gun_x = mech_x + (item.col - 1) * cell_size + cell_size / 2
                local gun_y = mech_y + (mech_grid.rows - item.row) * cell_size + cell_size / 2
                
                -- 使用與敵人相同的計算方式
                local base_speed = entity_controller.player_move_speed or 2.0
                local speed_mult = pdata.projectile_speed_mult or 1.0
                local vx = base_speed * speed_mult  -- 水平發射
                local vy = 0  -- GUN 直射，垂直速度為 0
                local dmg = pdata.projectile_damage or 5
                local grav_mult = pdata.projectile_grav_mult or 1.0
                
                entity_controller:addPlayerProjectile(gun_x, gun_y, vx, vy, dmg, grav_mult)
                self.gun_fire_timer = 0
                break
            end
        end
    end
    
    -- 更新受擊震動
    if self.hit_shake_timer > 0 then
        self.hit_shake_timer = self.hit_shake_timer - dt
        self.hit_shake_offset = math.sin(self.hit_shake_timer * 80) * 5
    else
        self.hit_shake_offset = 0
    end
    
    -- 更新 FEET 跳躍物理（重力）
    if self.active_part_id == "FEET" and not self.is_grounded then
        local gravity = (entity_controller and entity_controller.GRAVITY) or 0.5
        self.velocity_y = self.velocity_y + gravity
    end
end

-- 更新跳躍的地面狀態（由 state_mission 調用）
function MechController:updateGroundState(is_grounded)
    if is_grounded then
        self.is_grounded = true
        self.velocity_y = 0
    end
end

-- 觸發受擊效果
function MechController:onHit()
    self.hit_shake_timer = 0.3
    self.hit_shake_offset = 0
end

-- 更新抓取的石頭位置（由 state_mission 調用）
function MechController:updateGrabbedStone(claw_tip_x, claw_tip_y)
    if self.claw_grabbed_stone then
        self.claw_grabbed_stone.x = claw_tip_x - self.claw_grabbed_stone.width / 2
        self.claw_grabbed_stone.y = claw_tip_y
    end
end

-- 嘗試抓取石頭
function MechController:tryGrabStone(claw_tip_x, claw_tip_y, stones, grab_range)
    grab_range = grab_range or 20
    for _, stone in ipairs(stones or {}) do
        if not stone.is_grabbed then
            local dx = (stone.x + stone.width/2) - claw_tip_x
            local dy = (stone.y + stone.height/2) - claw_tip_y
            local distance = math.sqrt(dx*dx + dy*dy)
            if distance < grab_range and self.claw_grip_angle < 10 then  -- 爪子必須閉合才能抓
                stone.is_grabbed = true
                self.claw_grabbed_stone = stone
                print("LOG: Grabbed stone at distance=" .. math.floor(distance))
                return true
            end
        end
    end
    return false
end

-- [[ ========================================== ]]
-- [[  Projectile 類別 (砲彈) ]]
-- [[ ========================================== ]]

Projectile = {}

-- 砲彈初始化
function Projectile:init(x, y, vx, vy, damage, is_player_bullet, ground_y)
    local p = {
        x = x,
        y = y,
        vx = vx,
        vy = vy,
        damage = damage,
        is_player_bullet = is_player_bullet,
        width = 4,    -- 砲彈寬度
        height = 4,   -- 砲彈高度
        active = true,
        ground_y = ground_y -- 引用地面高度來處理碰撞
    }
    setmetatable(p, { __index = Projectile })
    return p
end

-- 砲彈更新
function Projectile:update(dt, GRAVITY)
    if not self.active then return end
    
    -- 應用物理
    self.x = self.x + self.vx * dt
    -- 使用砲彈自帶的 gravity（若未設定則使用世界重力）
    local g = self.gravity or GRAVITY or 0.5
    self.vy = self.vy + g * dt
    self.y = self.y + self.vy * dt
    
    -- 檢查是否碰到地面
    if self.y + self.height >= self.ground_y then
        self.y = self.ground_y - self.height
        self.active = false
    end
end

-- 砲彈繪製
function Projectile:draw(camera_x)
    if not self.active then return end
    local screen_x = self.x - camera_x
    gfx.setColor(self.is_player_bullet and gfx.kColorRed or gfx.kColorBlack)
    gfx.fillRect(screen_x, self.y, self.width, self.height)
end

-- [[ ========================================== ]]
-- [[  Enemy 類別 (敵人) ]]
-- [[ ========================================== ]]

Enemy = {}

function Enemy:init(x, y, type_id, ground_y)
    local data = EnemyData[type_id]
    local e = {
        x = x,
        y = y,
        type_id = type_id,
        hp = data.hp,
        attack = data.attack,
        width = 24,  -- 敵人模型寬度
        height = 32, -- 敵人模型高度
        ground_y = ground_y,
        vx = 1.0, -- 基礎水平速度
        move_dir = 1, -- 1 for right, -1 for left
        is_alive = true,
        move_timer = 0,
        fire_timer = 0,
        fire_cooldown = 2.0 -- 每 2 秒發射一次
    }
    -- 確保敵人站在地面上
    e.y = ground_y - e.height 
    setmetatable(e, { __index = Enemy })
    print("LOG: Created Enemy " .. type_id .. " at " .. x)
    -- 從敵人資料讀取砲彈 multiplier（可在 enemy_data.lua 調整）
    e.projectile_speed_mult = (data and data.projectile_speed_mult) or 1.0
    e.projectile_grav_mult = (data and data.projectile_grav_mult) or 1.0
    return e
end

function Enemy:update(dt, mech_x, controller)
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

    -- 左右移動邏輯 (BASIC_ENEMY)
    if self.type_id == "BASIC_ENEMY" then
        if self.move_timer > 2.0 then -- 每 2 秒換一次方向
            self.move_dir = self.move_dir * -1
            self.move_timer = 0
        end
        self.x = self.x + self.move_dir * self.vx * dt
    end

    -- 射擊邏輯
    if self.fire_timer >= self.fire_cooldown then
        self:fire(mech_x, controller)
        self.fire_timer = 0
    end
end

-- 發射拋物線砲彈 (擊向機甲)
function Enemy:fire(target_x, controller)
    local start_x = self.x + self.width / 2
    local start_y = self.y + self.height / 2
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

function Enemy:draw(camera_x)
    if not self.is_alive then return end
    local screen_x = self.x - camera_x + (self.hit_shake_offset_x or 0)  -- 應用震動偏移
    gfx.setColor(gfx.kColorBlack)
    -- 繪製敵人模型
    gfx.fillRect(screen_x, self.y, self.width, self.height) 
    -- 繪製 HP 條
    local hp_max = EnemyData[self.type_id].hp
    local hp_percent = self.hp / hp_max
    gfx.fillRect(screen_x, self.y - 5, self.width * hp_percent, 3) 
end

-- [[ ========================================== ]]
-- [[  Stone 類別 (可互動石頭) ]]
-- [[ ========================================== ]]

Stone = {}

function Stone:init(x, y, ground_y)
    local stone_img = nil
    pcall(function()
        stone_img = playdate.graphics.image.new("images/stone")
    end)
    
    local stone = {
        x = x,
        y = y,
        width = 16,
        height = 16,
        vx = 0,
        vy = 0,
        is_grounded = (y >= ground_y - 16),
        is_grabbed = false,  -- 是否被爪子抓住
        ground_y = ground_y,
        image = stone_img,
        damage = 15  -- 砸到敵人的傷害
    }
    setmetatable(stone, { __index = Stone })
    return stone
end

function Stone:update(dt, gravity)
    if self.is_grabbed then
        -- 被抓住時不更新物理
        return
    end
    
    -- 應用重力
    if not self.is_grounded then
        self.vy = self.vy + gravity
        self.y = self.y + self.vy
        
        -- 地面碰撞
        if self.y >= self.ground_y - self.height then
            self.y = self.ground_y - self.height
            self.vy = 0
            self.vx = 0  -- 落地後停止
            self.is_grounded = true
        end
    end
    
    -- 水平移動
    self.x = self.x + self.vx
end

function Stone:draw(camera_x)
    local screen_x = self.x - camera_x
    if self.image then
        pcall(function() self.image:draw(screen_x, self.y) end)
    else
        -- 備用：繪製方塊
        playdate.graphics.setColor(playdate.graphics.kColorBlack)
        playdate.graphics.fillRect(screen_x, self.y, self.width, self.height)
    end
end

function Stone:launch(vx, vy)
    -- 被拋出時設定速度
    self.vx = vx
    self.vy = vy
    self.is_grounded = false
    self.is_grabbed = false
end

-- [[ ========================================== ]]
-- [[  EntityController 類別 (實體總控制器) ]]
-- [[ ========================================== ]]

function EntityController:init(scene_data, enemies_data, player_move_speed, ui_offset)
    local ui_offset = ui_offset or 0  -- UI 區域偏移量
    local safe_ground_y = (scene_data and scene_data.ground_y) or 240
    -- 將地面往上移動 ui_offset
    safe_ground_y = safe_ground_y - ui_offset
    
    local controller = {
        obstacles = (scene_data and scene_data.obstacles) or {},
        ground_y = safe_ground_y,
        enemies = {}, -- 新增敵人列表
        projectiles = {}, -- 新增砲彈列表
        stones = {},  -- 新增石頭列表
        GRAVITY = 0.5, -- 將重力常數傳入
        player_move_speed = player_move_speed or 2.0 -- 供敵人計算砲彈速度
    }
    setmetatable(controller, { __index = EntityController })
    
    -- 初始化敵人
    for _, edata in ipairs(enemies_data or {}) do
        local enemy = Enemy:init(edata.x, edata.y, edata.type, safe_ground_y)
        table.insert(controller.enemies, enemy)
    end
    
    -- 初始化石頭
    local stones_data = (scene_data and scene_data.stones) or {}
    for _, sdata in ipairs(stones_data) do
        local stone_y = sdata.y == 0 and (safe_ground_y - 16) or sdata.y
        local stone = Stone:init(sdata.x, stone_y, safe_ground_y)
        table.insert(controller.stones, stone)
    end
    
    print("LOG: EntityController initialized with " .. #controller.obstacles .. " obstacles and " .. #controller.enemies .. " enemies.")
    return controller
end

-- 添加玩家砲彈
function EntityController:addPlayerProjectile(x, y, vx, vy, damage, grav_mult)
    grav_mult = grav_mult or 1.0
    
    local projectile = Projectile:init(x, y, vx, vy, damage, true, self.ground_y)
    -- 設定重力（基準重力 * 重力倍率）
    projectile.gravity = (self.GRAVITY or 0.5) * grav_mult
    table.insert(self.projectiles, projectile)
    print("LOG: Player fired projectile at (" .. math.floor(x) .. ", " .. math.floor(y) .. ") vx=" .. math.floor(vx) .. " grav_mult=" .. grav_mult)
end

function EntityController:updateAll(dt, mech_x, mech_y, mech_width, mech_height, mech_stats)
    local mech_damage_taken = 0

    -- 1. 更新敵人 (讓敵人移動和射擊)
    for i, enemy in ipairs(self.enemies) do
        if enemy.is_alive then
            enemy:update(dt, mech_x, self)
            
            -- 檢查敵人與機甲碰撞 (扣 HP 邏輯)
            if self:checkMechCollision(mech_x, mech_y, mech_width, mech_height, enemy.x, enemy.y, enemy.width, enemy.height) then
                 mech_damage_taken = mech_damage_taken + enemy.attack * dt -- 持續傷害
            end
        end
    end

    -- 2. 更新砲彈 (處理物理與碰撞)
    for i = #self.projectiles, 1, -1 do
        local p = self.projectiles[i]
        if p.active then
            p:update(dt, self.GRAVITY)
            
            -- 檢查敵人砲彈是否擊中機甲
            if not p.is_player_bullet and self:checkMechCollision(mech_x, mech_y, mech_width, mech_height, p.x, p.y, p.width, p.height) then
                mech_damage_taken = mech_damage_taken + p.damage
                p.active = false -- 擊中後銷毀
            end
            
            -- 檢查玩家砲彈是否擊中敵人
            if p.is_player_bullet then
                for _, enemy in ipairs(self.enemies) do
                    if enemy.is_alive and self:checkMechCollision(enemy.x, enemy.y, enemy.width, enemy.height, p.x, p.y, p.width, p.height) then
                        -- 擊中敵人
                        enemy.hp = enemy.hp - p.damage
                        p.active = false -- 砲彈銷毀
                        
                        -- 敵人受擊震動
                        enemy.hit_shake_timer = 0.3
                        enemy.hit_shake_offset_x = 0
                        
                        print("LOG: Player projectile hit enemy! HP=" .. math.floor(enemy.hp))
                        
                        if enemy.hp <= 0 then
                            enemy.is_alive = false
                            print("LOG: Enemy killed by player projectile")
                        end
                        break
                    end
                end
            end
            
        else
            table.remove(self.projectiles, i) -- 移除不活躍的砲彈
        end
    end
    
    -- 3. 更新石頭
    for i = #self.stones, 1, -1 do
        local stone = self.stones[i]
        stone:update(dt, self.GRAVITY)
        
        -- 檢查石頭是否與敵人碰撞（造成傷害）
        if not stone.is_grabbed and (stone.vx ~= 0 or stone.vy ~= 0) then
            for _, enemy in ipairs(self.enemies) do
                if enemy.is_alive and self:checkMechCollision(enemy.x, enemy.y, enemy.width, enemy.height, stone.x, stone.y, stone.width, stone.height) then
                    -- 石頭砸到敵人
                    enemy.hp = enemy.hp - stone.damage
                    enemy.hit_shake_timer = 0.3
                    enemy.hit_shake_offset_x = 0
                    
                    print("LOG: Stone hit enemy! HP=" .. math.floor(enemy.hp))
                    
                    if enemy.hp <= 0 then
                        enemy.is_alive = false
                        print("LOG: Enemy killed by stone")
                    end
                    
                    -- 石頭落地停止
                    stone.vx = 0
                    stone.vy = 0
                    stone.is_grounded = true
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
            if enemy.is_alive then
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
                    
                    -- 調試輸出：顯示被攻擊敵人的 HP
                    print("LOG: Enemy hit! Type=" .. (enemy.type_id or "unknown") .. ", HP=" .. math.floor(enemy.hp) .. "/" .. (EnemyData[enemy.type_id] and EnemyData[enemy.type_id].hp or "?") .. ", Damage=" .. attack)
                    
                    -- 受擊效果：震動
                    enemy.hit_shake_timer = 0.3  -- 0.3 秒震動（增加持續時間）
                    enemy.hit_shake_offset_x = 0
                    
                    if enemy.hp <= 0 then
                        enemy.is_alive = false
                        print("LOG: Enemy killed at x=" .. math.floor(enemy.x))
                    end
                end
            end
        end
        
        ::next_weapon::
    end
    
    return damage_dealt
end


function EntityController:draw(camera_x)
    local ground_y = self.ground_y
    gfx.setColor(gfx.kColorBlack)
    
    -- 繪製地面（只繪製一條橫線）
    gfx.drawLine(0, ground_y, 400, ground_y) 

    -- 繪製障礙物 (原有的邏輯保持不變)
    for i, obs in ipairs(self.obstacles) do
        
        if not obs then goto next_obstacle end 
        
        local obs_width = obs.width or 0 
        local obs_height = obs.height or 0
        local obs_x = obs.x or 0

        local obs_screen_x = obs_x - camera_x
        local obs_y = ground_y - obs_height

        if obs_screen_x < 400 and obs_screen_x + obs_width > 0 then
            gfx.fillRect(obs_screen_x, obs_y, obs_width, obs_height)
        end
        
        ::next_obstacle::
    end
    
    -- 繪製敵人
    for _, enemy in ipairs(self.enemies) do
        enemy:draw(camera_x)
    end
    
    -- 繪製石頭
    for _, stone in ipairs(self.stones) do
        stone:draw(camera_x)
    end
    
    -- 繪製砲彈
    for _, projectile in ipairs(self.projectiles) do
        projectile:draw(camera_x)
    end
end

-- checkCollision 函式保持不變 (用於機甲與場景的垂直/水平碰撞檢查)
-- ... (您的 checkCollision 函式內容) ...
local function checkCollision(self, target_x, target_y, mech_vy_current, mech_y_old, mech_width, mech_height)
    local mech_left = target_x
    local mech_right = target_x + mech_width
    local mech_top = target_y
    local mech_bottom = target_y + mech_height
    
    local horizontal_block = false
    local final_y_stop = nil
    
    local safe_ground_y = self.ground_y or 240 
    
    -- 合併障礙物和石頭為檢查列表
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

    for i, obs in ipairs(all_obstacles) do
        
        if not obs then goto next_collision_check end 
        
        local obs_width = obs.width or 0 
        local obs_height = obs.height or 0
        local obs_x = obs.x or 0

        local obs_left = obs_x
        local obs_right = obs_left + obs_width
        local obs_top = safe_ground_y - obs_height 
        local obs_bottom = safe_ground_y          

        -- 1. 廣義重疊檢查 (AABB 碰撞)
        if mech_right > obs_left and mech_left < obs_right and
           mech_bottom > obs_top and mech_top < obs_bottom then
            
            -- 2. 細分碰撞類型
            
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

return EntityController