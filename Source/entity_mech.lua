-- entity_mech.lua — MechController 類別「邏輯段」（輸入/零件操作/切換/物理）
-- [[ P1 拆檔 ]] 自 module_entities.lua 拆出；繪製段另在 entity_mech_render.lua
-- （兩檔都往同一個全域 MechController 表掛方法，由聚合器依序載入）。
-- A2 手感調校主要改這檔與 parts_data.lua。

import "CoreLibs/graphics"

local gfx = playdate.graphics

MechController = {}

-- [[ P4 滑行 ]] 無輸入時移動速度的每幀衰減係數（0~1，越小停得越快；A2 可調）
MechController.COAST_FRICTION = 0.85

-- [[ A3 ]] 切換焦點後的冷卻幀數（期間切換鍵不再觸發，避免連按視覺混亂；A2 可調）
MechController.FOCUS_SWITCH_COOLDOWN = 8

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

        -- [[ P4 滑行 ]] 水平移動速度（含滑行）。有輸入時=目標速度；
        -- 無輸入或焦點切走時按 COAST_FRICTION 逐幀衰減，模擬慣性滑行
        move_velocity = 0,
        move_input_active = false,  -- 本幀是否有移動輸入

        -- [[ A3 ]] 焦點切換視覺回饋
        focus_flash_timer = 0,  -- 切換當幀設為 8，逐幀遞減；期間面板高亮框放大、機體零件外框閃爍
        focus_switch_cooldown = 0,  -- 切換後冷卻，>0 時切換鍵不再觸發
        last_top_index = 1,  -- [[ 空間對應切換 ]] 上排最後使用的零件位置（回上排時還原）
        
        -- CLAW 相關
        claw_arm_angle = 0,  -- 臂的旋轉角度
        claw_arm_angle_prev = 0,  -- 上一幀的臂角度（用於計算旋轉速度）
        claw_grip_angle = 0,  -- 爪子的開合角度（0=閉合，max=張開）
        claw_grip_angle_prev = 0,  -- 上一幀的爪子角度（用於檢測開合狀態變化）
        claw_grabbed_stone = nil,  -- 當前抓住的石頭
        claw_is_closed = false,  -- 爪子開合狀態（A 鍵隨時切換，與是否抓到東西無關）
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
-- [[ P3 切換模型重構（InputSpec 定稿 D1） ]]
-- 廢除「方向鍵選格 → A 激活 → B 退出」三段式模態，
-- 改為：上/下鍵直接切換焦點（循環所有已裝零件，當幀生效，無確認步驟）。
-- 焦點 = active_part_id（永遠有值）；左右鍵/crank/A 由焦點零件使用。

-- [[ 空間對應切換 ]] 取得「可操作」零件，分排、各自左→右排序。
-- operable == false（如 GUN 全自動）的零件不進入切換循環。
function MechController:getOperableParts(mech_stats)
    local eq = (mech_stats and mech_stats.equipped_parts) or {}
    local bottom = {}
    local top = {}
    for _, item in ipairs(eq) do
        local pdata = _G.PartsData and _G.PartsData[item.id]
        if not (pdata and pdata.operable == false) then
            if item.row == 1 then
                bottom[#bottom + 1] = item
            else
                top[#top + 1] = item
            end
        end
    end
    table.sort(bottom, function(a, b) return a.col < b.col end)
    table.sort(top, function(a, b) return a.col < b.col end)
    return bottom, top
end

-- 設定焦點（當幀生效）
function MechController:setFocus(item)
    self.active_part_id = item.id
    self.selected_part_slot = {col = item.col, row = item.row}
    -- [[ A3 ]] 切換瞬間的視覺回饋：面板高亮框彈跳、機體零件外框閃爍
    self.focus_flash_timer = 8
    -- [[ A3 ]] 切換冷卻：一小段時間內不能再切，避免連按視覺混亂
    self.focus_switch_cooldown = MechController.FOCUS_SWITCH_COOLDOWN
end

-- [[ 空間對應切換（2026-07-11 定案）]]
-- 上/下鍵 = 換排（上=去上排、下=回下排；回上排時記住上次用的零件）；
-- 左/右鍵 = 焦點在「上排」時於上排零件間橫移（方向與畫面排列一致）；
--           焦點在下排時左右鍵歸移動零件使用（handlePartOperation），此處不碰。
-- 無操作零件（operable=false，如 GUN）不可選中。
function MechController:handleSelection(mech_stats)
    -- [[ A3 ]] 切換視覺回饋倒數（每幀一次）
    if self.focus_flash_timer and self.focus_flash_timer > 0 then
        self.focus_flash_timer = self.focus_flash_timer - 1
    end

    local bottom, top = self:getOperableParts(mech_stats)
    if #bottom == 0 and #top == 0 then return end

    -- 找出目前焦點的排與位置
    local cur_row = nil
    local cur_idx = nil
    for i, item in ipairs(bottom) do
        if item.id == self.active_part_id then cur_row = 1; cur_idx = i; break end
    end
    if not cur_row then
        for i, item in ipairs(top) do
            if item.id == self.active_part_id then cur_row = 2; cur_idx = i; break end
        end
    end

    -- 開場（或焦點失效）：預設焦點 = 下排移動零件（沒有則上排第一個）
    if not cur_row then
        self:setFocus(bottom[1] or top[1])
        -- 開場自動鎖定不算「切換」，不吃冷卻
        self.focus_switch_cooldown = 0
        return
    end

    -- [[ A3 ]] 切換冷卻中：不接受再切換
    if self.focus_switch_cooldown and self.focus_switch_cooldown > 0 then
        self.focus_switch_cooldown = self.focus_switch_cooldown - 1
        return
    end

    if playdate.buttonJustPressed(playdate.kButtonUp) then
        -- 上：去上排（記住上次用的上排零件）
        if cur_row == 1 and #top > 0 then
            local ti = math.min(self.last_top_index or 1, #top)
            self.last_top_index = ti
            self:setFocus(top[ti])
        end
    elseif playdate.buttonJustPressed(playdate.kButtonDown) then
        -- 下：回下排
        if cur_row == 2 and #bottom > 0 then
            self.last_top_index = cur_idx
            self:setFocus(bottom[1])
        end
    elseif cur_row == 2 and playdate.buttonJustPressed(playdate.kButtonLeft) then
        -- 左：上排內向左橫移
        if cur_idx > 1 then
            self.last_top_index = cur_idx - 1
            self:setFocus(top[cur_idx - 1])
        end
    elseif cur_row == 2 and playdate.buttonJustPressed(playdate.kButtonRight) then
        -- 右：上排內向右橫移
        if cur_idx < #top then
            self.last_top_index = cur_idx + 1
            self:setFocus(top[cur_idx + 1])
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

-- 檢查發射方向是否被已安裝的零件阻擋（不包括當前發射的零件）
function MechController:isFiringDirectionBlocked(firing_direction, active_part_id)
    local eq = _G.GameState and _G.GameState.mech_stats and _G.GameState.mech_stats.equipped_parts
    if not eq then return false end
    
    for _, item in ipairs(eq) do
        -- 跳過當前發射的零件（不要自己擋自己）
        if active_part_id and item.id == active_part_id then
            goto skip_part
        end
        
        local pdata = _G.PartsData and _G.PartsData[item.id]
        if pdata and pdata.block_directions then
            for _, blocked_dir in ipairs(pdata.block_directions) do
                if blocked_dir == firing_direction then
                    return true  -- 發射方向被阻擋
                end
            end
        end
        
        ::skip_part::
    end
    
    return false  -- 發射方向未被阻擋
end

-- 處理零件操作（返回移動增量）
function MechController:handlePartOperation(mech_x, mech_y, mech_grid, entity_controller)
    local dx = 0
    local MOVE_SPEED = 2.0
    
    -- [[ P4 ]] 不再於無焦點時提前 return——滑行衰減（函式尾）任何情況都要執行
    local part_type = self:getActivePartType()

    if part_type == "WHEEL" then
        -- WHEEL：左右移動
        -- WHEEL 是 3x1 格，寬度 = 3*32 + 2*5 = 106 像素
        -- wheel_stick 可以從最左移動到最右，範圍大約是 panel 寬度的一半，減去 stick 寬度的一半
        -- 假設 panel 總寬 106，stick 寬 10，則最大偏移 = (106/2) - (10/2) = 48
        local max_stick_offset = 40

        if playdate.buttonIsPressed(playdate.kButtonLeft) then
            self.move_velocity = -MOVE_SPEED  -- [[ P4 ]] 改寫入速度，滑行統一在函式尾處理
            self.move_input_active = true
            self.wheel_stick_offset = math.max(-max_stick_offset, self.wheel_stick_offset - 5)
        elseif playdate.buttonIsPressed(playdate.kButtonRight) then
            self.move_velocity = MOVE_SPEED
            self.move_input_active = true
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
                -- 檢查右上方發射方向是否被阻擋（不包括CANON本身）
                if self:isFiringDirectionBlocked("RIGHT_UP", self.active_part_id) then
                    -- 發射方向被阻擋，不發射
                else
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

                            -- [[ 斜坡跟隨 ]] 砲口位置與發射方向套用機體傾斜
                            canon_x, canon_y, vx, vy = self:applyMechTilt(canon_x, canon_y, vx, vy, mech_x, mech_y, mech_grid, entity_controller)

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
            self.move_velocity = -move_speed  -- [[ P4 ]] 改寫入速度，滑行統一在函式尾處理
            self.move_input_active = true
            moving = true
            direction = -1
            self.wheel_stick_offset = math.max(-max_stick_offset, self.wheel_stick_offset - 5)
        end
        if playdate.buttonIsPressed(playdate.kButtonRight) then
            self.move_velocity = move_speed
            self.move_input_active = true
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
        -- [[ P3 CLAW 改制（InputSpec 定稿 D4） ]]
        -- crank = 臂上下轉動；A = 抓/放切換（當幀執行）；爪子開合隨抓/放自動演出
        local pdata = _G.PartsData and _G.PartsData["CLAW"]
        local arm_angle_min = pdata and pdata.arm_angle_min or -90
        local arm_angle_max = pdata and pdata.arm_angle_max or 90
        local claw_angle_min = pdata and pdata.claw_angle_min or 0
        local claw_angle_max = pdata and pdata.claw_angle_max or 45
        local crank_ratio = pdata and pdata.crank_degrees_per_rotation or 180  -- crank 1 圈 = 臂轉幾度（A2 可調）
        local grip_anim_speed = pdata and pdata.grip_anim_speed or 5  -- 開合自動演出速度（度/幀）

        -- crank 控制臂的旋轉
        local crankChange = playdate.getCrankChange()
        if crankChange and math.abs(crankChange) > 0 then
            local arm_delta = (crankChange / 360.0) * crank_ratio
            self.claw_arm_angle = self.claw_arm_angle + arm_delta
            if self.claw_arm_angle > arm_angle_max then
                self.claw_arm_angle = arm_angle_max
            elseif self.claw_arm_angle < arm_angle_min then
                self.claw_arm_angle = arm_angle_min
            end
        end

        -- 檢測爪臂快速轉動以觸發攻擊（沿用：crank 甩臂即攻擊）
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

        -- A 鍵：隨時切換爪子開合（不依賴附近有無石頭，空揮也有回饋）
        -- 閉合時若範圍內有石頭 → 順便抓住；張開時若抓著 → 放開/投擲
        if playdate.buttonJustPressed(playdate.kButtonA) then
            if self.claw_is_closed then
                -- 張開
                self.claw_is_closed = false
                if self.claw_grabbed_stone then
                    -- 放開/投擲（沿用原投擲計算：臂的角速度轉為切線速度）
                    local stone = self.claw_grabbed_stone
                    local arm_length = 30  -- 臂長約 30 像素
                    local arm_angular_velocity_rad = math.rad(arm_angular_velocity)
                    local throw_speed_mult = (pdata and pdata.throw_speed_mult) or 4.0
                    local vx = -arm_angular_velocity_rad * arm_length * throw_speed_mult
                    local vy = 0  -- 初始 y 速度為 0，僅受重力影響
                    stone:launch(vx, vy)
                    self.claw_grabbed_stone = nil
                    print("LOG: Released stone with vx=" .. math.floor(vx) .. " (arm angular vel=" .. math.floor(arm_angular_velocity) .. ")")
                end
            else
                -- 閉合；嘗試抓取（由 state_mission 檢查爪尖範圍並執行 tryGrabStone）
                self.claw_is_closed = true
                self.try_grab = true
            end
        end

        -- 爪子開合：隨開合狀態自動演出（閉合/張開由 A 鍵決定，與是否抓到無關）
        local grip_target = self.claw_is_closed and claw_angle_min or claw_angle_max
        if self.claw_grip_angle < grip_target then
            self.claw_grip_angle = math.min(grip_target, self.claw_grip_angle + grip_anim_speed)
        elseif self.claw_grip_angle > grip_target then
            self.claw_grip_angle = math.max(grip_target, self.claw_grip_angle - grip_anim_speed)
        end
        self.claw_grip_angle_prev = self.claw_grip_angle

        -- 更新上一幀的臂角度
        self.claw_arm_angle_prev = self.claw_arm_angle
    end

    -- [[ P4 滑行（決策 #1）]] 無移動輸入（含焦點不在移動零件）時，
    -- 速度按 COAST_FRICTION 逐幀衰減——切走焦點後機體滑行減速，而非急停
    if not self.move_input_active then
        self.move_velocity = self.move_velocity * MechController.COAST_FRICTION
        if math.abs(self.move_velocity) < 0.05 then
            self.move_velocity = 0
            self.feet_is_moving = false  -- 滑行結束才停走路動畫
        end
    end
    self.move_input_active = false
    dx = dx + self.move_velocity

    return dx
end

-- [[ 斜坡跟隨 ]] 與 drawMechTilted 完全一致的機體傾斜變換：
-- 繞「機體底部中心」旋轉 terrain_angle。發射點、爪尖等「邏輯座標」
-- 必須套用同一變換，才會與畫面上傾斜後的零件位置/朝向一致。
-- 傳入 vx, vy 時連速度向量一起旋轉（發射方向跟著機體傾斜）。
function MechController:applyMechTilt(x, y, vx, vy, mech_x, mech_y, mech_grid, entity_controller)
    local cell = (mech_grid and mech_grid.cell_size) or 16
    local terrain_angle = entity_controller and entity_controller:getTerrainAngle(mech_x + cell * 1.5) or 0
    if terrain_angle == 0 then
        return x, y, vx, vy
    end

    -- 底部中心（含 FEET 超出格子的高度，與 drawMech 的計算一致）
    local feet_extra = 0
    local eq = (_G.GameState and _G.GameState.mech_stats and _G.GameState.mech_stats.equipped_parts) or {}
    for _, item in ipairs(eq) do
        if item.id == "FEET" then
            local fd = _G.PartsData and _G.PartsData["FEET"]
            if fd and fd._img then
                local ok, _, ih = pcall(function() return fd._img:getSize() end)
                if ok and ih then
                    feet_extra = math.max(0, ih - cell)
                end
            end
            break
        end
    end
    local pivot_x = mech_x + ((mech_grid and mech_grid.cols) or 3) * cell / 2
    local pivot_y = mech_y + ((mech_grid and mech_grid.rows) or 2) * cell + feet_extra

    local rad = math.rad(terrain_angle)
    local c, s = math.cos(rad), math.sin(rad)
    local rx, ry = x - pivot_x, y - pivot_y
    local nx = pivot_x + (rx * c - ry * s)
    local ny = pivot_y + (rx * s + ry * c)
    local nvx, nvy = vx, vy
    if vx and vy then
        nvx = vx * c - vy * s
        nvy = vx * s + vy * c
    end
    return nx, ny, nvx, nvy
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
                -- 檢查右方發射方向是否被阻擋（不包括GUN本身）
                if self:isFiringDirectionBlocked("RIGHT", "GUN") then
                    -- 發射方向被阻擋，不發射
                    break
                end
                
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

                -- [[ 斜坡跟隨 ]] 槍口位置與發射方向套用機體傾斜
                gun_x, gun_y, vx, vy = self:applyMechTilt(gun_x, gun_y, vx, vy, mech_x, mech_y, mech_grid, entity_controller)

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
    
    -- [[ P4 ]] FEET 專屬重力已移除：跳躍初速由 state_mission 一次性取走
    -- （velocity_y 歸零），之後統一由任務物理施加重力，與焦點無關
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
-- [[ P3 CLAW 改制 ]] 舊制要求「爪子閉合才能抓」（開合由玩家 crank 控制）；
-- 新制 A 鍵當幀抓取，只看範圍——爪子閉合是抓到後的自動演出，不是前置條件。
function MechController:tryGrabStone(claw_tip_x, claw_tip_y, stones, grab_range)
    grab_range = grab_range or 20

    for _, stone in ipairs(stones or {}) do
        if not stone.is_grabbed and not stone.is_placed then
            local dx = (stone.x + stone.width/2) - claw_tip_x
            local dy = (stone.y + stone.height/2) - claw_tip_y
            local distance = math.sqrt(dx*dx + dy*dy)
            if distance < grab_range then
                stone.is_grabbed = true
                self.claw_grabbed_stone = stone
                print("LOG: Grabbed stone at distance=" .. math.floor(distance))
                return true
            end
        end
    end
    return false
end
