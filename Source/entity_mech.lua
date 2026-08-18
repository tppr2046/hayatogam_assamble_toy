-- entity_mech.lua — MechController 類別「邏輯段」（輸入/零件操作/切換/物理）
-- [[ P1 拆檔 ]] 自 module_entities.lua 拆出；繪製段另在 entity_mech_render.lua
-- （兩檔都往同一個全域 MechController 表掛方法，由聚合器依序載入）。
-- A2 手感調校主要改這檔與 parts_data.lua。

import "CoreLibs/graphics"

local gfx = playdate.graphics

MechController = {}

-- [[ 版面 ]] WHEEL/FEET 面板上滑塊的最大左右偏移（px）。
-- 由「軌道寬 − 滑塊寬」推出：wheel_panel 64px、wheel_stick 18px → (64-18)/2 = 23。
-- ★ 2026-08-08 面板由 3 格(96) 縮成 2 格(64) 時一併從 40 改成 23，否則滑塊會跑出軌道。
local STICK_MAX_OFFSET = 23

-- [[ 跳躍 ]] 重力（px/幀²）。★必須與 state_mission.lua 的 GRAVITY 一致，
-- 因為跳躍初速度是由「想跳多高」反推出來的：v = sqrt(2 * g * h)。
local MECH_GRAVITY = 0.5

-- [[ P4 滑行 ]] 無輸入時移動速度的每幀衰減係數（0~1，越小停得越快；A2 可調）。
-- 這是**預設值**；零件可用 parts_data 的 `coast_friction` 個別覆寫
-- （2026-08-07：輪子該滑、腿該停得快，兩者不該共用同一個值）。
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
        -- [[ 修正 ]] CANON 角度改為「每個零件各自保存」（key = 零件 id）：
        -- 兩門 CANON 不再共用角度；離開焦點時各自維持原本角度。
        canon_angles = {},
        canon_knob_angles = {},   -- 操作面板旋鈕角度（僅焦點中的零件會更新→非焦點面板不動作）
        canon_fire_timer = 0,
        canon_button_pressed = false,  -- 按鈕是否按下
        -- [[ 跳躍 ]] 每幀由 handlePartOperation 更新
        can_jump = false,              -- 目前焦點零件 × 核心加成後能不能跳（面板據此決定畫不畫跳躍鈕）
        jump_button_pressed = false,   -- 跳躍鈕的按下狀態（面板顯示用）
        
        -- GUN 相關
        -- ★ 2026-08-11 改成**每個零件一個計時器**（key = 零件 id）。
        --   舊版是單一 gun_fire_timer，GUN 與 GUN2(雷射) 併裝時會互搶冷卻。
        gun_fire_timers = {},
        gun_button_pressed = false,   -- 雷射槍(GUN2)的 A 鈕按下狀態，面板顯示用
        
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
    
    -- 載入 CLAW 開合開關的按鈕圖表
    -- [[ 2026-08-10 ]] 由佔位的 claw_control_v（3 格，1=關/2=開）換成專屬圖
    -- claw-button-table-32-32（2 格，**1=開 / 2=夾起**——注意順序與舊圖相反）。
    -- 舊圖已刪除，不再有 fallback。
    local ok_claw_button, claw_button_table = pcall(function()
        return playdate.graphics.imagetable.new("images/claw-button")
    end)
    if ok_claw_button and claw_button_table then
        mc.ui_images.claw_button = claw_button_table
    else
        print("WARNING: Failed to load claw-button.pdt")
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

-- [[ 跳躍 ]] 目前焦點零件的實際跳躍高度（px）＝ 零件 jump_height × 核心 jump_mult。
-- 回傳 0 代表「不能跳」——可能是焦點不是移動零件，也可能是核心加成為 0（CORE1）。
-- 操作面板的跳躍鈕也用這個值決定要不要顯示（0 就不畫）。
function MechController:getJumpHeight()
    local pdata = _G.PartsData and _G.PartsData[self.active_part_id]
    local base = (pdata and pdata.jump_height) or 0
    if base <= 0 then return 0 end
    local core = _G.CoreData and _G.CoreData.current and _G.CoreData.current()
    local mult = (core and core.jump_mult) or 0
    return base * mult
end

-- [[ 修正 ]] 取得某門 CANON 的仰角（每個零件各自保存；未設過則為 0）
function MechController:getCanonAngle(part_id)
    if not part_id then return 0 end
    self.canon_angles = self.canon_angles or {}
    return self.canon_angles[part_id] or 0
end

-- [[ 修正 ]] 取得某門 CANON 的面板旋鈕角度（僅焦點中的零件會更新→非焦點面板靜止）
function MechController:getCanonKnobAngle(part_id)
    if not part_id then return 0 end
    self.canon_knob_angles = self.canon_knob_angles or {}
    return self.canon_knob_angles[part_id] or 0
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

    -- [[ 跳躍 ]] 2026-08-07：跳躍不再是 FEET 專屬。凡是焦點停在「有 jump_height 的
    -- 下層零件」（FEET/WHEEL）都能跳，各零件高度不同，再乘上核心的 jump_mult。
    -- 放在分支之外統一處理，避免每個移動零件各寫一份。
    -- ★ 仍然綁在「焦點」上：焦點在 CANON/CLAW 時 A 是發射/抓放，不會誤觸跳躍。
    local jump_h = self:getJumpHeight()
    self.can_jump = (jump_h > 0)          -- 供操作面板決定要不要畫跳躍鈕
    if self.can_jump and playdate.buttonJustPressed(playdate.kButtonA) and self.is_grounded then
        -- 由高度反推初速度：h = v² / (2g) → v = sqrt(2gh)
        -- g 必須與 state_mission.lua 的 GRAVITY 一致（0.5 / 幀²）
        self.velocity_y = -math.sqrt(2 * MECH_GRAVITY * jump_h)
        self.is_grounded = false
        self.jump_button_pressed = true
    end
    if not playdate.buttonIsPressed(playdate.kButtonA) then
        self.jump_button_pressed = false
    end

    if part_type == "WHEEL" then
        -- WHEEL：左右移動
        -- WHEEL 是 3x1 格，寬度 = 3*32 + 2*5 = 106 像素
        -- wheel_stick 可以從最左移動到最右，範圍大約是 panel 寬度的一半，減去 stick 寬度的一半
        -- 假設 panel 總寬 106，stick 寬 10，則最大偏移 = (106/2) - (10/2) = 48
        local max_stick_offset = STICK_MAX_OFFSET

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

        -- [[ 修正 ]] 只更新「焦點中」這門砲的角度與面板旋鈕；其他 CANON 維持原角度、面板不動
        local cid = self.active_part_id
        self.canon_knob_angles[cid] = playdate.getCrankPosition()

        local crankChange = playdate.getCrankChange()
        if crankChange and math.abs(crankChange) > 0 then
            -- crank 轉動量轉換為 canon 角度變化：crankChange 是度數，除以 360 得到圈數，乘以 crank_ratio 得到 canon 角度變化
            local canon_delta = (crankChange / 360.0) * crank_ratio
            local ang = self:getCanonAngle(cid) + canon_delta

            -- 限制角度在範圍內
            if ang > angle_max then
                ang = angle_max
            elseif ang < angle_min then
                ang = angle_min
            end
            self.canon_angles[cid] = ang
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
                            -- 樞紐＝格中心 + barrel_offset_y（砲管繞此旋轉，**必須與繪製一致**，
                            -- 見 entity_mech_render.lua 的 drawActivePart；否則砲彈會從砲管下方飛出）
                            local pivot_x = mech_x + (item.col - 1) * cell_size + cell_size / 2
                            local pivot_y = mech_y + (mech_grid.rows - item.row) * cell_size + cell_size / 2
                                            + (pdata.barrel_offset_y or 0)

                            -- 使用與敵人相同的計算方式
                            local base_speed = entity_controller.player_move_speed or 2.0
                            local speed_mult = pdata.projectile_speed_mult or 1.0
                            local speed = base_speed * speed_mult

                            local angle_rad = math.rad(self:getCanonAngle(item.id))
                            local dir_x = math.cos(angle_rad)
                            local dir_y = -math.sin(angle_rad)
                            local vx = dir_x * speed
                            local vy = dir_y * speed

                            -- [[ 修正 ]] 砲彈從砲口發射：樞紐 + 砲管方向 × 砲管長（格中心→砲口）
                            local ok_iw, iw = pcall(function() return pdata._img:getSize() end)
                            local barrel_len = ((ok_iw and iw) or (cell_size * 2)) - cell_size / 2
                            if barrel_len < cell_size / 2 then barrel_len = cell_size / 2 end
                            local canon_x = pivot_x + dir_x * barrel_len
                            local canon_y = pivot_y + dir_y * barrel_len
                            local dmg = pdata.projectile_damage or 10
                            local grav_mult = pdata.projectile_grav_mult or 1.0

                            -- [[ 斜坡跟隨 ]] 砲口位置與發射方向套用機體傾斜
                            canon_x, canon_y, vx, vy = self:applyMechTilt(canon_x, canon_y, vx, vy, mech_x, mech_y, mech_grid, entity_controller)

                            -- [[ CANON3 ]] 有 blast_radius 的砲彈落地/命中時會範圍爆炸
                            entity_controller:addPlayerProjectile(canon_x, canon_y, vx, vy, dmg, grav_mult,
                                                                  nil, pdata.blast_radius, pdata.blast_damage)
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
    elseif part_type == "GUN" then
        -- [[ 雷射槍 GUN2 2026-08-11 ]] 手動：焦點在它身上時按 A 發射一道**會往前飛的貫穿光束**。
        -- （全自動的 GUN 是 operable=false，根本不會成為焦點，不會走到這裡。）
        -- ★ pdata 必須在這裡自己取——本函式沒有函式層級的 pdata，
        --   漏掉的話它會是 nil、下面的守衛永遠 false，**按 A 完全沒反應且不會報錯**。
        local pdata = _G.PartsData and _G.PartsData[self.active_part_id]
        if playdate.buttonJustPressed(playdate.kButtonA) then
            self.gun_button_pressed = true
            local tmr = self.gun_fire_timers[self.active_part_id] or 999
            if pdata and tmr >= (pdata.fire_cooldown or 1.0)
               and not self:isFiringDirectionBlocked("RIGHT", self.active_part_id) then
                local eq = _G.GameState.mech_stats.equipped_parts or {}
                for _, item in ipairs(eq) do
                    if item.id == self.active_part_id then
                        local cell_size = mech_grid.cell_size
                        -- ★ 槍口在圖的**右端**（量自 gun02.png：x=31, y=8），
                        --   所以由零件左上角推算，不是格子中心 —— 否則光束會從機身中間長出來。
                        local lx = mech_x + (item.col - 1) * cell_size + (pdata.muzzle_x or 0)
                        local ly = mech_y + (mech_grid.rows - item.row) * cell_size + (pdata.muzzle_y or 8)
                        local base_speed = entity_controller.player_move_speed or 2.0
                        local speed = base_speed * (pdata.laser_speed_mult or 100)
                        local vx, vy
                        lx, ly, vx, vy = self:applyMechTilt(lx, ly, speed, 0, mech_x, mech_y, mech_grid, entity_controller)
                        entity_controller:addPlayerLaser(lx, ly, vx, vy,
                            pdata.laser_length, pdata.laser_thickness,
                            pdata.projectile_damage, pdata.laser_range)
                        self.gun_fire_timers[self.active_part_id] = 0
                        if _G.SoundManager and _G.SoundManager.playCanonFire then
                            _G.SoundManager.playCanonFire()
                        end
                        break
                    end
                end
            end
        elseif playdate.buttonJustReleased(playdate.kButtonA) then
            self.gun_button_pressed = false
        end
    elseif part_type == "FEET" then
        -- FEET：左右移動 + 跳躍
        local pdata = _G.PartsData and _G.PartsData["FEET"]
        local move_speed = (pdata and pdata.move_speed) or 3.0
        
        -- FEET 使用與 WHEEL 相同的 wheel_stick_offset 邏輯
        local max_stick_offset = STICK_MAX_OFFSET
        
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
        
        -- [[ 跳躍 ]] 已移到分支之外（見 handlePartOperation 開頭），
        -- 因為 WHEEL 也能跳，不再是 FEET 專屬。

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
    -- 速度按 coast_friction 逐幀衰減——切走焦點後機體滑行減速，而非急停。
    -- 係數取「目前裝在機體上的移動零件」，找不到就用預設值。
    if not self.move_input_active then
        local friction = MechController.COAST_FRICTION
        local eq = _G.GameState and _G.GameState.mech_stats
                   and _G.GameState.mech_stats.equipped_parts or {}
        for _, item in ipairs(eq) do
            local pd = _G.PartsData and _G.PartsData[item.id]
            if pd and pd.coast_friction and (pd.part_type == "FEET" or pd.part_type == "WHEEL") then
                friction = pd.coast_friction
                break
            end
        end
        self.move_velocity = self.move_velocity * friction
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
    
    -- GUN 類零件自動發射
    -- ★ 2026-08-11：由寫死的 `item.id == "GUN"` 改成 **`pdata.part_type == "GUN"`**，
    --   之後再加槍械變體（如雷射槍 GUN2）只要在 parts_data 宣告即可，不必回來改這裡。
    -- ★ 冷卻計時器**所有槍都要累計**（含手動的雷射槍），只有「自動開火」這段跳過手動零件；
    --   否則手動槍的計時器永遠不會前進，按 A 就再也打不出第二發。
    self.gun_fire_timers = self.gun_fire_timers or {}
    local eq = _G.GameState.mech_stats.equipped_parts or {}
    for _, item in ipairs(eq) do
        local pdata = _G.PartsData and _G.PartsData[item.id]
        if pdata and pdata.part_type == "GUN" and pdata.fire_cooldown then
            -- 每個零件各自累計冷卻（多把槍併裝時不會互搶）
            -- ★ 首次見到這個零件時的初值：**手動槍給滿**（一進關卡按 A 就能打），
            --   自動槍給 0（維持原本「等一個 CD 才開第一槍」的節奏，不改既有手感）。
            if self.gun_fire_timers[item.id] == nil then
                self.gun_fire_timers[item.id] = pdata.operable and pdata.fire_cooldown or 0
            end
            local tmr = self.gun_fire_timers[item.id] + dt
            self.gun_fire_timers[item.id] = tmr
            -- ★ operable=true 的槍是**手動**（雷射槍 GUN2），由 updateActivePart 按 A 發射，
            --   不能在這裡自動打掉，否則會變成「自動 + 手動」兩邊都發。
            -- [[ §15.9 反向槍 ]] 發射方向不再寫死 —— 由 parts_data 的 `fire_direction` 決定
            -- （沒設就是 "RIGHT"，所以既有的 GUN/GUN2 行為完全不變）。
            -- ★ 擋位判斷也要用同一個方向，否則反向槍會去檢查右側有沒有被擋。
            local fire_dir = pdata.fire_direction or "RIGHT"
            if (not pdata.operable) and tmr >= pdata.fire_cooldown
               and not self:isFiringDirectionBlocked(fire_dir, item.id) then
                local cell_size = mech_grid.cell_size
                -- ★ 槍口位置要吃 image_offset_x/y ——「零件相對格子的位移」，
                --   與 entity_mech_render / state_hq / state_mission 的繪製端**讀同一組欄位**。
                --   高位槍靠 y = −8 把圖抬高，子彈發射點必須跟著抬，否則會從腳邊射出來。
                local gun_x = mech_x + (item.col - 1) * cell_size + cell_size / 2
                                     + (pdata.image_offset_x or 0)
                local gun_y = mech_y + (mech_grid.rows - item.row) * cell_size + cell_size / 2
                                     + (pdata.image_offset_y or 0)

                -- 使用與敵人相同的計算方式
                local base_speed = entity_controller.player_move_speed or 2.0
                local speed_mult = pdata.projectile_speed_mult or 1.0
                local dir_sign = (fire_dir == "LEFT") and -1 or 1
                local vx = base_speed * speed_mult * dir_sign  -- 水平發射（負值＝往左）
                local vy = 0  -- GUN 直射，垂直速度為 0
                local dmg = pdata.projectile_damage or 5
                local grav_mult = pdata.projectile_grav_mult or 1.0

                -- [[ 斜坡跟隨 ]] 槍口位置與發射方向套用機體傾斜
                gun_x, gun_y, vx, vy = self:applyMechTilt(gun_x, gun_y, vx, vy, mech_x, mech_y, mech_grid, entity_controller)

                entity_controller:addPlayerProjectile(gun_x, gun_y, vx, vy, dmg, grav_mult)
                self.gun_fire_timers[item.id] = 0
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
-- 傳進來的 claw_tip 已經是**夾持點**（鉸鏈軸再往前 grip_hold_dist），見 state_mission 的計算。
-- 石頭以夾持點為中心對齊，才像被兩片爪咬住；只對齊 x、y 用左上角的話會偏下半個石頭。
function MechController:updateGrabbedStone(claw_tip_x, claw_tip_y)
    if self.claw_grabbed_stone then
        local s = self.claw_grabbed_stone
        s.x = claw_tip_x - (s.width or 0) / 2
        s.y = claw_tip_y - (s.height or 0) / 2
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
