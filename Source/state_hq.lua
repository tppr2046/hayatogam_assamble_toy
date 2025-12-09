-- state_hq.lua (Version 8.4 - 恢復所有繪圖與操作邏輯)

import "CoreLibs/graphics"
import "module_ui" 

local gfx = playdate.graphics  
local default_font = gfx.font.systemFont

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
local UI_AREA_Y_START = 160 
local GRID_COLS = 3       
local GRID_ROWS = 2       
local GRID_CELL_SIZE = 50 
local GRID_START_X = 100  
local GRID_START_Y = 40   

local GRID_MAP = {}       
local cursor_col = 1      
local cursor_row = 1      

local selected_part_index = 1   
local equipped_part_index = 1   
local hq_mode = "EQUIP"         -- EQUIP (組裝模式), UNEQUIP (拆卸模式), MENU (底部選單)
local menu_option_index = 1     
local is_placing_part = false 

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

    -- 更新 mech_stats
    local pdata = _G.PartsData and _G.PartsData[item.id]
    if pdata then
        if pdata.hp then
            _G.GameState.mech_stats.total_hp = (_G.GameState.mech_stats.total_hp or 0) - pdata.hp
        end
        if pdata.weight then
            _G.GameState.mech_stats.total_weight = (_G.GameState.mech_stats.total_weight or 0) - pdata.weight
        end
    end

    table.remove(eq, index)
    print("LOG: Removed part", item.id, "from", item.col, item.row)
    return true
end

-- ==========================================
-- 狀態機接口
-- ==========================================

function StateHQ.setup()
    gfx.setFont(font) 
    
    -- 確保必要的全域變數存在
    _G.GameState = _G.GameState or {}
    -- 若有零件資料，將解鎖清單預設為 PartsData 的 key 清單
    if not _G.GameState.unlocked_parts then
        if _G.PartsData and next(_G.PartsData) then
            local list = {}
            for k, _ in pairs(_G.PartsData) do
                table.insert(list, k)
            end
            _G.GameState.unlocked_parts = list
        else
            _G.GameState.unlocked_parts = {"ARM-01", "LEG-02", "CORE-03"}
        end
    end

    _G.GameState.mech_stats = _G.GameState.mech_stats or { total_hp = 100, total_weight = 0, equipped_parts = {} }
    _G.GameState.mech_stats.equipped_parts = _G.GameState.mech_stats.equipped_parts or {}
    
    hq_mode = "EQUIP" -- 確保從組裝模式開始

    -- 初始化 GRID_MAP（row-major），nil 表示空
    GRID_MAP = {}
    for r = 1, GRID_ROWS do
        GRID_MAP[r] = {}
        for c = 1, GRID_COLS do
            GRID_MAP[r][c] = nil
        end
    end
end

function StateHQ.update()
    
    local unlocked_parts_count = _G.GameState and #(_G.GameState.unlocked_parts or {}) or 0

    if hq_mode == "EQUIP" then
        if is_placing_part then
            -- 模式 1A: 零件放置中 (移動網格游標)
            if playdate.buttonJustPressed(playdate.kButtonLeft) then
                cursor_col = math.max(1, cursor_col - 1)
            elseif playdate.buttonJustPressed(playdate.kButtonRight) then
                cursor_col = math.min(GRID_COLS, cursor_col + 1)
            elseif playdate.buttonJustPressed(playdate.kButtonUp) then
                cursor_row = math.max(1, cursor_row - 1)
            elseif playdate.buttonJustPressed(playdate.kButtonDown) then
                cursor_row = math.min(GRID_ROWS, cursor_row + 1)
            elseif playdate.buttonJustPressed(playdate.kButtonA) then
                -- 嘗試放置邏輯
                local part_id = _G.GameState.unlocked_parts[selected_part_index]
                local part_data = _G.PartsData and _G.PartsData[part_id]
                local can_fit, reason = checkIfFits(part_data, cursor_col, cursor_row)
                
                if can_fit then
                    -- 實際記錄放置：標記 GRID_MAP 並將零件加入 GameState
                    local w = part_data.slot_x or 1
                    local h = part_data.slot_y or 1
                    for r = cursor_row, cursor_row + h - 1 do
                        for c = cursor_col, cursor_col + w - 1 do
                            GRID_MAP[r][c] = part_id
                        end
                    end

                    -- 記錄到 equipped_parts（包含原點位置與尺寸）
                    table.insert(_G.GameState.mech_stats.equipped_parts, { id = part_id, col = cursor_col, row = cursor_row, w = w, h = h })

                    -- 更新 mech_stats（例如增加 HP、重量等，若 part_data 有對應欄位）
                    if part_data.hp then
                        _G.GameState.mech_stats.total_hp = (_G.GameState.mech_stats.total_hp or 0) + part_data.hp
                    end
                    if part_data.weight then
                        _G.GameState.mech_stats.total_weight = (_G.GameState.mech_stats.total_weight or 0) + part_data.weight
                    end

                    is_placing_part = false
                    print("LOG: Part placed successfully:", part_id, "at", cursor_col, cursor_row)
                else
                    print("LOG: Placement failed: " .. reason)
                end
            elseif playdate.buttonJustPressed(playdate.kButtonB) then
                is_placing_part = false -- 取消放置
            end
        else
            -- 模式 1B: 零件選擇/模式切換
            if playdate.buttonJustPressed(playdate.kButtonUp) then
                selected_part_index = math.max(1, selected_part_index - 1)
            elseif playdate.buttonJustPressed(playdate.kButtonDown) then
                selected_part_index = math.min(unlocked_parts_count, selected_part_index + 1)
            elseif playdate.buttonJustPressed(playdate.kButtonLeft) or playdate.buttonJustPressed(playdate.kButtonRight) then
                -- L/R 鍵: 左鍵進入 UNEQUIP，右鍵進入 MENU
                if playdate.buttonJustPressed(playdate.kButtonLeft) then
                    hq_mode = "UNEQUIP"
                else
                    hq_mode = "MENU"
                end
            elseif playdate.buttonJustPressed(playdate.kButtonA) then
                if selected_part_index >= 1 and selected_part_index <= unlocked_parts_count then
                    is_placing_part = true -- 進入放置模式
                end
            elseif playdate.buttonJustPressed(playdate.kButtonB) then
                hq_mode = "MENU" -- 進入底部選單
            end
        end
    
    elseif hq_mode == "UNEQUIP" then
        -- 模式 2: 拆卸零件邏輯 (簡化)
        if playdate.buttonJustPressed(playdate.kButtonLeft) or playdate.buttonJustPressed(playdate.kButtonRight) then
            hq_mode = "EQUIP"
        end
        -- ... 其他拆卸邏輯
        
    elseif hq_mode == "MENU" then
        -- 模式 3: 底部選單操作
        local menu_count = #MENU_OPTIONS
        if playdate.buttonJustPressed(playdate.kButtonUp) then
            menu_option_index = math.max(1, menu_option_index - 1)
        elseif playdate.buttonJustPressed(playdate.kButtonDown) then
            menu_option_index = math.min(menu_count, menu_option_index + 1)
        elseif playdate.buttonJustPressed(playdate.kButtonA) then
            -- 執行選單動作
            local action = MENU_OPTIONS[menu_option_index].action
            if action == "MISSION_SELECT" then
                -- ❗ 關鍵：跳轉到 StateMission
                print("LOG: HQ menu ACTION MISSION_SELECT selected. menu_option_index:", menu_option_index)
                if _G and _G.StateMission then
                    print("LOG: _G.StateMission found. Calling setState(_G.StateMission)")
                else
                    print("ERROR: _G.StateMission is nil! Cannot switch to mission state.")
                end
                setState(_G.StateMission)
            elseif action == "CONTINUE" then
                hq_mode = "EQUIP" -- 返回組裝
            end
        elseif playdate.buttonJustPressed(playdate.kButtonB) then
            hq_mode = "EQUIP" -- 返回組裝模式
        end
    
    elseif hq_mode == "UNEQUIP" then
        -- UNEQUIP 模式：在網格上選取已放置的零件並移除
        if playdate.buttonJustPressed(playdate.kButtonLeft) then
            cursor_col = math.max(1, cursor_col - 1)
        elseif playdate.buttonJustPressed(playdate.kButtonRight) then
            cursor_col = math.min(GRID_COLS, cursor_col + 1)
        elseif playdate.buttonJustPressed(playdate.kButtonUp) then
            cursor_row = math.max(1, cursor_row - 1)
        elseif playdate.buttonJustPressed(playdate.kButtonDown) then
            cursor_row = math.min(GRID_ROWS, cursor_row + 1)
        elseif playdate.buttonJustPressed(playdate.kButtonA) then
            -- 嘗試移除當前格子上的零件
            local idx, item = findEquippedPartAt(cursor_col, cursor_row)
            if idx and item then
                removeEquippedPart(idx)
            else
                print("LOG: No part at selected cell to remove.")
            end
        elseif playdate.buttonJustPressed(playdate.kButtonB) then
            hq_mode = "EQUIP" -- 返回組裝模式
        end
    end
end


function StateHQ.draw()
    
    gfx.clear(gfx.kColorWhite)
    gfx.setColor(gfx.kColorBlack)
    gfx.setFont(font) 
    
    -- 1. 繪製組裝網格背景 
    if ModuleUI and ModuleUI.drawUIBackground then
        ModuleUI.drawUIBackground() 
    end
    
    -- 2. 繪製機甲網格邊框 (作為機甲本體的佔位符)
    local mech_image_x = GRID_START_X
    local mech_image_y = GRID_START_Y
    local mech_width = GRID_CELL_SIZE * GRID_COLS
    local mech_height = GRID_CELL_SIZE * GRID_ROWS
    
    gfx.drawRect(mech_image_x, mech_image_y, mech_width, mech_height)
    gfx.drawText("MECH ASSEMBLY GRID", mech_image_x + 5, mech_image_y + 5)
    
    -- 繪製已放置的零件（以格子為單位）
    for r = 1, GRID_ROWS do
        for c = 1, GRID_COLS do
            local cell_x = GRID_START_X + (c - 1) * GRID_CELL_SIZE
            local cell_y = GRID_START_Y + (r - 1) * GRID_CELL_SIZE
            local pid = GRID_MAP[r] and GRID_MAP[r][c]
            if pid then
                local pdata = (_G.PartsData and _G.PartsData[pid]) or nil
                gfx.setColor(gfx.kColorBlack)
                gfx.drawRect(cell_x, cell_y, GRID_CELL_SIZE, GRID_CELL_SIZE)
                if pdata and pdata.name then
                    gfx.drawText(pdata.name, cell_x + 2, cell_y + 2)
                else
                    gfx.drawText(pid, cell_x + 2, cell_y + 2)
                end
            end
        end
    end
    
    -- 3. 繪製組裝游標 (白色方框，標示當前位置)
    if hq_mode == "EQUIP" and is_placing_part then
        local cursor_x = GRID_START_X + (cursor_col - 1) * GRID_CELL_SIZE
        local cursor_y = GRID_START_Y + (cursor_row - 1) * GRID_CELL_SIZE
        
        gfx.setColor(gfx.kColorWhite)
        gfx.fillRect(cursor_x, cursor_y, GRID_CELL_SIZE, GRID_CELL_SIZE)
        gfx.setColor(gfx.kColorBlack)
        gfx.drawRect(cursor_x, cursor_y, GRID_CELL_SIZE, GRID_CELL_SIZE)
    end

    -- 如果在 UNEQUIP 模式，繪製游標框並顯示要移除的零件資訊（若有）
    if hq_mode == "UNEQUIP" then
        local cursor_x = GRID_START_X + (cursor_col - 1) * GRID_CELL_SIZE
        local cursor_y = GRID_START_Y + (cursor_row - 1) * GRID_CELL_SIZE
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
    
    -- 4. 繪製零件清單 (左側)
    gfx.drawText("PARTS LIST:", 10, 30)
    local list_y = 50
    local line_height = 15
    local unlocked_parts = _G.GameState and _G.GameState.unlocked_parts or {}
    
    for i, part_id in ipairs(unlocked_parts) do
        local display_text = part_id 
        local current_y = list_y + (i - 1) * line_height
        
        if hq_mode == "EQUIP" and not is_placing_part and i == selected_part_index then
            display_text = "> " .. display_text .. " <"
        end
        gfx.drawText(display_text, 10, current_y)
    end
    
    -- 5. 繪製零件詳細資訊 / 狀態 (右側)
    local detail_x = 250
    local detail_y = 30
    gfx.drawText("MECH STATS:", detail_x, detail_y)
    local stats = _G.GameState and _G.GameState.mech_stats or { total_hp = 0, total_weight = 0 }
    gfx.drawText("HP: " .. stats.total_hp, detail_x, detail_y + 20)
    gfx.drawText("Weight: " .. stats.total_weight, detail_x, detail_y + 40)
    
    -- 6. 繪製 UI 說明 (底部)
    local action_text = ""
    local dpad_text = ""
    local ui_base_y = UI_AREA_Y_START + 5
    
    if hq_mode == "EQUIP" then
        if is_placing_part then
            action_text = "A to CONFIRM; B to CANCEL placement"
            dpad_text = "U/D/L/R move cursor"
        else
            action_text = "A to SELECT part; B for MENU"
            dpad_text = "U/D select part; L/R for UNEQUIP/MENU"
        end
        gfx.drawText(action_text, 10, ui_base_y)
        gfx.drawText(dpad_text, 10, ui_base_y + 15)
        
    elseif hq_mode == "UNEQUIP" then
        action_text = "A to UNEQUIP; B for MENU"
        dpad_text = "U/D select part; L/R for EQUIP"
        gfx.drawText(action_text, 10, ui_base_y)
        gfx.drawText(dpad_text, 10, ui_base_y + 15)
    -- 注意: 輸入處理在 update() 中統一處理，draw() 僅負責繪製

        
    elseif hq_mode == "MENU" then
        -- 僅繪製選單內容，輸入在 update() 中處理
        gfx.drawText("MENU:", 10, ui_base_y)
        local menu_x = 10
        local menu_y = ui_base_y + 18
        local menu_line_h = 14
        for i, opt in ipairs(MENU_OPTIONS) do
            local text = opt.name
            if i == menu_option_index then
                text = "> " .. text .. " <"
            end
            gfx.drawText(text, menu_x, menu_y + (i - 1) * menu_line_h)
        end
    end
end

return StateHQ