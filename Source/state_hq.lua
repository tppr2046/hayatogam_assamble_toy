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
    -- 簡單檢查：不允許在 (1,1) 放置 (您可以在這裡加入您的網格碰撞檢查)
    if start_col == 1 and start_row == 1 then
        return false, "Blocked by core"
    end
    return true, ""
end

-- ==========================================
-- 狀態機接口
-- ==========================================

function StateHQ.setup()
    gfx.setFont(font) 
    
    -- 確保必要的全域變數存在
    if not _G.GameState or not _G.GameState.unlocked_parts then
        _G.GameState = _G.GameState or {}
        _G.GameState.unlocked_parts = {"ARM-01", "LEG-02", "CORE-03"} -- 預設值
    end
    _G.GameState.mech_stats = _G.GameState.mech_stats or { total_hp = 100, total_weight = 0 }
    
    hq_mode = "EQUIP" -- 確保從組裝模式開始
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
                    -- 假設放置成功 (這裡需要您的實際放置程式碼)
                    is_placing_part = false
                    print("LOG: Part placed successfully.")
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
                hq_mode = "MENU" -- L/R 鍵切換到選單或拆卸 (這裡切換到 MENU)
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
                setState(_G.StateMission) 
            elseif action == "CONTINUE" then
                hq_mode = "EQUIP" -- 返回組裝
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
    
    -- 3. 繪製組裝游標 (白色方框，標示當前位置)
    if hq_mode == "EQUIP" and is_placing_part then
        local cursor_x = GRID_START_X + (cursor_col - 1) * GRID_CELL_SIZE
        local cursor_y = GRID_START_Y + (cursor_row - 1) * GRID_CELL_SIZE
        
        gfx.setColor(gfx.kColorWhite)
        gfx.fillRect(cursor_x, cursor_y, GRID_CELL_SIZE, GRID_CELL_SIZE)
        gfx.setColor(gfx.kColorBlack)
        gfx.drawRect(cursor_x, cursor_y, GRID_CELL_SIZE, GRID_CELL_SIZE)
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
            -- 按 B 鍵進入底部菜單 (MENU)
            if playdate.buttonJustPressed(playdate.kButtonB) then
                hq_mode = "MENU" -- ❗ 關鍵：從 EQUIP 切換到 MENU
                menu_option_index = 1 -- 重設選單選項
            end
        end
        gfx.drawText(action_text, 10, ui_base_y)
        gfx.drawText(dpad_text, 10, ui_base_y + 15)
        
    elseif hq_mode == "UNEQUIP" then
        action_text = "A to UNEQUIP; B for MENU"
        dpad_text = "U/D select part; L/R for EQUIP"
        gfx.drawText(action_text, 10, ui_base_y)
        gfx.drawText(dpad_text, 10, ui_base_y + 15)
-- 按 B 鍵進入底部菜單 (MENU)
    if playdate.buttonJustPressed(playdate.kButtonB) then
        hq_mode = "MENU" -- ❗ 關鍵：從 UNEQUIP 切換到 MENU
        menu_option_index = 1 -- 重設選單選項
    end

        
    elseif hq_mode == "MENU" then
    
    -- 處理 A 鍵確認
    if playdate.buttonJustPressed(playdate.kButtonA) then
        local selection = MENU_OPTIONS[menu_option_index].action
        
        if selection == "MISSION_SELECT" then
            -- ❗ 關鍵修正：從 HQ 進入任務狀態
            setState(StateMission) 
            return -- 處理完畢，退出
        elseif selection == "CONTINUE" then
            -- 返回組裝介面
            hq_mode = "EQUIP"
        end
    
    -- 處理 D-Pad 上下選擇菜單
    elseif playdate.buttonJustPressed(playdate.kButtonUp) then
        menu_option_index = menu_option_index - 1
        if menu_option_index < 1 then menu_option_index = #MENU_OPTIONS end
    elseif playdate.buttonJustPressed(playdate.kButtonDown) then
        menu_option_index = menu_option_index + 1
        if menu_option_index > #MENU_OPTIONS then menu_option_index = 1 end
    
    -- 處理 D-Pad 左右切換模式 (返回 EQUIP)
    elseif playdate.buttonJustPressed(playdate.kButtonLeft) or playdate.buttonJustPressed(playdate.kButtonRight) then
        hq_mode = "EQUIP"
    end
    
    end
end

return StateHQ