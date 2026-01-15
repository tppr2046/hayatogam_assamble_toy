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
        canon_button_pressed = false,  -- 按鈕是否按下
        
        -- GUN 相關
        gun_fire_timer = 0,
        
        -- FEET 相關（跳躍）
        velocity_y = 0,  -- 垂直速度
        is_grounded = true,  -- 是否在地面上
        feet_is_moving = false,  -- 是否正在移動
        feet_move_direction = 0,  -- 移動方向：1=向右, -1=向左, 0=靜止
        feet_animation = nil,  -- 動畫循環物件
        
        -- WHEEL 相關
        wheel_stick_offset = 0,  -- wheel_stick 的左右位移
        
        -- CLAW 相關
        claw_arm_angle = 0,  -- 臂的旋轉角度
        claw_arm_angle_prev = 0,  -- 上一幀的臂角度（用於計算旋轉速度）
        claw_grip_angle = 0,  -- 爪子的開合角度（0=閉合，max=張開）
        claw_grip_angle_prev = 0,  -- 上一幀的爪子角度（用於檢測開合狀態變化）
        claw_grabbed_stone = nil,  -- 當前抓住的石頭
        claw_is_attacking = false,  -- 爪子是否在攻擊狀態
        claw_last_attack_angle = 0,  -- 上次攻擊時的角度
        
        -- 玩家受擊效果
        hit_shake_timer = 0,
        hit_shake_offset = 0,
        
        -- 介面圖片
        ui_images = {}
    }
    setmetatable(mc, { __index = MechController })
    
    -- 載入通用 UI 圖片（如空格圖、dither 圖）
    local ok, empty_img = pcall(function()
        return playdate.graphics.image.new("images/empty")
    end)
    if ok and empty_img then
        mc.ui_images.empty = empty_img
    else
        print("WARNING: Failed to load empty.png")
    end
    
    local ok_dither, dither_img = pcall(function()
        return playdate.graphics.image.new("images/x")
    end)
    if ok_dither and dither_img then
        mc.ui_images.dither = dither_img
    else
        print("WARNING: Failed to load x.png")
    end
    
    -- 從 PartsData 載入每個零件的 UI 圖片
    if _G.PartsData then
        for part_id, part_data in pairs(_G.PartsData) do
            -- 載入 ui_panel
            if part_data.ui_panel then
                local ok_panel, panel_img = pcall(function()
                    return playdate.graphics.image.new(part_data.ui_panel)
                end)
                if ok_panel and panel_img then
                    mc.ui_images[part_id .. "_panel"] = panel_img
                else
                    print("WARNING: Failed to load UI panel for " .. part_id .. ": " .. part_data.ui_panel)
                end
            end
            
            -- 載入 ui_stick（如果有）
            if part_data.ui_stick then
                local ok_stick, stick_img = pcall(function()
                    return playdate.graphics.image.new(part_data.ui_stick)
                end)
                if ok_stick and stick_img then
                    mc.ui_images[part_id .. "_stick"] = stick_img
                else
                    print("WARNING: Failed to load UI stick for " .. part_id .. ": " .. part_data.ui_stick)
                end
            end
        end
    end
    
    -- 載入 CANON 專用的 control 圖片
    local ok_control, control_img = pcall(function()
        return playdate.graphics.image.new("images/canon_control")
    end)
    if ok_control and control_img then
        mc.ui_images.canon_control = control_img
    else
        print("WARNING: Failed to load canon_control.png")
    end
    
    -- 載入 CANON 專用的 button 圖片表
    local ok_button, button_table = pcall(function()
        return playdate.graphics.imagetable.new("images/canon_button")
    end)
    if ok_button and button_table then
        mc.ui_images.canon_button = button_table
    else
        print("WARNING: Failed to load canon_button.pdt")
    end
    
    -- 載入 CLAW 專用的 control 圖片
    local ok_claw_control, claw_control_img = pcall(function()
        return playdate.graphics.image.new("images/claw_control")
    end)
    if ok_claw_control and claw_control_img then
        mc.ui_images.claw_control = claw_control_img
    else
        print("WARNING: Failed to load claw_control.png")
    end
    
    -- 載入 CLAW 專用的 control_v 圖片表
    local ok_claw_control_v, claw_control_v_table = pcall(function()
        return playdate.graphics.imagetable.new("images/claw_control_v")
    end)
    if ok_claw_control_v and claw_control_v_table then
        mc.ui_images.claw_control_v = claw_control_v_table
    else
        print("WARNING: Failed to load claw_control_v.pdt")
    end
    
    return mc
end

-- 處理零件選擇和激活
function MechController:handleSelection(mech_stats)
    local UI_GRID_COLS = 3
    local UI_GRID_ROWS = 2
    
    if not self.active_part_id then
        -- 未激活：方向鍵選擇
        if playdate.buttonJustPressed(playdate.kButtonUp) then
            -- 按上：從下排跳到上排的零件
            local eq = mech_stats.equipped_parts or {}
            for _, item in ipairs(eq) do
                if item.row == 2 then  -- 找到上排的零件
                    self.selected_part_slot = {col = item.col, row = item.row}
                    break
                end
            end
        elseif playdate.buttonJustPressed(playdate.kButtonDown) then
            -- 按下：從上排跳到下排的零件
            local eq = mech_stats.equipped_parts or {}
            for _, item in ipairs(eq) do
                if item.row == 1 then  -- 找到下排的零件
                    self.selected_part_slot = {col = item.col, row = item.row}
                    break
                end
            end
        elseif playdate.buttonJustPressed(playdate.kButtonLeft) then
            if not self.selected_part_slot then
                -- 初始化：選中第一個零件
                local eq = mech_stats.equipped_parts or {}
                if #eq > 0 then
                    self.selected_part_slot = {col = eq[1].col, row = eq[1].row}
                end
            else
                self.selected_part_slot.col = math.max(1, self.selected_part_slot.col - 1)
            end
        elseif playdate.buttonJustPressed(playdate.kButtonRight) then
            if not self.selected_part_slot then
                -- 初始化：選中第一個零件
                local eq = mech_stats.equipped_parts or {}
                if #eq > 0 then
                    self.selected_part_slot = {col = eq[1].col, row = eq[1].row}
                end
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

-- 獲取當前激活零件的功能類型
function MechController:getActivePartType()
    if not self.active_part_id then
        return nil
    end
    local pdata = _G.PartsData and _G.PartsData[self.active_part_id]
    return pdata and pdata.part_type
end

-- 處理零件操作（返回移動增量）
function MechController:handlePartOperation(mech_x, mech_y, mech_grid, entity_controller)
    local dx = 0
    local MOVE_SPEED = 2.0
    
    local part_type = self:getActivePartType()
    if not part_type then
        return dx
    end
    
    if part_type == "WHEEL" then
        -- WHEEL：左右移動
        -- WHEEL 是 3x1 格，寬度 = 3*32 + 2*5 = 106 像素
        -- wheel_stick 可以從最左移動到最右，範圍大約是 panel 寬度的一半，減去 stick 寬度的一半
        -- 假設 panel 總寬 106，stick 寬 10，則最大偏移 = (106/2) - (10/2) = 48
        local max_stick_offset = 40
        
        if playdate.buttonIsPressed(playdate.kButtonLeft) then
            dx = dx - MOVE_SPEED
            self.wheel_stick_offset = math.max(-max_stick_offset, self.wheel_stick_offset - 5)
        elseif playdate.buttonIsPressed(playdate.kButtonRight) then
            dx = dx + MOVE_SPEED
            self.wheel_stick_offset = math.min(max_stick_offset, self.wheel_stick_offset + 5)
        else
            -- 放開後回到預設位置（加快回復速度）
            if self.wheel_stick_offset > 0 then
                self.wheel_stick_offset = math.max(0, self.wheel_stick_offset - 5)
            elseif self.wheel_stick_offset < 0 then
                self.wheel_stick_offset = math.min(0, self.wheel_stick_offset + 5)
            end
        end
        
    elseif part_type == "SWORD" then
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
        
    elseif part_type == "CANON" then
        -- CANON：crank 旋轉 + A 發射（支援 CANON1/2 等不同 ID）
        local pdata = _G.PartsData and _G.PartsData[self.active_part_id]
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
        
        -- 追蹤 A 按鈕狀態（用於顯示按鈕 UI）
        if playdate.buttonJustPressed(playdate.kButtonA) then
            self.canon_button_pressed = true
            if pdata and self.canon_fire_timer >= (pdata.fire_cooldown or 0.5) then
                local eq = _G.GameState.mech_stats.equipped_parts or {}
                for _, item in ipairs(eq) do
                    local ipdata = _G.PartsData and _G.PartsData[item.id]
                    if ipdata and ipdata.part_type == "CANON" and item.id == self.active_part_id then
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
                        -- 播放砲台發射音效
                        if _G.SoundManager and _G.SoundManager.playCanonFire then
                            _G.SoundManager.playCanonFire()
                        end
                        break
                    end
                end
            end
        elseif playdate.buttonJustReleased(playdate.kButtonA) then
            self.canon_button_pressed = false
        end
    elseif part_type == "FEET" then
        -- FEET：左右移動 + 跳躍
        local pdata = _G.PartsData and _G.PartsData["FEET"]
        local move_speed = (pdata and pdata.move_speed) or 3.0
        
        -- FEET 使用與 WHEEL 相同的 wheel_stick_offset 邏輯
        local max_stick_offset = 40
        
        local moving = false
        local direction = 0
        
        if playdate.buttonIsPressed(playdate.kButtonLeft) then
            dx = dx - move_speed
            moving = true
            direction = -1
            self.wheel_stick_offset = math.max(-max_stick_offset, self.wheel_stick_offset - 5)
        end
        if playdate.buttonIsPressed(playdate.kButtonRight) then
            dx = dx + move_speed
            moving = true
            direction = 1
            self.wheel_stick_offset = math.min(max_stick_offset, self.wheel_stick_offset + 5)
        end
        
        -- 如果沒有按鍵，wheel_stick_offset 回到中心
        if not playdate.buttonIsPressed(playdate.kButtonLeft) and not playdate.buttonIsPressed(playdate.kButtonRight) then
            if self.wheel_stick_offset > 0 then
                self.wheel_stick_offset = math.max(0, self.wheel_stick_offset - 5)
            elseif self.wheel_stick_offset < 0 then
                self.wheel_stick_offset = math.min(0, self.wheel_stick_offset + 5)
            end
        end
        
        self.feet_is_moving = moving
        self.feet_move_direction = direction
        
        -- A 鍵跳躍（只有在地面時才能跳）
        if playdate.buttonJustPressed(playdate.kButtonA) and self.is_grounded then
            local jump_vel = (pdata and pdata.jump_velocity) or -8.0
            self.velocity_y = jump_vel
            self.is_grounded = false
        end
        
    elseif part_type == "CLAW" then
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
        
        -- 檢測爪臂快速轉動以觸發攻擊
        local arm_angular_velocity = self.claw_arm_angle - self.claw_arm_angle_prev
        if math.abs(arm_angular_velocity) >= 2 then  -- 轉動速度達到 2 度/幀即可攻擊
            if not self.claw_last_attack_angle or math.abs(self.claw_arm_angle - self.claw_last_attack_angle) >= 20 then
                self.claw_is_attacking = true
                self.claw_last_attack_angle = self.claw_arm_angle
            else
                self.claw_is_attacking = false
            end
        else
            self.claw_is_attacking = false
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
                    
                    -- 計算臂旋轉產生的速度（角速度轉線速度）
                    local arm_length = 30  -- 臂長約 30 像素
                    local arm_angular_velocity = self.claw_arm_angle - self.claw_arm_angle_prev  -- 度/幀
                    local arm_angular_velocity_rad = math.rad(arm_angular_velocity)  -- 弧度/幀
                    
                    -- 從 parts_data 讀取投擲速度倍率
                    local throw_speed_mult = (pdata and pdata.throw_speed_mult) or 4.0
                    
                    -- 根據爪臂角度計算切線方向
                    -- 爪臂角度為正時向前（右），為負時向後（左）
                    local angle_rad = math.rad(self.claw_arm_angle)
                    
                    -- 切線速度 = 角速度 × 半徑 × 速度倍率，方向垂直於臂
                    -- 如果角速度為正（逆時針），石頭向左飛；為負（順時針），石頭向右飛
                    local vx = -arm_angular_velocity_rad * arm_length * throw_speed_mult  -- 加上速度倍率
                    local vy = 0  -- 初始 y 速度為 0，僅受重力影響
                    
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
    local part_type_for_gravity = self:getActivePartType()
    if part_type_for_gravity == "FEET" and not self.is_grounded then
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
    
    -- 從 parts_data 獲取抓取臨界值
    local pdata = _G.PartsData and _G.PartsData["CLAW"]
    local grip_threshold = pdata and pdata.grab_threshold or 10
    
    for _, stone in ipairs(stones or {}) do
        if not stone.is_grabbed and not stone.is_placed then
            local dx = (stone.x + stone.width/2) - claw_tip_x
            local dy = (stone.y + stone.height/2) - claw_tip_y
            local distance = math.sqrt(dx*dx + dy*dy)
            if distance < grab_range and self.claw_grip_angle < grip_threshold then  -- 爪子必須閉合才能抓
                stone.is_grabbed = true
                self.claw_grabbed_stone = stone
                print("LOG: Grabbed stone at distance=" .. math.floor(distance) .. ", grip_angle=" .. math.floor(self.claw_grip_angle))
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
function Projectile:update(dt, GRAVITY, entity_controller)
    if not self.active then return end
    
    -- 應用物理
    self.x = self.x + self.vx * dt
    -- 使用砲彈自帶的 gravity（若未設定則使用世界重力）
    local g = self.gravity or GRAVITY or 0.5
    self.vy = self.vy + g * dt
    self.y = self.y + self.vy * dt
    
    -- 檢查是否碰到地形
    local ground_height = entity_controller and entity_controller:getGroundHeight(self.x) or self.ground_y
    if self.y + self.height >= ground_height then
        self.y = ground_height - self.height
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
        attack_type = data.attack_type
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
                    end
                end
            else
                -- No animation table, mark as dead (animation timeout)
                self.is_alive = false
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
    
    -- 繪製敵人圖片或方塊
    if self.image then
        pcall(function() self.image:draw(screen_x, self.y) end)
    else
        gfx.setColor(gfx.kColorBlack)
        gfx.fillRect(screen_x, self.y, self.width, self.height)
    end
    
    -- 繪製 HP 條
    local hp_max = EnemyData[self.type_id].hp
    local hp_percent = self.hp / hp_max
    gfx.setColor(gfx.kColorBlack)
    gfx.fillRect(screen_x, self.y - 5, self.width * hp_percent, 3) 
    
    -- 繪製劍（SWORD_ENEMY）
    if self.attack_type == "SWING SWORD" then
        local enemy_data = EnemyData[self.type_id] or {}
        local pivot_offset_x = enemy_data.sword_pivot_offset_x or 0
        local pivot_offset_y = enemy_data.sword_pivot_offset_y or 0
        
        -- 世界座標下的旋轉軸心
        local pivot_x = screen_x + self.width / 2 + pivot_offset_x
        local pivot_y = self.y + self.height / 2 + pivot_offset_y
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

-- [[ ========================================== ]]
-- [[  Stone 类別 (可互動石頭) ]]
-- [[ ========================================== ]]

Stone = {}

function Stone:init(x, y, ground_y, target_id, image_path)
    local stone_img = nil
    local img_width = 16
    local img_height = 16
    
    -- 加載圖片並獲取尺寸
    if image_path then
        local ok, img = pcall(function()
            return playdate.graphics.image.new(image_path)
        end)
        if ok and img then
            stone_img = img
            local ok_size, w, h = pcall(function() return img:getSize() end)
            if ok_size and w and h then
                img_width = w
                img_height = h
            end
        end
    else
        -- 預設圖片
        pcall(function()
            stone_img = playdate.graphics.image.new("images/stone")
        end)
    end
    
    local stone = {
        x = x,
        y = y,
        width = img_width,
        height = img_height,
        vx = 0,
        vy = 0,
        is_grounded = (y >= ground_y - img_height),
        is_grabbed = false,  -- 是否被爪子抓住
        ground_y = ground_y,
        image = stone_img,
        damage = 15,  -- 砸到敵人的傷害
        target_id = target_id,  -- 指定要放到哪個目標
        is_placed = false  -- 是否已經放到指定目標
    }
    setmetatable(stone, { __index = Stone })
    return stone
end

function Stone:update(dt, gravity, entity_controller)
    if self.is_grabbed or self.is_placed then
        -- 被抓住或已放置時不更新物理
        return
    end
    
    -- 應用重力
    if not self.is_grounded then
        self.vy = self.vy + gravity
        self.y = self.y + self.vy
        
        -- 地形碰撞
        local ground_height = entity_controller and entity_controller:getGroundHeight(self.x) or self.ground_y
        if self.y >= ground_height - self.height then
            self.y = ground_height - self.height
            self.vy = 0
            self.vx = 0  -- 落地後停止
            self.is_grounded = true
        end
    end
    
    -- 水平移動
    self.x = self.x + self.vx
end

function Stone:draw(camera_x)
    if self.is_placed then
        return  -- 已放置的石頭不顯示
    end
    
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
    
    -- 初始化敵人
    for _, edata in ipairs(enemies_data or {}) do
        local enemy = Enemy:init(edata.x, edata.y, edata.type, safe_ground_y)
        table.insert(controller.enemies, enemy)
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
        
        -- 加載圖片並獲取尺寸
        if tdata.image then
            local ok, img = pcall(function()
                return playdate.graphics.image.new(tdata.image)
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
            target_width = tdata.width or 32
            target_height = tdata.height or 32
        end
        
        local target_y = tdata.y == 0 and (safe_ground_y - target_height) or tdata.y
        local target = {
            id = tdata.id or "target" .. #controller.delivery_targets + 1,
            x = tdata.x,
            y = target_y,
            width = target_width,
            height = target_height,
            image = target_img,
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
            enemy:update(dt, mech_x, mech_y, mech_width, mech_height, self)
            
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
                local sword_length = 30
                local sword_x = enemy.x + enemy.width / 2
                local sword_y = enemy.y + enemy.height / 2
                
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
            
            -- 檢查敵人砲彈是否擊中機甲
            if not p.is_player_bullet and self:checkMechCollision(mech_x, mech_y, mech_width, mech_height, p.x, p.y, p.width, p.height) then
                mech_damage_taken = mech_damage_taken + p.damage
                p.active = false -- 擊中後銷毀
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
                        
                        -- 擊中敵人
                        enemy.hp = enemy.hp - p.damage
                        p.active = false -- 砲彈銷毀
                        
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
                    
                    -- 播放擊中音效
                    if _G.SoundManager and _G.SoundManager.playHit then
                        _G.SoundManager.playHit()
                    end
                    
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
    for _, terrain in ipairs(self.terrain) do
        local screen_x = terrain.x - camera_x
        
        -- 只繪製在畫面內的地形
        if screen_x < 400 and screen_x + 64 > 0 then
            local x1, y1, x2, y2 = self:getTerrainPoints(terrain.type, screen_x, ground_y, terrain.height_offset)
            
            -- 繪製地形線
            gfx.drawLine(x1, y1, x2, y2)
            
            -- 使用填充遮擋背景：將地形線下方填滿至畫面底部，以遮住背景
            gfx.fillTriangle(x1, y1, x2, y2, x2, 240)
            gfx.fillTriangle(x1, y1, x1, 240, x2, 240)
        end
    end 

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
    
    -- 繪製石頭
    for _, stone in ipairs(self.stones) do
        stone:draw(camera_x)
    end
    
    -- 繪製目標物件
    for _, target in ipairs(self.delivery_targets) do
        if not target.is_completed then  -- 只繪製未完成的目標
            local screen_x = target.x - camera_x
            if screen_x >= -target.width and screen_x <= 400 then
                if target.image then
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
            end
        end
    end
    
    -- 繪製砲彈
    for _, projectile in ipairs(self.projectiles) do
        projectile:draw(camera_x)
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
            
            if terrain.type == "flat" then
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
    
    -- 只要機甲底部觸碰或低於地面，就設置停靠點
    if mech_bottom >= terrain_y then
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

-- [[ ========================================== ]]
-- [[  MechRenderer (機甲繪製) ]]
-- [[ ========================================== ]]

function MechController:drawMech(mech_x, mech_y, camera_x, mech_grid, game_state, feet_imagetable, feet_current_frame, entity_controller)
    local gfx = playdate.graphics
    local draw_x = mech_x - camera_x + self.hit_shake_offset
    
    -- 計算機甲中心點的地形角度
    local mech_center_x = mech_x + (mech_grid and mech_grid.cell_size or 16) * 1.5
    local terrain_angle = entity_controller and entity_controller:getTerrainAngle(mech_center_x) or 0
    
    -- 獲取已裝備零件列表
    local eq = game_state.mech_stats.equipped_parts or {}
    if #eq == 0 then return end
    
    -- 計算 FEET 的額外高度
    local feet_extra_height = 0
    for _, item in ipairs(eq) do
        if item.id == "FEET" then
            local feet_data = _G.PartsData and _G.PartsData["FEET"]
            if feet_data and feet_data._img then
                local ok, iw, ih = pcall(function() return feet_data._img:getSize() end)
                if ok and iw and ih then
                    local cell_size = mech_grid and mech_grid.cell_size or 16
                    feet_extra_height = ih - cell_size
                    if feet_extra_height < 0 then feet_extra_height = 0 end
                end
            end
            break
        end
    end
    
    local body_draw_y = mech_y
    
    -- 如果有地形角度，設置旋轉
    if terrain_angle ~= 0 then
        gfx.pushContext()
        -- 計算旋轉中心點（機甲底部中心）
        local mech_width = (mech_grid and mech_grid.cell_size or 16) * 3
        local mech_height = (mech_grid and mech_grid.cell_size or 16) * 2 + feet_extra_height
        local pivot_x = draw_x + mech_width / 2
        local pivot_y = body_draw_y + mech_height
        
        -- 應用旋轉（以底部中心為軸）
        gfx.setImageDrawMode(gfx.kDrawModeCopy)
    end
    
    -- 第一階段：繪製下排零件（row = 1）
    for _, item in ipairs(eq) do
        local pdata = _G.PartsData and _G.PartsData[item.id]
        local part_type = pdata and pdata.part_type
        local has_special_render = (part_type == "SWORD" or part_type == "CANON" or part_type == "FEET" or part_type == "CLAW")
        local should_skip = has_special_render and (item.id == self.active_part_id)
        if not should_skip and item.row == 1 then
            self:drawPart(item, draw_x, body_draw_y, mech_grid, feet_imagetable, feet_current_frame, terrain_angle)
        end
    end
    
    -- 第二階段：繪製上排零件（row = 2）
    for _, item in ipairs(eq) do
        local pdata = _G.PartsData and _G.PartsData[item.id]
        local part_type = pdata and pdata.part_type
        local has_special_render = (part_type == "SWORD" or part_type == "CANON" or part_type == "FEET" or part_type == "CLAW")
        local should_skip = has_special_render and (item.id == self.active_part_id)
        if not should_skip and item.row == 2 then
            self:drawPart(item, draw_x, body_draw_y, mech_grid, feet_imagetable, feet_current_frame, terrain_angle)
        end
    end
    
    -- 繪製激活的零件（覆蓋在上層）
    if self.active_part_id then
        for _, item in ipairs(eq) do
            if item.id == self.active_part_id then
                -- SWORD 和 CLAW 不使用地形旋轉，一次使用
                local part_rotation_angle = terrain_angle
                local pdata = _G.PartsData and _G.PartsData[item.id]
                if pdata and (pdata.part_type == "SWORD" or pdata.part_type == "CLAW") then
                    part_rotation_angle = 0
                end
                self:drawActivePart(item, draw_x, body_draw_y, mech_grid, feet_imagetable, feet_current_frame, part_rotation_angle)
                break
            end
        end
    end
    
    -- 恢復旋轉
    if terrain_angle ~= 0 then
        gfx.popContext()
    end
end

function MechController:drawPart(item, draw_x, body_draw_y, mech_grid, feet_imagetable, feet_current_frame, rotation_angle)
    rotation_angle = rotation_angle or 0
    local gfx = playdate.graphics
    local pdata = _G.PartsData and _G.PartsData[item.id]
    if not pdata or not pdata._img then return end
    
    local part_type = pdata.part_type
    local cell_size = mech_grid.cell_size
    local px = draw_x + (item.col - 1) * cell_size
    local py_top = body_draw_y + (mech_grid.rows - item.row) * cell_size
    local ok, iw, ih = pcall(function() return pdata._img:getSize() end)
    if not ok or not iw or not ih then return end
    
    local part_y
    if pdata.align_image_top then
        part_y = py_top
    else
        local offset_y = pdata.image_offset_y or 0
        part_y = py_top + (cell_size - ih) + offset_y
    end
    
    -- 特殊處理 FEET 動畫
    if part_type == "FEET" and feet_imagetable and self.feet_is_moving then
        local frame_image = feet_imagetable:getImage(feet_current_frame)
        if frame_image then
            if rotation_angle ~= 0 then
                pcall(function() frame_image:drawRotated(px + iw/2, part_y + ih/2, rotation_angle) end)
            else
                pcall(function() frame_image:draw(px, part_y) end)
            end
        end
    -- 特殊處理 CLAW（繪製底座 + 臂 + 爪子）
    elseif part_type == "CLAW" then
        self:drawClaw(px, part_y, iw, ih, pdata, rotation_angle)
    -- 特殊處理 CANON（繪製底座 + 砲管）
    elseif part_type == "CANON" then
        -- 繪製底座（不旋轉）
        if pdata._base_img then
            local ok_base, base_width, base_height = pcall(function() return pdata._base_img:getSize() end)
            if ok_base and base_height then
                local base_y = py_top + cell_size - base_height
                pcall(function() pdata._base_img:draw(px, base_y) end)
            else
                pcall(function() pdata._base_img:draw(px, py_top) end)
            end
        end
        -- 繪製砲管（旋轉）
        if rotation_angle ~= 0 then
            pcall(function() pdata._img:drawRotated(px + iw/2, part_y + ih/2, rotation_angle) end)
        else
            pcall(function() pdata._img:draw(px, part_y) end)
        end
    else
        -- 使用靜態圖片
        if rotation_angle ~= 0 then
            pcall(function() pdata._img:drawRotated(px + iw/2, part_y + ih/2, rotation_angle) end)
        else
            pcall(function() pdata._img:draw(px, part_y) end)
        end
    end
end

function MechController:drawClaw(px, part_y, iw, ih, pdata, rotation_angle)
    rotation_angle = rotation_angle or 0
    local gfx = playdate.graphics
    -- 繪製底座
    if rotation_angle ~= 0 then
        pcall(function() pdata._img:drawRotated(px + iw/2, part_y + ih/2, rotation_angle) end)
    else
        pcall(function() pdata._img:draw(px, part_y) end)
    end
    
    -- 計算底座中心點
    local pivot_x = px + iw / 2
    local pivot_y = part_y + ih / 2
    
    -- 繪製臂和爪子
    if pdata._arm_img then
        local arm_ok, arm_w, arm_h = pcall(function() return pdata._arm_img:getSize() end)
        if arm_ok and arm_w and arm_h then
            local angle_rad = math.rad(-self.claw_arm_angle)
            local cos_a = math.cos(angle_rad)
            local sin_a = math.sin(angle_rad)
            local arm_center_offset_x = arm_w / 2
            local rotated_dx = arm_center_offset_x * cos_a
            local rotated_dy = arm_center_offset_x * sin_a
            local arm_center_x = pivot_x + rotated_dx
            local arm_center_y = pivot_y + rotated_dy
            
            pcall(function() pdata._arm_img:drawRotated(arm_center_x, arm_center_y, -self.claw_arm_angle) end)
            
            -- 計算臂末端位置（爪子軸心）
            local arm_end_rotated_dx = arm_w * cos_a
            local arm_end_rotated_dy = arm_w * sin_a
            local claw_pivot_x = pivot_x + arm_end_rotated_dx
            local claw_pivot_y = pivot_y + arm_end_rotated_dy
            
            -- 繪製上爪
            if pdata._upper_img then
                local total_angle = -self.claw_arm_angle - self.claw_grip_angle + rotation_angle
                pcall(function() pdata._upper_img:drawRotated(claw_pivot_x, claw_pivot_y, total_angle) end)
            end
            
            -- 繪製下爪
            if pdata._lower_img then
                local total_angle = -self.claw_arm_angle + self.claw_grip_angle + rotation_angle
                pcall(function() pdata._lower_img:drawRotated(claw_pivot_x, claw_pivot_y, total_angle) end)
            end
        end
    end
end

function MechController:drawActivePart(item, draw_x, body_draw_y, mech_grid, feet_imagetable, feet_current_frame, rotation_angle)
    rotation_angle = rotation_angle or 0
    local gfx = playdate.graphics
    local pdata = _G.PartsData and _G.PartsData[item.id]
    if not pdata or not pdata._img then return end
    
    local cell_size = mech_grid.cell_size
    local part_type = pdata.part_type
    
    if part_type == "SWORD" then
        -- 計算 SWORD 位置
        local sx = (item.col - 1) * cell_size
        local sy = (mech_grid.rows - item.row) * cell_size
        local pivot_x = draw_x + sx + cell_size / 2
        local pivot_y = body_draw_y + sy + cell_size / 2
        
        gfx.pushContext()
        local ok, iw, ih = pcall(function() return pdata._img:getSize() end)
        if ok and iw and ih then
            local original_x = draw_x + sx
            local original_y = body_draw_y + sy + cell_size - ih
            local img_center_x = original_x + iw / 2
            local img_center_y = original_y + ih / 2
            local dx_from_pivot = img_center_x - pivot_x
            local dy_from_pivot = img_center_y - pivot_y
            local angle_rad = math.rad(-self.sword_angle)
            local cos_a = math.cos(angle_rad)
            local sin_a = math.sin(angle_rad)
            local rotated_dx = dx_from_pivot * cos_a - dy_from_pivot * sin_a
            local rotated_dy = dx_from_pivot * sin_a + dy_from_pivot * cos_a
            local new_center_x = pivot_x + rotated_dx
            local new_center_y = pivot_y + rotated_dy
            pdata._img:drawRotated(new_center_x, new_center_y, -self.sword_angle)
        end
        gfx.popContext()
        
    elseif part_type == "CANON" then
        -- 計算 CANON 位置（底座 + 砲管）
        local cx = (item.col - 1) * cell_size
        local cy = (mech_grid.rows - item.row) * cell_size
        local base_x = draw_x + cx
        
        -- 繪製底座（不旋轉）
        if pdata._base_img then
            local ok, base_width, base_height = pcall(function() return pdata._base_img:getSize() end)
            if ok and base_height then
                local base_y = body_draw_y + cy + cell_size - base_height
                pcall(function() pdata._base_img:draw(base_x, base_y) end)
            else
                pcall(function() pdata._base_img:draw(base_x, body_draw_y + cy) end)
            end
        end
        
        -- 繪製砲管（旋轉）
        if pdata._img then
            local pivot_x = draw_x + cx + cell_size / 2
            local pivot_y = body_draw_y + cy + cell_size / 2
            
            local ok, iw, ih = pcall(function() return pdata._img:getSize() end)
            if ok and iw and ih then
                local original_x = draw_x + cx
                local original_y = body_draw_y + cy + cell_size - ih
                local img_center_x = original_x + iw / 2
                local img_center_y = original_y + ih / 2
                local dx_from_pivot = img_center_x - pivot_x
                local dy_from_pivot = img_center_y - pivot_y
                local angle_rad = math.rad(-self.canon_angle)
                local cos_a = math.cos(angle_rad)
                local sin_a = math.sin(angle_rad)
                local rotated_dx = dx_from_pivot * cos_a - dy_from_pivot * sin_a
                local rotated_dy = dx_from_pivot * sin_a + dy_from_pivot * cos_a
                local new_center_x = pivot_x + rotated_dx
                local new_center_y = pivot_y + rotated_dy
                pdata._img:drawRotated(new_center_x, new_center_y, -self.canon_angle - rotation_angle)
            end
        end
        
    elseif part_type == "FEET" then
        -- 繪製 FEET（使用 drawPart）
        self:drawPart(item, draw_x, body_draw_y, mech_grid, feet_imagetable, feet_current_frame, rotation_angle)
    
    elseif part_type == "CLAW" then
        -- 繪製 CLAW（使用 drawPart）
        self:drawPart(item, draw_x, body_draw_y, mech_grid, feet_imagetable, feet_current_frame, rotation_angle)
    end
end

function MechController:drawUI(mech_stats, ui_start_x, ui_start_y, ui_cell_size, ui_grid_cols, ui_grid_rows)
    local gfx = playdate.graphics
    local eq = mech_stats.equipped_parts or {}
    
    -- 找出選中格子對應的零件ID（優先使用激活的零件，其次使用選中的零件）
    local selected_part_id_for_highlight = self.active_part_id
    if not selected_part_id_for_highlight and self.selected_part_slot then
        for _, item in ipairs(eq) do
            local slot_w = item.w or 1
            local slot_h = item.h or 1
            if self.selected_part_slot.col >= item.col and self.selected_part_slot.col < item.col + slot_w and
               self.selected_part_slot.row >= item.row and self.selected_part_slot.row < item.row + slot_h then
                selected_part_id_for_highlight = item.id
                break
            end
        end
    end
    
    -- 繪製控制格子和介面圖
    for _, item in ipairs(eq) do
        -- Part info logging removed
    end
    
    for r = 1, ui_grid_rows do
        for c = 1, ui_grid_cols do
            local cx = ui_start_x + (c - 1) * ui_cell_size
            local cy = ui_start_y + (ui_grid_rows - r) * ui_cell_size
            
            -- 查找是否有零件在這個列和對應的排
            -- r=2 對應組裝格 row=2（上排），r=1 對應組裝格 row=1（下排）
            local found_part = nil
            for _, item in ipairs(eq) do
                local slot_w = item.w or 1
                -- 檢查此列是否在零件範圍內，且零件的 row 與控制介面的 r 對應
                if item.row == r and c >= item.col and c < item.col + slot_w then
                    found_part = item
                    break
                end
            end
            
            if found_part then
                -- 只在起始格繪製介面圖
                if c == found_part.col then
                    self:drawPartUI(found_part.id, cx, cy, ui_cell_size)
                end
                -- 零件佔用的其他格子保持空白（不繪製任何東西）
            else
                -- 沒有零件，繪製 empty.png
                if self.ui_images and self.ui_images.empty then
                    pcall(function() self.ui_images.empty:draw(cx, cy) end)
                end
                -- 繪製邊框
                gfx.setColor(gfx.kColorBlack)
                gfx.setLineWidth(1)
                gfx.drawRect(cx, cy, ui_cell_size, ui_cell_size)
            end
        end
    end
    
    -- 繪製選中零件的粗外框（根據零件的 row 顯示在對應的控制介面排）
    if selected_part_id_for_highlight then
        for _, item in ipairs(eq) do
            if item.id == selected_part_id_for_highlight then
                local slot_w = item.w or 1
                local fx = ui_start_x + (item.col - 1) * ui_cell_size
                -- 根據零件的 row 決定 y 座標：row=2 在上方，row=1 在下方
                local fy = ui_start_y + (ui_grid_rows - item.row) * ui_cell_size
                local fw = slot_w * ui_cell_size
                local fh = ui_cell_size
                
                -- 繪製白色外框（確保在任何背景上都可見）
                gfx.setColor(gfx.kColorWhite)
                gfx.setLineWidth(5)
                gfx.drawRect(fx, fy, fw, fh)
                
                -- 繪製黑色內框
                gfx.setColor(gfx.kColorBlack)
                gfx.setLineWidth(3)
                gfx.drawRect(fx, fy, fw, fh)
                gfx.setLineWidth(1)
                break
            end
        end
    end
    
    -- 顯示激活零件資訊
    local info_x = ui_start_x + ui_grid_cols * ui_cell_size + 10
    if self.active_part_id then
        local part_type_for_info = self:getActivePartType()
        gfx.drawText("Active: " .. self.active_part_id, info_x, ui_start_y)
        if part_type_for_info == "SWORD" then
            gfx.drawText("Angle: " .. math.floor(self.sword_angle), info_x, ui_start_y + 15)
        elseif part_type_for_info == "CANON" then
            gfx.drawText("Angle: " .. math.floor(self.canon_angle), info_x, ui_start_y + 15)
        end
    else
        gfx.drawText("Select part (A)", info_x, ui_start_y)
    end
end

-- 繪製零件介面圖（根據零件類型）
function MechController:drawPartUI(part_id, x, y, size)
    local gfx = playdate.graphics
    local ui = self.ui_images or {}
    local pdata = _G.PartsData and _G.PartsData[part_id]
    
    if not pdata then
        print("WARNING: No parts data for " .. part_id)
        return
    end
    
    -- 取得零件類型
    local part_type = pdata.part_type
    
    -- 繪製 ui_panel（底圖）
    local panel_key = part_id .. "_panel"
    local panel_img = ui[panel_key]
    if panel_img then
        -- 根據零件類型決定是否旋轉
        if part_type == "CANON" then
            -- CANON 的 panel 不旋轉，直接繪製
            pcall(function() panel_img:draw(x, y) end)
            
            -- 繪製 canon_control（隨 crank 角度旋轉）
            local control_img = ui.canon_control
            if control_img then
                local crank_angle = playdate.getCrankPosition()
                local rotated_control = control_img:rotatedImage(crank_angle)
                if rotated_control then
                    local rw, rh = rotated_control:getSize()
                    -- 左對齊，垂直居中
                    pcall(function() rotated_control:draw(x, y + (size - rh)/2) end)
                end
            end
            
            -- 繪製 canon_button（根據按鈕狀態顯示不同 sprite）
            local button_table = ui.canon_button
            if button_table then
                -- sprite 1（左邊）= 未按下，sprite 2（右邊）= 按下
                local sprite_index = self.canon_button_pressed and 2 or 1
                local button_img = button_table:getImage(sprite_index)
                if button_img then
                    -- 獲取 panel 和 button 的寬度，將 button 對齊 panel 右邊
                    local panel_w, panel_h = panel_img:getSize()
                    local button_w, button_h = button_img:getSize()
                    local button_x = x + panel_w - button_w
                    pcall(function() button_img:draw(button_x, y) end)
                end
            end
        elseif part_type == "CLAW" then
            -- CLAW 的 panel 不旋轉，直接繪製
            pcall(function() panel_img:draw(x, y) end)
            
            -- 檢查是否為當前激活的零件
            local is_active = (self.active_part_id == part_id)
            
            -- 繪製 claw_control_v（左邊控制器，根據上下鍵狀態顯示不同 frame）
            local control_v_table = ui.claw_control_v
            if control_v_table then
                local frame_index = 1  -- 預設 frame 0 (1-based indexing)
                if is_active then
                    -- 只有在激活狀態才檢查按鍵狀態
                    local up_pressed = playdate.buttonIsPressed(playdate.kButtonUp)
                    local down_pressed = playdate.buttonIsPressed(playdate.kButtonDown)
                    if up_pressed then
                        frame_index = 2  -- frame 1 (上鍵按下)
                    elseif down_pressed then
                        frame_index = 3  -- frame 2 (下鍵按下)
                    end
                end
                
                local control_img = control_v_table:getImage(frame_index)
                if control_img then
                    -- 左對齊繪製
                    pcall(function() control_img:draw(x, y) end)
                end
            end
            
            -- 繪製 claw_control（右邊控制器，隨 crank 角度旋轉）
            local control_img = ui.claw_control
            if control_img then
                local crank_angle = is_active and playdate.getCrankPosition() or 0  -- 非激活狀態顯示預設角度
                local rotated_control = control_img:rotatedImage(crank_angle)
                if rotated_control then
                    local rw, rh = rotated_control:getSize()
                    -- 右對齊，垂直居中
                    local panel_w, panel_h = panel_img:getSize()
                    local control_x = x + panel_w - rw
                    pcall(function() rotated_control:draw(control_x, y + (size - rh)/2) end)
                end
            end
        else
            -- 其他零件直接繪製
            pcall(function() panel_img:draw(x, y) end)
        end
    end
    
    -- 繪製 ui_stick（如果有）
    local stick_img = ui[part_id .. "_stick"]
    if stick_img then
        if part_type == "SWORD" then
            -- SWORD 的 stick 需要旋轉，以格子中心為軸心，角度鏡射
            local center_x = x + size / 2
            local center_y = y + size / 2
            -- 鏡射角度以同步機甲上的 sword 旋轉
            local mirrored_angle = -self.sword_angle
            local rotated_img = stick_img:rotatedImage(mirrored_angle)
            if rotated_img then
                local rw, rh = rotated_img:getSize()
                -- 以格子中心點為旋轉中心繪製
                pcall(function() rotated_img:draw(center_x - rw/2, center_y - rh/2) end)
            end
        elseif part_type == "WHEEL" or part_type == "FEET" then
            -- WHEEL/FEET 的 stick 左右移動
            -- 假設 panel 是 96 像素寬（3 格）
            local panel_img_width = 96
            local center_x = x + panel_img_width / 2 + self.wheel_stick_offset
            local center_y = y + size / 2
            local sw, sh = stick_img:getSize()
            pcall(function() stick_img:draw(center_x - sw/2, center_y - sh/2) end)
        end
    end
end

return EntityController