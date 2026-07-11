-- entity_mech_render.lua — MechController 繪製段（場景機體繪製＋底部操作面板 UI）
-- [[ P1 拆檔 ]] 自 entity_mech.lua 再拆出：邏輯（輸入/操作/切換）留在
-- entity_mech.lua，繪製集中於此。兩檔都往同一個全域 MechController 表掛方法。
-- G2 UI 排版修正與 CLAW 面板調整主要改這檔。

import "CoreLibs/graphics"

local gfx = playdate.graphics



-- [[ ========================================== ]]
-- [[  MechRenderer (機甲繪製) ]]
-- [[ ========================================== ]]

-- [[ P2s SPIKE 開關 ]] 斜坡上是否用「離屏 image 整體傾斜」畫機體。
-- true = 新方案（整台當剛體繞底部中心旋轉）；false = 原本逐零件旋轉的畫法。
-- 方便 A/B 對照;spike 驗證通過後再併入正式 P2。
MechController.SLOPE_OFFSCREEN_TILT = true

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

    -- [[ P2s SPIKE ]] 斜坡上改走「離屏 image 整體傾斜」路徑，讓整台機體像剛體一起轉
    if MechController.SLOPE_OFFSCREEN_TILT and terrain_angle ~= 0 then
        self:drawMechTilted(draw_x, body_draw_y, mech_grid, eq, feet_extra_height, terrain_angle, feet_imagetable, feet_current_frame)
        self:drawFocusPartOutline(mech_x, mech_y, draw_x, mech_grid, entity_controller)
        return
    end

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

    self:drawFocusPartOutline(mech_x, mech_y, draw_x, mech_grid, entity_controller)
end

-- [[ A3/G1 ]] 機體上的焦點回饋：切到某零件的瞬間，該零件外框以
-- 「與面板高亮框相同的效果」顯示——白 5px＋黑 3px 雙層框、放大彈回
-- （expand 隨 focus_flash_timer 8→0 收攏），8 幀後消失。
-- 外框四角套用機體傾斜（斜坡上跟著零件）。
function MechController:drawFocusPartOutline(mech_x, mech_y, draw_x, mech_grid, entity_controller)
    local timer = self.focus_flash_timer or 0
    if timer <= 0 or not self.active_part_id then return end

    local gfx = playdate.graphics
    local eq = (_G.GameState and _G.GameState.mech_stats and _G.GameState.mech_stats.equipped_parts) or {}
    for _, item in ipairs(eq) do
        if item.id == self.active_part_id then
            local cell = (mech_grid and mech_grid.cell_size) or 16
            local slot_w = item.w or 1
            -- 與面板高亮框相同的放大彈回
            local expand = math.floor(timer / 2)
            -- 零件格範圍四角（世界座標，含 expand）
            local x1 = mech_x + (item.col - 1) * cell - expand
            local y1 = mech_y + (((mech_grid and mech_grid.rows) or 2) - item.row) * cell - expand
            local x2 = x1 + slot_w * cell + expand * 2
            local y2 = y1 + cell + expand * 2
            local corners = { {x1, y1}, {x2, y1}, {x2, y2}, {x1, y2} }
            -- 套用機體傾斜 → 螢幕座標
            local sx = {}
            local sy = {}
            for i, c in ipairs(corners) do
                local wx, wy = self:applyMechTilt(c[1], c[2], nil, nil, mech_x, mech_y, mech_grid, entity_controller)
                sx[i] = wx + (draw_x - mech_x)
                sy[i] = wy
            end
            -- 與面板高亮框相同：白 5px 外框打底、黑 3px 內框在上
            gfx.setColor(gfx.kColorWhite)
            gfx.setLineWidth(5)
            for i = 1, 4 do
                local j = (i % 4) + 1
                gfx.drawLine(sx[i], sy[i], sx[j], sy[j])
            end
            gfx.setColor(gfx.kColorBlack)
            gfx.setLineWidth(3)
            for i = 1, 4 do
                local j = (i % 4) + 1
                gfx.drawLine(sx[i], sy[i], sx[j], sy[j])
            end
            gfx.setLineWidth(1)
            break
        end
    end
end

-- [[ P2s SPIKE ]] 離屏 image 整體傾斜：把整台機體先畫到一張離屏圖，
-- 再繞「機體底部中心」旋轉 terrain_angle 一次畫到畫面。
-- 效果：機體是一個整體，斜坡上底座/砲塔/所有零件一起傾斜；
-- crank 瞄準角照常畫進離屏圖，再由整張圖的旋轉自然疊加地形角。
function MechController:drawMechTilted(draw_x, body_draw_y, mech_grid, eq, feet_extra_height, terrain_angle, feet_imagetable, feet_current_frame)
    local gfx = playdate.graphics
    local cell = (mech_grid and mech_grid.cell_size) or 16
    local mech_width = cell * 3
    local mech_height = cell * 2 + (feet_extra_height or 0)

    -- 加 padding，避免砲管/爪臂等超出格子的部分被離屏圖邊緣裁掉
    -- 最長伸距：爪臂 48px + 爪 16px = 64px（canon 砲管 64px 同級），再加 cell 餘裕
    local pad = cell + 64
    local img_w = mech_width + pad * 2
    local img_h = mech_height + pad * 2

    local mech_img = gfx.image.new(img_w, img_h)  -- 預設透明底
    if not mech_img then return end

    -- 在離屏圖上以本地座標（位移 pad）畫出整台機體；rotation_angle 一律傳 0（不逐零件轉）
    gfx.pushContext(mech_img)
        local lx, ly = pad, pad

        -- 下排（row = 1）
        for _, item in ipairs(eq) do
            local pdata = _G.PartsData and _G.PartsData[item.id]
            local pt = pdata and pdata.part_type
            local special = (pt == "SWORD" or pt == "CANON" or pt == "FEET" or pt == "CLAW")
            if not (special and item.id == self.active_part_id) and item.row == 1 then
                self:drawPart(item, lx, ly, mech_grid, feet_imagetable, feet_current_frame, 0)
            end
        end

        -- 上排（row = 2）
        for _, item in ipairs(eq) do
            local pdata = _G.PartsData and _G.PartsData[item.id]
            local pt = pdata and pdata.part_type
            local special = (pt == "SWORD" or pt == "CANON" or pt == "FEET" or pt == "CLAW")
            if not (special and item.id == self.active_part_id) and item.row == 2 then
                self:drawPart(item, lx, ly, mech_grid, feet_imagetable, feet_current_frame, 0)
            end
        end

        -- 作用中零件（crank 角照常，terrain 交給整張圖旋轉，故傳 0）
        if self.active_part_id then
            for _, item in ipairs(eq) do
                if item.id == self.active_part_id then
                    self:drawActivePart(item, lx, ly, mech_grid, feet_imagetable, feet_current_frame, 0)
                    break
                end
            end
        end
    gfx.popContext()

    -- 繞「機體底部中心」把整張圖旋轉 terrain_angle 畫到畫面
    -- drawRotated 以影像中心為軸；影像中心相對底部中心位移 (0, -mech_height/2)，隨影像一起轉
    local pivot_x = draw_x + mech_width / 2
    local pivot_y = body_draw_y + mech_height
    local rad = math.rad(terrain_angle)
    local cos_a, sin_a = math.cos(rad), math.sin(rad)
    local off_x, off_y = 0, -mech_height / 2
    local center_x = pivot_x + (off_x * cos_a - off_y * sin_a)
    local center_y = pivot_y + (off_x * sin_a + off_y * cos_a)
    mech_img:drawRotated(center_x, center_y, terrain_angle)
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
                -- [[ A3 ]] 切換瞬間高亮框放大彈回（focus_flash_timer 8→0）
                local expand = math.floor((self.focus_flash_timer or 0) / 2)
                local fx = ui_start_x + (item.col - 1) * ui_cell_size - expand
                -- 根據零件的 row 決定 y 座標：row=2 在上方，row=1 在下方
                local fy = ui_start_y + (ui_grid_rows - item.row) * ui_cell_size - expand
                local fw = slot_w * ui_cell_size + expand * 2
                local fh = ui_cell_size + expand * 2

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
    end
    -- [[ A3 ]] 舊「Select part (A)」提示已移除：直接切換制下焦點永遠存在
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
            
            -- 繪製 claw_control_v（左邊控制器）
            -- [[ A3 ]] 舊制此圖回應上下鍵（當時上下鍵控臂）；新制上下鍵=切換焦點、
            -- crank 控臂，故固定顯示預設 frame，避免誤導
            local control_v_table = ui.claw_control_v
            if control_v_table then
                local control_img = control_v_table:getImage(1)
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

