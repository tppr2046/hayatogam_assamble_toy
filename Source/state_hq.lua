-- state_hq.lua (Version 8.4 - 恢復所有繪圖與操作邏輯)

import "CoreLibs/graphics" 

local gfx = playdate.graphics  
local default_font = gfx.font.systemFont
-- MissionData 現在從 _G.MissionData 獲取（在 main.lua 中載入）

-- 確保字形載入成功
local custom_font_path = 'fonts/Charlie Ninja' 
local font = gfx.font.new(custom_font_path) 

if not font then
    font = default_font
    print("WARNING: Failed to load " .. custom_font_path .. ". Using system font.")
end

StateHQ = {}

-- ==========================================
-- 網格組裝常數與狀態
-- ==========================================
local SCREEN_WIDTH = 400
local SCREEN_HEIGHT = 240
local UI_HEIGHT = 64  -- 操作介面高度
local GAME_HEIGHT = SCREEN_HEIGHT - UI_HEIGHT  -- 實際遊戲畫面高度
local GRID_COLS = 3       
local GRID_ROWS = 2       
local GRID_CELL_SIZE = 16 
local GRID_WIDTH = GRID_COLS * GRID_CELL_SIZE
local GRID_START_X = (SCREEN_WIDTH - GRID_WIDTH) / 2  -- 置中
local GRID_START_Y = 100  -- 往下移動，為預覽留出空間

-- UI 控制介面相關
local UI_GRID_COLS = 3
local UI_GRID_ROWS = 2
local UI_CELL_SIZE = 20
local UI_START_X = 10
local UI_START_Y = GAME_HEIGHT + 5   

local GRID_MAP = {}       
local cursor_col = 1      
local cursor_row = 1      
local cursor_on_ready = false  -- 游標是否在 READY 選項上local cursor_on_back = false   -- 遊標是否在 BACK 選項上
local selected_category = nil   -- nil = 選擇分類, "TOP" or "BOTTOM" = 已選分類
local selected_part_index = 1   
local hq_mode = "EQUIP"         -- EQUIP (組裝模式), UNEQUIP (拆卸模式), READY_MENU (READY選單)
local menu_option_index = 1     
local is_placing_part = false
local show_ready_menu = false   -- 是否顯示 READY 選單 

-- 放置失敗視覺/音效反饋
local FLASH_DURATION = 12 -- 幀數
local flash_timer = 0
local flash_col = nil
local flash_row = nil

-- 底部菜單選項清單
local MENU_OPTIONS = {
    {name = "Start Mission", action = "MISSION_SELECT"}, 
    {name = "Continue Assembly", action = "CONTINUE"},
}

-- ==========================================
-- 輔助函式 (佔位符)
-- ==========================================

-- 佔位符：檢查零件放置是否合適 (避免程式在 draw 函式中崩潰)
local function checkIfFits(part_data, start_col, start_row)
    if not part_data then return false, "No part selected" end
    -- 檢查是否超出網格範圍
    local w = part_data.slot_x or 1
    local h = part_data.slot_y or 1
    if start_col < 1 or start_row < 1 or (start_col + w - 1) > GRID_COLS or (start_row + h - 1) > GRID_ROWS then
        return false, "Out of bounds"
    end

    -- 檢查 placement_row 限制（TOP/BOTTOM/BOTH）
    if part_data.placement_row then
        local pr = part_data.placement_row
        if pr == "TOP" then
            -- TOP placement: the part's topmost occupied row must align with GRID_ROWS
            if (start_row + h - 1) ~= GRID_ROWS then
                return false, "Must place on TOP row"
            end
        elseif pr == "BOTTOM" then
            -- BOTTOM placement: the part's origin must be on the bottom row (row == 1)
            if start_row ~= 1 then
                return false, "Must place on BOTTOM row"
            end
        end
    end

    -- 檢查是否與已佔用格子重疊
    for r = start_row, start_row + h - 1 do
        GRID_MAP[r] = GRID_MAP[r] or {}
        for c = start_col, start_col + w - 1 do
            if GRID_MAP[r][c] then
                return false, "Cell occupied"
            end
        end
    end

    return true, ""
end

-- 在已裝備清單中尋找覆蓋指定格子的零件，回傳索引與該項
local function findEquippedPartAt(col, row)
    local eq = _G.GameState and _G.GameState.mech_stats and _G.GameState.mech_stats.equipped_parts
    if not eq then return nil end
    for i, item in ipairs(eq) do
        local c1 = item.col
        local r1 = item.row
        local w = item.w or 1
        local h = item.h or 1
        if col >= c1 and col < c1 + w and row >= r1 and row < r1 + h then
            return i, item
        end
    end
    return nil
end

-- 尋找第一個空的格子（適合放置零件）
local function findFirstEmptyCell(part_data)
    local w = (part_data and part_data.slot_x) or 1
    local h = (part_data and part_data.slot_y) or 1
    
    -- 優先從左上角開始尋找
    for r = GRID_ROWS, 1, -1 do  -- 從上到下（row 2, 1）
        for c = 1, GRID_COLS do  -- 從左到右
            local can_fit, reason = checkIfFits(part_data, c, r)
            if can_fit then
                return c, r
            end
        end
    end
    -- 沒有空位，返回中間位置
    return 2, 2
end

-- 從 equipped_parts 刪除指定索引的零件，並把 GRID_MAP 與 mech_stats 更新
local function removeEquippedPart(index)
    local eq = _G.GameState and _G.GameState.mech_stats and _G.GameState.mech_stats.equipped_parts
    if not eq or not eq[index] then return false end
    local item = eq[index]
    -- 清除 GRID_MAP 的格子
    for r = item.row, item.row + (item.h or 1) - 1 do
        for c = item.col, item.col + (item.w or 1) - 1 do
            if GRID_MAP[r] then GRID_MAP[r][c] = nil end
        end
    end
    table.remove(eq, index)
    print("LOG: Removed part", item.id, "from", item.col, item.row)
    -- 重算 mech_stats 以避免累加/重複扣除造成誤差
    if _G and _G.GameState and _G.GameState.mech_stats then
        recalcMechStats()
    end
    return true
end

-- 根據 equipped_parts 重新計算 mech_stats（total_hp, total_weight）
function recalcMechStats()
    if not (_G and _G.GameState and _G.GameState.mech_stats) then return end
    local total_hp = 0
    local total_weight = 0
    local eq = _G.GameState.mech_stats.equipped_parts or {}
    for _, item in ipairs(eq) do
        local pdata = _G.PartsData and _G.PartsData[item.id]
        if pdata then
            total_hp = total_hp + (pdata.hp or 0)
            total_weight = total_weight + (pdata.weight or 0)
        end
    end
    -- 確保即便沒有裝備也有基礎值（例如 0 或先前設定的 base）
    _G.GameState.mech_stats.total_hp = total_hp
    _G.GameState.mech_stats.total_weight = total_weight
end

-- 繪製網狀 Dither 覆蓋 (簡單方格樣式)
local function drawDither(x, y, w, h)
    local step = 6
    local fillSize = math.max(1, step - 2)
    for yy = y, y + h - 1, step do
        for xx = x, x + w - 1, step do
            local r = math.floor((xx / step) + (yy / step))
            if (r % 2) == 0 then
                gfx.fillRect(xx, yy, fillSize, fillSize)
            end
        end
    end
end

-- ==========================================
-- 狀態機接口
-- ==========================================

function StateHQ.setup()
    gfx.setFont(font) 
    
    -- 確保 MissionData 已在 main.lua 中載入
    if not _G.MissionData then
        print("ERROR HQ: _G.MissionData not found! Loading fallback...")
        local md = import "mission_data"
        _G.MissionData = md or {}
    end
    
    -- 確保必要的全域變數存在
    _G.GameState = _G.GameState or {}
    _G.GameState.owned_parts = _G.GameState.owned_parts or {}
    
    -- 組織零件為分類（TOP 和 BOTTOM），只顯示已擁有的零件
    local top_parts = {}
    local bottom_parts = {}
    if _G.PartsData and next(_G.PartsData) then
        for pid, pdata in pairs(_G.PartsData) do
            -- 只添加已擁有且未裝備的零件
            if _G.GameState.owned_parts[pid] then
                -- 檢查是否已裝備
                local is_equipped = false
                for _, item in ipairs(_G.GameState.mech_stats.equipped_parts or {}) do
                    if item.id == pid then
                        is_equipped = true
                        break
                    end
                end
                
                -- 只有未裝備的零件才添加到列表
                if not is_equipped then
                    if pdata.placement_row == "TOP" or pdata.placement_row == "BOTH" then
                        table.insert(top_parts, pid)
                    end
                    if pdata.placement_row == "BOTTOM" or pdata.placement_row == "BOTH" then
                        table.insert(bottom_parts, pid)
                    end
                end
            end
        end
    end
    _G.GameState.parts_by_category = {
        TOP = top_parts,
        BOTTOM = bottom_parts
    }
    print("LOG: Available parts - TOP:", #top_parts, "BOTTOM:", #bottom_parts)

    _G.GameState.mech_stats = _G.GameState.mech_stats or { total_hp = 100, total_weight = 0, equipped_parts = {} }
    _G.GameState.mech_stats.equipped_parts = _G.GameState.mech_stats.equipped_parts or {}
    
    hq_mode = "EQUIP" -- 確保從組裝模式開始
    selected_category = nil  -- 重置分類選擇
    cursor_on_ready = false
    cursor_on_back = false
    show_ready_menu = false

    -- 初始化 GRID_MAP（row-major），nil 表示空
    GRID_MAP = {}
    for r = 1, GRID_ROWS do
        GRID_MAP[r] = {}
        for c = 1, GRID_COLS do
            GRID_MAP[r][c] = nil
        end
    end

    -- 保存網格設定到全域，供任務關卡使用（用於合成機體影像）
    _G.GameState.mech_grid = { cell_size = GRID_CELL_SIZE, cols = GRID_COLS, rows = GRID_ROWS }

    -- Preload part images into parts data (store as _img)
    if _G and _G.PartsData then
        for pid, pdata in pairs(_G.PartsData) do
            if pdata.image then
                local img, err = gfx.image.new(pdata.image)
                if img then
                    pdata._img = img
                else
                    print("WARN: failed to load image for part", pid, pdata.image, err)
                end
            end
            -- 載入 CLAW 的額外圖片
            if pid == "CLAW" then
                print("DEBUG: Loading CLAW extra images")
                if pdata.arm_image then
                    local arm_img = gfx.image.new(pdata.arm_image)
                    if arm_img then
                        pdata._arm_img = arm_img
                        print("DEBUG: Loaded arm_image:", pdata.arm_image)
                    else
                        print("ERROR: Failed to load arm_image:", pdata.arm_image)
                    end
                end
                if pdata.upper_image then
                    local upper_img = gfx.image.new(pdata.upper_image)
                    if upper_img then
                        pdata._upper_img = upper_img
                        print("DEBUG: Loaded upper_image:", pdata.upper_image)
                    else
                        print("ERROR: Failed to load upper_image:", pdata.upper_image)
                    end
                end
                if pdata.lower_image then
                    local lower_img = gfx.image.new(pdata.lower_image)
                    if lower_img then
                        pdata._lower_img = lower_img
                        print("DEBUG: Loaded lower_image:", pdata.lower_image)
                    else
                        print("ERROR: Failed to load lower_image:", pdata.lower_image)
                    end
                end
            end
        end
    end
    -- Pre-render scaled images that match grid cell sizes so a part that is w x h
    -- cells can be drawn once spanning those cells. This creates pdata._img_scaled.
    if _G and _G.PartsData then
        for pid, pdata in pairs(_G.PartsData) do
            if pdata._img then
                local gotSize, iw, ih = pcall(function() return pdata._img:getSize() end)
                -- ensure buffer is at least the image size so larger-than-slot images (e.g., 32x16 SWORD) are fully visible
                local sw = math.max((pdata.slot_x or 1) * GRID_CELL_SIZE, (gotSize and iw) or 0)
                local sh = math.max((pdata.slot_y or 1) * GRID_CELL_SIZE, (gotSize and ih) or 0)
                if sw > 0 and sh > 0 then
                    local ok, buf = pcall(function() return gfx.image.new(sw, sh) end)
                    if ok and buf then
                        gfx.pushContext(buf)
                        gfx.clear(gfx.kColorClear)
                        if gotSize and iw and ih then
                            local dx = math.floor((sw - iw) / 2)
                            local dy = math.floor((sh - ih) / 2)
                            pcall(function() pdata._img:draw(math.max(0, dx), math.max(0, dy)) end)
                        else
                            pcall(function() pdata._img:draw(0, 0) end)
                        end
                        gfx.popContext()
                        pdata._img_scaled = buf
                    end
                end
            end
        end
    end
end

function StateHQ.update()
    
    if hq_mode == "EQUIP" then
        if is_placing_part then
            -- 零件放置中：移動網格游標
            if playdate.buttonJustPressed(playdate.kButtonLeft) then
                cursor_col = math.max(1, cursor_col - 1)
            elseif playdate.buttonJustPressed(playdate.kButtonRight) then
                cursor_col = math.min(GRID_COLS, cursor_col + 1)
            elseif playdate.buttonJustPressed(playdate.kButtonUp) then
                cursor_row = math.min(GRID_ROWS, cursor_row + 1)
            elseif playdate.buttonJustPressed(playdate.kButtonDown) then
                cursor_row = math.max(1, cursor_row - 1)
            elseif playdate.buttonJustPressed(playdate.kButtonA) then
                -- 嘗試放置
                if selected_category then
                    local parts_list = _G.GameState.parts_by_category[selected_category]
                    local part_id = parts_list[selected_part_index]
                    local part_data = _G.PartsData and _G.PartsData[part_id]
                    local can_fit, reason = checkIfFits(part_data, cursor_col, cursor_row)
                    
                    if can_fit then
                        local w = part_data.slot_x or 1
                        local h = part_data.slot_y or 1
                        for r = cursor_row, cursor_row + h - 1 do
                            for c = cursor_col, cursor_col + w - 1 do
                                GRID_MAP[r][c] = part_id
                            end
                        end
                        table.insert(_G.GameState.mech_stats.equipped_parts, { id = part_id, col = cursor_col, row = cursor_row, w = w, h = h })
                        if part_data.hp then
                            _G.GameState.mech_stats.total_hp = (_G.GameState.mech_stats.total_hp or 0) + part_data.hp
                        end
                        if part_data.weight then
                            _G.GameState.mech_stats.total_weight = (_G.GameState.mech_stats.total_weight or 0) + part_data.weight
                        end
                        is_placing_part = false
                        
                        -- 安裝完成後，自動選取下一個未裝備的零件
                        local parts_list = _G.GameState.parts_by_category[selected_category]
                        local parts_count = parts_list and #parts_list or 0
                        local found_next = false
                        
                        -- 從當前位置的下一個開始尋找未裝備的零件
                        for i = selected_part_index + 1, parts_count do
                            local check_part_id = parts_list[i]
                            local is_equipped = false
                            local eq = _G.GameState.mech_stats.equipped_parts or {}
                            for _, item in ipairs(eq) do
                                if item.id == check_part_id then
                                    is_equipped = true
                                    break
                                end
                            end
                            if not is_equipped then
                                selected_part_index = i
                                found_next = true
                                break
                            end
                        end
                        
                        -- 如果後面沒有未裝備的零件，從頭開始找
                        if not found_next then
                            for i = 1, selected_part_index - 1 do
                                local check_part_id = parts_list[i]
                                local is_equipped = false
                                local eq = _G.GameState.mech_stats.equipped_parts or {}
                                for _, item in ipairs(eq) do
                                    if item.id == check_part_id then
                                        is_equipped = true
                                        break
                                    end
                                end
                                if not is_equipped then
                                    selected_part_index = i
                                    found_next = true
                                    break
                                end
                            end
                        end
                        
                        -- 如果所有零件都已裝備，則移動到 READY
                        if not found_next then
                            cursor_on_ready = true
                            last_part_index = selected_part_index
                        end
                    else
                        flash_timer = FLASH_DURATION
                        flash_col = cursor_col
                        flash_row = cursor_row
                    end
                end
            elseif playdate.buttonJustPressed(playdate.kButtonB) then
                is_placing_part = false
            end
        elseif cursor_on_back then
            -- 游標在 BACK 上
            print("DEBUG: cursor_on_back is true")
            if playdate.buttonJustPressed(playdate.kButtonUp) then
                print("DEBUG: BACK - Up pressed")
                cursor_on_back = false
                cursor_on_ready = true
            elseif playdate.buttonJustPressed(playdate.kButtonA) then
                -- 返回任務選擇畫面
                print("DEBUG: BACK - A pressed, returning to mission select")
                print("DEBUG: _G.StateMissionSelect = " .. tostring(_G.StateMissionSelect))
                setState(_G.StateMissionSelect)
            end
        elseif cursor_on_ready then
            -- 游標在 READY 上
            if show_ready_menu then
                -- READY 選單打開
                if playdate.buttonJustPressed(playdate.kButtonDown) then
                    menu_option_index = math.min(2, menu_option_index + 1)
                elseif playdate.buttonJustPressed(playdate.kButtonUp) then
                    menu_option_index = math.max(1, menu_option_index - 1)
                elseif playdate.buttonJustPressed(playdate.kButtonA) then
                    if menu_option_index == 1 then
                        -- Start Mission
                        -- 使用從任務選擇畫面設置的任務 ID
                        _G.GameState = _G.GameState or {}
                        -- 確保有 current_mission，否則使用預設值
                        if not _G.GameState.current_mission then
                            _G.GameState.current_mission = "M001"
                            print("WARNING: No current_mission set, using M001 as fallback")
                        end
                        print("Starting mission:", _G.GameState.current_mission)
                        setState(_G.StateMission)
                    else
                        -- Continue Assembly
                        show_ready_menu = false
                        cursor_on_ready = false
                    end
                elseif playdate.buttonJustPressed(playdate.kButtonB) then
                    show_ready_menu = false
                end
            else
                -- 選單未打開
                if playdate.buttonJustPressed(playdate.kButtonUp) then
                    cursor_on_ready = false
                    -- 回到最後選中的零件（使用儲存的 last_part_index）
                    if last_part_index then
                        selected_part_index = last_part_index
                    end
                elseif playdate.buttonJustPressed(playdate.kButtonDown) then
                    -- 從 READY 移動到 BACK
                    print("DEBUG: Moving from READY to BACK")
                    cursor_on_ready = false
                    cursor_on_back = true
                    print("DEBUG: cursor_on_back set to true")
                elseif playdate.buttonJustPressed(playdate.kButtonA) then
                    show_ready_menu = true
                    menu_option_index = 1
                end
            end
        elseif not selected_category then
            -- 選擇分類
            if playdate.buttonJustPressed(playdate.kButtonUp) then
                if cursor_on_ready then
                    cursor_on_ready = false
                    selected_part_index = 2  -- 回到最後一個分類
                else
                    selected_part_index = (selected_part_index == 1) and 2 or 1
                end
            elseif playdate.buttonJustPressed(playdate.kButtonDown) then
                if selected_part_index == 2 then
                    cursor_on_ready = true
                    last_part_index = 2  -- 記住最後位置
                else
                    selected_part_index = 2
                end
            elseif playdate.buttonJustPressed(playdate.kButtonA) then
                selected_category = (selected_part_index == 1) and "TOP" or "BOTTOM"
                selected_part_index = 1
            end
        else
            -- 已選分類，選擇零件或移動到 READY
            local parts_list = _G.GameState.parts_by_category[selected_category]
            local parts_count = #parts_list
            
            if playdate.buttonJustPressed(playdate.kButtonUp) then
                -- 向上移動，跳過已安裝的零件
                local new_index = selected_part_index - 1
                while new_index >= 1 do
                    local check_part_id = parts_list[new_index]
                    local is_equipped = false
                    local eq = _G.GameState.mech_stats.equipped_parts or {}
                    for _, item in ipairs(eq) do
                        if item.id == check_part_id then
                            is_equipped = true
                            break
                        end
                    end
                    if not is_equipped then
                        selected_part_index = new_index
                        break
                    end
                    new_index = new_index - 1
                end
            elseif playdate.buttonJustPressed(playdate.kButtonDown) then
                -- 向下移動，跳過已安裝的零件
                local new_index = selected_part_index + 1
                while new_index <= parts_count do
                    local check_part_id = parts_list[new_index]
                    local is_equipped = false
                    local eq = _G.GameState.mech_stats.equipped_parts or {}
                    for _, item in ipairs(eq) do
                        if item.id == check_part_id then
                            is_equipped = true
                            break
                        end
                    end
                    if not is_equipped then
                        selected_part_index = new_index
                        break
                    end
                    new_index = new_index + 1
                end
                -- 如果沒有找到未安裝的零件，移動到 READY
                if new_index > parts_count then
                    cursor_on_ready = true
                    last_part_index = selected_part_index
                end
            elseif playdate.buttonJustPressed(playdate.kButtonA) then
                -- 選中零件，檢查是否已安裝
                local parts_list = _G.GameState.parts_by_category[selected_category]
                local part_id = parts_list[selected_part_index]
                
                -- 檢查是否已安裝
                local is_equipped = false
                local eq = _G.GameState.mech_stats.equipped_parts or {}
                for _, item in ipairs(eq) do
                    if item.id == part_id then
                        is_equipped = true
                        break
                    end
                end
                
                -- 如果已安裝，不做任何事（無法選取）
                if is_equipped then
                    print("Part already equipped: " .. part_id)
                    return
                end
                
                local part_data = _G.PartsData and _G.PartsData[part_id]
                
                if part_data then
                    -- 找到第一個空格子
                    local empty_col, empty_row = findFirstEmptyCell(part_data)
                    cursor_col = empty_col
                    cursor_row = empty_row
                    is_placing_part = true
                end
            elseif playdate.buttonJustPressed(playdate.kButtonB) then
                selected_category = nil
                selected_part_index = 1
            end
        end
    
    elseif hq_mode == "UNEQUIP" then
        -- 拆卸模式
        if playdate.buttonJustPressed(playdate.kButtonLeft) then
            cursor_col = math.max(1, cursor_col - 1)
        elseif playdate.buttonJustPressed(playdate.kButtonRight) then
            cursor_col = math.min(GRID_COLS, cursor_col + 1)
        elseif playdate.buttonJustPressed(playdate.kButtonUp) then
            cursor_row = math.min(GRID_ROWS, cursor_row + 1)
        elseif playdate.buttonJustPressed(playdate.kButtonDown) then
            cursor_row = math.max(1, cursor_row - 1)
        elseif playdate.buttonJustPressed(playdate.kButtonA) then
            local idx, item = findEquippedPartAt(cursor_col, cursor_row)
            if idx and item then
                removeEquippedPart(idx)
            end
        elseif playdate.buttonJustPressed(playdate.kButtonB) then
            hq_mode = "EQUIP"
        end
    end
    
    -- 更新 flash 計時器
    if flash_timer and flash_timer > 0 then
        flash_timer = flash_timer - 1
        if flash_timer <= 0 then
            flash_col = nil
            flash_row = nil
            flash_timer = 0
        end
    end
end


function StateHQ.draw()
    
    gfx.clear(gfx.kColorWhite)
    gfx.setColor(gfx.kColorBlack)
    gfx.setFont(font) 
    
    -- 1. 繪製組裝網格背景
    
    -- 2. 繪製機甲網格邊框 (作為機甲本體的佔位符)
    local mech_image_x = GRID_START_X
    local mech_image_y = GRID_START_Y
    local mech_width = GRID_CELL_SIZE * GRID_COLS
    local mech_height = GRID_CELL_SIZE * GRID_ROWS
    
    gfx.drawRect(mech_image_x, mech_image_y, mech_width, mech_height)
--    gfx.drawText("MECH ASSEMBLY GRID", mech_image_x + 5, mech_image_y + 5)
    
    -- Grid and parts rendering handled below (draw grid lines, then draw each equipped part once)
    
    -- 3. 繪製零件預覽 (選中零件後，即使沒進入放置模式也顯示預覽)
    if hq_mode == "EQUIP" and selected_category and selected_part_index and not cursor_on_ready then
        local parts_list = _G.GameState.parts_by_category[selected_category]
        local part_id = parts_list and parts_list[selected_part_index]
        local pdata = (_G.PartsData and _G.PartsData[part_id]) or nil
        
        if pdata then
            local preview_x, preview_y
            
            if is_placing_part then
                -- 放置模式：預覽在游標位置
                preview_x = GRID_START_X + (cursor_col - 1) * GRID_CELL_SIZE
                preview_y = GRID_START_Y + (GRID_ROWS - cursor_row) * GRID_CELL_SIZE
            else
                -- 非放置模式：預覽顯示在組裝格上方（置中）
                local sw = (pdata.slot_x or 1) * GRID_CELL_SIZE
                local sh = (pdata.slot_y or 1) * GRID_CELL_SIZE
                local grid_width = GRID_COLS * GRID_CELL_SIZE
                preview_x = GRID_START_X + (grid_width - sw) / 2
                preview_y = GRID_START_Y - sh - 40  -- 組裝格上方，留40像素間距
            end
            
            -- 繪製預覽圖片
            if pdata._img_scaled then
                local sw = (pdata.slot_x or 1) * GRID_CELL_SIZE
                local sh = (pdata.slot_y or 1) * GRID_CELL_SIZE
                local draw_y = preview_y + (GRID_CELL_SIZE - sh)
                pcall(function() pdata._img_scaled:draw(preview_x, draw_y) end)
                -- CLAW 特殊處理：繪製額外部件
                if part_id == "CLAW" then
                    if pdata._arm_img then pcall(function() pdata._arm_img:draw(preview_x, draw_y) end) end
                    if pdata._upper_img then pcall(function() pdata._upper_img:draw(preview_x, draw_y) end) end
                    if pdata._lower_img then pcall(function() pdata._lower_img:draw(preview_x, draw_y) end) end
                end
                gfx.setColor(gfx.kColorBlack)
                drawDither(preview_x + 2, draw_y + 2, sw - 4, sh - 4)
                gfx.setColor(gfx.kColorBlack)
                gfx.drawRect(preview_x, draw_y, sw, sh)
            elseif pdata._img then
                local iw, ih
                local ok, a, b = pcall(function() return pdata._img:getSize() end)
                if ok then iw, ih = a, b end
                local draw_x = preview_x
                local draw_y = preview_y
                if iw and ih then
                    draw_x = preview_x + math.floor((GRID_CELL_SIZE - iw) / 2)
                    draw_y = preview_y + math.floor((GRID_CELL_SIZE - ih) / 2)
                end
                pcall(function() pdata._img:draw(draw_x, draw_y) end)
                -- CLAW 特殊處理：繪製額外部件
                if part_id == "CLAW" then
                    if pdata._arm_img then pcall(function() pdata._arm_img:draw(draw_x, draw_y) end) end
                    if pdata._upper_img then pcall(function() pdata._upper_img:draw(draw_x, draw_y) end) end
                    if pdata._lower_img then pcall(function() pdata._lower_img:draw(draw_x, draw_y) end) end
                end
                gfx.setColor(gfx.kColorBlack)
                drawDither(preview_x + 2, preview_y + 2, GRID_CELL_SIZE - 4, GRID_CELL_SIZE - 4)
                gfx.setColor(gfx.kColorBlack)
                gfx.drawRect(preview_x, preview_y, GRID_CELL_SIZE, GRID_CELL_SIZE)
            end
        end
    end

    -- 如果在 UNEQUIP 模式，繪製游標框並顯示要移除的零件資訊（若有）
    if hq_mode == "UNEQUIP" then
        local cursor_x = GRID_START_X + (cursor_col - 1) * GRID_CELL_SIZE
        -- convert row (bottom-origin) to top-based y for drawing
        local cursor_y = GRID_START_Y + (GRID_ROWS - cursor_row) * GRID_CELL_SIZE
        -- 用黑色框標示選取格
        gfx.setColor(gfx.kColorBlack)
        gfx.drawRect(cursor_x, cursor_y, GRID_CELL_SIZE, GRID_CELL_SIZE)

        local idx, item = findEquippedPartAt(cursor_col, cursor_row)
        if item then
            local label = item.id or "PART"
            gfx.drawText("Remove: " .. label, cursor_x, cursor_y + GRID_CELL_SIZE + 2)
        else
            gfx.drawText("No part", cursor_x, cursor_y + GRID_CELL_SIZE + 2)
        end
    end
    
    -- 繪製閃爍（放置失敗）覆蓋層
    if flash_timer and flash_timer > 0 and flash_col and flash_row then
        local fx = GRID_START_X + (flash_col - 1) * GRID_CELL_SIZE
        local fy = GRID_START_Y + (flash_row - 1) * GRID_CELL_SIZE
        -- 閃爍效果：交替黑白填充
        if (flash_timer % 4) < 2 then
            gfx.setColor(gfx.kColorBlack)
            gfx.fillRect(fx, fy, GRID_CELL_SIZE, GRID_CELL_SIZE)
            gfx.setColor(gfx.kColorWhite)
        else
            gfx.setColor(gfx.kColorWhite)
            gfx.fillRect(fx, fy, GRID_CELL_SIZE, GRID_CELL_SIZE)
            gfx.setColor(gfx.kColorBlack)
        end
        gfx.drawText("X", fx + math.floor(GRID_CELL_SIZE/2) - 3, fy + math.floor(GRID_CELL_SIZE/2) - 6)
    end
    
    -- 4. 繪製零件清單 (左側) - 分類顯示
    gfx.drawText("PARTS:", 10, 30)
    local list_y = 50
    local line_height = 15
    
    if not selected_category then
        -- 顯示分類選擇
        local categories = {"TOP PARTS", "BOTTOM PARTS"}
        for i = 1, 2 do
            local text = categories[i]
            if i == selected_part_index then
                text = "> " .. text .. " <"
            end
            gfx.drawText(text, 10, list_y + (i - 1) * line_height)
        end
    else
        -- 顯示選中分類的零件
        gfx.drawText(selected_category .. " PARTS:", 10, list_y - 15)
        local parts_list = _G.GameState.parts_by_category[selected_category]
        for i, part_id in ipairs(parts_list) do
            -- 檢查是否已安裝
            local is_equipped = false
            local eq = _G.GameState.mech_stats.equipped_parts or {}
            for _, item in ipairs(eq) do
                if item.id == part_id then
                    is_equipped = true
                    break
                end
            end
            
            local text = part_id
            if i == selected_part_index and not cursor_on_ready then
                text = "> " .. text .. " <"
            end
            
            local text_x = 10
            local text_y = list_y + (i - 1) * line_height
            gfx.drawText(text, text_x, text_y)
            
            -- 如果已安裝，繪製刪除線
            if is_equipped then
                local text_width = gfx.getTextSize(text)
                gfx.setColor(gfx.kColorBlack)
                gfx.drawLine(text_x, text_y + 7, text_x + text_width, text_y + 7)
            end
        end
    end
    
    -- 5. 繪製零件詳細資訊 / 狀態 (右側)
    local detail_x = 250
    local detail_y = 30
    
    -- 繪製格子格線（上下兩排都顯示）
    for r = 1, GRID_ROWS do
        for c = 1, GRID_COLS do
            local cell_x = GRID_START_X + (c - 1) * GRID_CELL_SIZE
            local cell_y = GRID_START_Y + (r - 1) * GRID_CELL_SIZE
            gfx.setColor(gfx.kColorBlack)
            gfx.drawRect(cell_x, cell_y, GRID_CELL_SIZE, GRID_CELL_SIZE)
        end
    end
    
    -- 繪製已放置的零件，每個零件只繪製一次，佔據 w x h 格
    -- 分兩階段繪製：先下排(row=1)再上排(row=2)
                local eq = _G.GameState and _G.GameState.mech_stats and _G.GameState.mech_stats.equipped_parts or {}
                
                -- 第一階段：繪製下排零件（row=1，無格線和 Dither）
                for _, item in ipairs(eq) do
                    if item.row == 1 then
                        local pid = item.id
                        local pdata = (_G.PartsData and _G.PartsData[pid]) or nil
                        local px = GRID_START_X + (item.col - 1) * GRID_CELL_SIZE
                        -- convert item.row (bottom-left origin) to top-based y
                        local py_top = GRID_START_Y + (GRID_ROWS - item.row) * GRID_CELL_SIZE
                        local pw = (item.w or 1) * GRID_CELL_SIZE
                        local ph = (item.h or 1) * GRID_CELL_SIZE
                        if pdata and pdata._img_scaled then
                            -- draw pre-rendered image; anchor bottom-left so full image visible
                            local ok, iw, ih = pcall(function() return pdata._img_scaled:getSize() end)
                            if ok and iw and ih then
                                local draw_x = px
                                local draw_y
                                if pdata.align_image_top then
                                    -- 圖片上緣對齊格子上緣（用於 FEET）
                                    draw_y = py_top
                                else
                                    -- 預設：圖片底部對齊格子底部
                                    draw_y = py_top + (GRID_CELL_SIZE - ih)
                                end
                                pcall(function() pdata._img_scaled:draw(draw_x, draw_y) end)
                            else
                                pcall(function() pdata._img_scaled:draw(px, py_top) end)
                            end
                            
                            -- 繪製 CLAW 的額外部件
                            if pid == "CLAW" then
                                if pdata._arm_img then
                                    pcall(function() pdata._arm_img:draw(px, py_top) end)
                                end
                                if pdata._upper_img then
                                    pcall(function() pdata._upper_img:draw(px, py_top) end)
                                end
                                if pdata._lower_img then
                                    pcall(function() pdata._lower_img:draw(px, py_top) end)
                                end
                            end
                        elseif pdata and pdata._img then
                            -- fallback: draw original with bottom-left anchoring (no scaling)
                            local iw, ih
                            local ok, a, b = pcall(function() return pdata._img:getSize() end)
                            if ok then iw, ih = a, b end
                            local draw_x = px
                            local draw_y
                            if pdata.align_image_top then
                                -- 圖片上緣對齊格子上緣（用於 FEET 等超出格子的零件）
                                draw_y = py_top
                            else
                                -- 預設：圖片底部對齊格子底部
                                draw_y = py_top + (GRID_CELL_SIZE - (ih or GRID_CELL_SIZE))
                            end
                            pcall(function() pdata._img:draw(draw_x, draw_y) end)
                            
                            -- 繪製 CLAW 的額外部件
                            if pid == "CLAW" then
                                if pdata._arm_img then
                                    pcall(function() pdata._arm_img:draw(draw_x, draw_y) end)
                                end
                                if pdata._upper_img then
                                    pcall(function() pdata._upper_img:draw(draw_x, draw_y) end)
                                end
                                if pdata._lower_img then
                                    pcall(function() pdata._lower_img:draw(draw_x, draw_y) end)
                                end
                            end
                        else
                            -- no image: draw text label at the origin cell
                            gfx.setColor(gfx.kColorBlack)
                            gfx.drawText(pid or "?", px + 2, py_top + 2)
                        end
                    end
                end
                
                -- 第二階段：繪製上排零件（row=2，有格線和 Dither）
                for _, item in ipairs(eq) do
                    if item.row == 2 then
                        local pid = item.id
                        local pdata = (_G.PartsData and _G.PartsData[pid]) or nil
                        local px = GRID_START_X + (item.col - 1) * GRID_CELL_SIZE
                        -- convert item.row (bottom-left origin) to top-based y
                        local py_top = GRID_START_Y + (GRID_ROWS - item.row) * GRID_CELL_SIZE
                        local pw = (item.w or 1) * GRID_CELL_SIZE
                        local ph = (item.h or 1) * GRID_CELL_SIZE
                        if pdata and pdata._img_scaled then
                            -- draw pre-rendered image; anchor bottom-left so full image visible
                            local ok, iw, ih = pcall(function() return pdata._img_scaled:getSize() end)
                            if ok and iw and ih then
                                local draw_x = px
                                local draw_y
                                if pdata.align_image_top then
                                    -- 圖片上緣對齊格子上緣（用於 FEET）
                                    draw_y = py_top
                                else
                                    -- 預設：圖片底部對齊格子底部
                                    draw_y = py_top + (GRID_CELL_SIZE - ih)
                                end
                                pcall(function() pdata._img_scaled:draw(draw_x, draw_y) end)
                            else
                                pcall(function() pdata._img_scaled:draw(px, py_top) end)
                            end
                            
                            -- 繪製 CLAW 的額外部件
                            if pid == "CLAW" then
                                if pdata._arm_img then
                                    pcall(function() pdata._arm_img:draw(px, py_top) end)
                                end
                                if pdata._upper_img then
                                    pcall(function() pdata._upper_img:draw(px, py_top) end)
                                end
                                if pdata._lower_img then
                                    pcall(function() pdata._lower_img:draw(px, py_top) end)
                                end
                            end
                            
                            gfx.setColor(gfx.kColorBlack)
                            drawDither(px + 2, py_top + 2, pw - 4, ph - 4)
                            gfx.setColor(gfx.kColorBlack)
                            gfx.drawRect(px, py_top, pw, ph)
                        elseif pdata and pdata._img then
                            -- fallback: draw original with bottom-left anchoring (no scaling)
                            local iw, ih
                            local ok, a, b = pcall(function() return pdata._img:getSize() end)
                            if ok then iw, ih = a, b end
                            local draw_x = px
                            local draw_y
                            if pdata.align_image_top then
                                -- 圖片上緣對齊格子上緣（用於 FEET 等超出格子的零件）
                                draw_y = py_top
                            else
                                -- 預設：圖片底部對齊格子底部
                                draw_y = py_top + (GRID_CELL_SIZE - (ih or GRID_CELL_SIZE))
                            end
                            pcall(function() pdata._img:draw(draw_x, draw_y) end)
                            -- CLAW 特殊處理：繪製額外部件
                            if pid == "CLAW" then
                                print("DEBUG: Drawing CLAW extras at", draw_x, draw_y)
                                print("DEBUG: _arm_img=", pdata._arm_img, "_upper_img=", pdata._upper_img, "_lower_img=", pdata._lower_img)
                                if pdata._arm_img then pcall(function() pdata._arm_img:draw(draw_x, draw_y) end) end
                                if pdata._upper_img then pcall(function() pdata._upper_img:draw(draw_x, draw_y) end) end
                                if pdata._lower_img then pcall(function() pdata._lower_img:draw(draw_x, draw_y) end) end
                            end
                            gfx.setColor(gfx.kColorBlack)
                            drawDither(px + 2, py_top + 2, pw - 4, ph - 4)
                        else
                            -- no image: draw text label at the origin cell
                            gfx.setColor(gfx.kColorBlack)
                            gfx.drawText(pid or "?", px + 2, py_top + 2)
                        end
                    end
                end
    
    -- 6. 繪製機甲狀態
    gfx.drawText("MECH STATS:", detail_x, detail_y)
    local stats = _G.GameState and _G.GameState.mech_stats or { total_hp = 0, total_weight = 0 }
    gfx.drawText("HP: " .. stats.total_hp, detail_x, detail_y + 20)
    gfx.drawText("Weight: " .. stats.total_weight, detail_x, detail_y + 40)
    
    -- 7. 繪製 READY 選項（置中在組裝格下方）
    local ready_y = GRID_START_Y + GRID_ROWS * GRID_CELL_SIZE + 10
    local ready_text = "READY"
    if cursor_on_ready then
        ready_text = "> " .. ready_text .. " <"
    end
    local ready_text_width = gfx.getTextSize(ready_text)
    local ready_x = GRID_START_X + (GRID_COLS * GRID_CELL_SIZE - ready_text_width) / 2
    gfx.drawText(ready_text, ready_x, ready_y)
    
    -- 繪製 BACK 選項（在 READY 下方）
    local back_y = ready_y + 15
    local back_text = "BACK"
    if cursor_on_back then
        back_text = "> " .. back_text .. " <"
    end
    local back_text_width = gfx.getTextSize(back_text)
    local back_x = GRID_START_X + (GRID_COLS * GRID_CELL_SIZE - back_text_width) / 2
    gfx.drawText(back_text, back_x, back_y)
    
    -- 如果顯示 READY 選單
    if show_ready_menu then
        local menu_y = ready_y + 15
        local options = {"Start Mission", "Back to equip"}
        for i = 1, 2 do
            local text = options[i]
            if i == menu_option_index then
                text = "> " .. text
            else
                text = "  " .. text
            end
            local text_width = gfx.getTextSize(text)
            local menu_x = GRID_START_X + (GRID_COLS * GRID_CELL_SIZE - text_width) / 2
            gfx.drawText(text, menu_x, menu_y + (i - 1) * 12)
        end
    end
    
    -- 8. 繪製控制介面 UI（下半部）
    -- 繪製 3x2 控制格子
    local eq = _G.GameState and _G.GameState.mech_stats and _G.GameState.mech_stats.equipped_parts or {}
    
    -- 找出選中格子對應的零件ID（用於高亮所有佔用格子）
    local selected_part_id_for_highlight = nil
    if selected_category and selected_part_index and not cursor_on_ready then
        local parts_list = _G.GameState.parts_by_category[selected_category]
        local part_id = parts_list and parts_list[selected_part_index]
        selected_part_id_for_highlight = part_id
    end
    
    for r = 1, UI_GRID_ROWS do
        for c = 1, UI_GRID_COLS do
            local cx = UI_START_X + (c - 1) * (UI_CELL_SIZE + 5)
            local cy = UI_START_Y + (UI_GRID_ROWS - r) * (UI_CELL_SIZE + 5)
            
            -- 檢查此格是否有零件以及屬於哪個零件
            local part_id = nil
            local is_in_selected_part = false
            for _, item in ipairs(eq) do
                local slot_w = item.w or 1
                local slot_h = item.h or 1
                if c >= item.col and c < item.col + slot_w and
                   r >= item.row and r < item.row + slot_h then
                    part_id = item.id
                    -- 檢查是否屬於選中的零件
                    if selected_part_id_for_highlight and item.id == selected_part_id_for_highlight then
                        is_in_selected_part = true
                    end
                    break
                end
            end
            
            -- 繪製格子（高亮選中零件的所有格子）
            if is_in_selected_part then
                gfx.setColor(gfx.kColorBlack)
                gfx.fillRect(cx, cy, UI_CELL_SIZE, UI_CELL_SIZE)
                gfx.setColor(gfx.kColorWhite)
            else
                gfx.setColor(gfx.kColorBlack)
            end
            gfx.drawRect(cx, cy, UI_CELL_SIZE, UI_CELL_SIZE)
            
            -- 顯示零件名稱縮寫（只在零件的起始格顯示）
            if part_id then
                for _, item in ipairs(eq) do
                    if item.id == part_id and item.col == c and item.row == r then
                        local label = string.sub(part_id, 1, 1)
                        gfx.setColor(gfx.kColorBlack)
                        gfx.drawText(label, cx + 6, cy + 6)
                        break
                    end
                end
            end
        end
    end
    
    -- 顯示當前選中的零件資訊
    local info_x = UI_START_X + UI_GRID_COLS * (UI_CELL_SIZE + 5) + 10
    if selected_category and selected_part_index and not cursor_on_ready then
        local parts_list = _G.GameState.parts_by_category[selected_category]
        local part_id = parts_list and parts_list[selected_part_index]
        if part_id then
            gfx.setColor(gfx.kColorBlack)
            gfx.drawText("Selected: " .. part_id, info_x, UI_START_Y)
        end
    else
        gfx.setColor(gfx.kColorBlack)
        gfx.drawText("Select category", info_x, UI_START_Y)
    end
    
    -- 9. 顯示關卡簡介（下半部右側）
    local mission_id = (_G and _G.GameState and _G.GameState.current_mission) or "M001"
    if MissionData and MissionData[mission_id] then
        local mission = MissionData[mission_id]
        local brief_x = info_x
        local brief_y = UI_START_Y + 25
        
        gfx.setColor(gfx.kColorBlack)
        gfx.drawText("MISSION:", brief_x, brief_y)
        gfx.drawText(mission.name or "Unknown", brief_x, brief_y + 12)
        
        if mission.objective then
            gfx.drawText("Objective:", brief_x, brief_y + 30)
            gfx.drawText(mission.objective.description or "", brief_x, brief_y + 42)
        end
    end
end

return StateHQ