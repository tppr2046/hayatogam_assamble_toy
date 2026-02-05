-- state_hq.lua (Version 8.4 - 恢復所有繪圖與操作邏輯)

import "CoreLibs/graphics" 

local gfx = playdate.graphics  
local default_font = gfx.font.systemFont
-- MissionData 現在從 _G.MissionData 獲取（在 main.lua 中載入）

-- 確保字形載入成功
local custom_font_path = 'fonts/Assemble' 
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
local GRID_START_Y = 60  -- 往下移動，為預覽留出空間

-- UI 控制介面相關
local UI_GRID_COLS = 3
local UI_GRID_ROWS = 2
local UI_CELL_SIZE = 32
local UI_START_X = 10
local UI_START_Y = GAME_HEIGHT + 5   

local GRID_MAP = {}       
local cursor_col = 1      
local cursor_row = 1      
local cursor_on_ready = false  -- 游標是否在 READY 選項上
local cursor_on_shop = false   -- 游標是否在 SHOP 選項上
local cursor_on_back = false   -- 遊標是否在 BACK 選項上
local is_unequip_mode = false  -- 是否在解除裝備模式
local unequip_selected_col = 1  -- 解除模式選中的格子列
local unequip_selected_row = 1  -- 解除模式選中的格子排
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
local cursor_blink_tick = 0  -- 控制粗邊框的閃爍
-- 播放標題/一般介面 BGM（循環）
function StateHQ.setupBGM()
    if _G.SoundManager and _G.SoundManager.playTitleBGM then
        _G.SoundManager.playTitleBGM()
    end
end
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

    -- 將零件重新加入可用清單（TOP/BOTTOM/BOTH）
    local parts_by_category = _G.GameState and _G.GameState.parts_by_category
    local pdata = _G.PartsData and _G.PartsData[item.id]
    if parts_by_category and pdata then
        local pr = pdata.placement_row or "BOTH"
        local function insert_if_missing(cat)
            local list = parts_by_category[cat]
            if list then
                local exists = false
                for _, pid in ipairs(list) do
                    if pid == item.id then exists = true break end
                end
                if not exists then table.insert(list, item.id) end
            end
        end
        if pr == "TOP" or pr == "BOTH" then insert_if_missing("TOP") end
        if pr == "BOTTOM" or pr == "BOTH" then insert_if_missing("BOTTOM") end
    end
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


-- ==========================================
-- 狀態機接口
-- ==========================================

function StateHQ.setup()
    gfx.setFont(font) 
    -- 播放標題/一般介面 BGM（循環）
    if _G.SoundManager and _G.SoundManager.playTitleBGM then
        _G.SoundManager.playTitleBGM()
    end
    
    -- 初始化 MechController（用於繪製介面圖）
    if MechController and MechController.init then
        mech_controller = MechController:init()
    else
        print("WARNING: MechController not found in state_hq")
    end
    
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
    cursor_on_shop = false
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
                if pdata.arm_image then
                    local arm_img = gfx.image.new(pdata.arm_image)
                    if arm_img then
                        pdata._arm_img = arm_img
                    else
                        print("ERROR: Failed to load arm_image:", pdata.arm_image)
                    end
                end
                if pdata.upper_image then
                    local upper_img = gfx.image.new(pdata.upper_image)
                    if upper_img then
                        pdata._upper_img = upper_img
                    else
                        print("ERROR: Failed to load upper_image:", pdata.upper_image)
                    end
                end
                if pdata.lower_image then
                    local lower_img = gfx.image.new(pdata.lower_image)
                    if lower_img then
                        pdata._lower_img = lower_img
                    else
                        print("ERROR: Failed to load lower_image:", pdata.lower_image)
                    end
                end
            end
            
            -- 載入 CANON 的底座圖片
            if pdata.base_image then
                local base_img = gfx.image.new(pdata.base_image)
                if base_img then
                    pdata._base_img = base_img
                else
                    print("ERROR: Failed to load base_image for", pid, pdata.base_image)
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
                        -- 繪製 CLAW 的額外部件到 scaled image
                        if pid == "CLAW" then
                            if pdata._arm_img then pcall(function() pdata._arm_img:draw(math.max(0, dx or 0), math.max(0, dy or 0)) end) end
                            if pdata._upper_img then pcall(function() pdata._upper_img:draw(math.max(0, dx or 0), math.max(0, dy or 0)) end) end
                            if pdata._lower_img then pcall(function() pdata._lower_img:draw(math.max(0, dx or 0), math.max(0, dy or 0)) end) end
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
    
    if is_unequip_mode then
        -- 解除裝備模式
        local eq = _G.GameState.mech_stats.equipped_parts or {}
        
        if playdate.buttonJustPressed(playdate.kButtonLeft) then
            -- 在最左邊格子按左鍵回到零件清單
            if unequip_selected_col == 1 then
                is_unequip_mode = false
            else
                unequip_selected_col = math.max(1, unequip_selected_col - 1)
            end
            -- 播放游標移動音效
            if _G.SoundManager and _G.SoundManager.playCursorMove then
                _G.SoundManager.playCursorMove()
            end
        elseif playdate.buttonJustPressed(playdate.kButtonRight) then
            unequip_selected_col = math.min(GRID_COLS, unequip_selected_col + 1)
            -- 播放游標移動音效
            if _G.SoundManager and _G.SoundManager.playCursorMove then
                _G.SoundManager.playCursorMove()
            end
        elseif playdate.buttonJustPressed(playdate.kButtonUp) then
            -- 從下排跳到上排的零件
            for _, item in ipairs(eq) do
                if item.row == 2 then
                    unequip_selected_col = item.col
                    unequip_selected_row = item.row
                    break
                end
            end
            -- 播放游標移動音效
            if _G.SoundManager and _G.SoundManager.playCursorMove then
                _G.SoundManager.playCursorMove()
            end
        elseif playdate.buttonJustPressed(playdate.kButtonDown) then
            -- 從上排跳到下排的零件
            for _, item in ipairs(eq) do
                if item.row == 1 then
                    unequip_selected_col = item.col
                    unequip_selected_row = item.row
                    break
                end
            end
            -- 播放游標移動音效
            if _G.SoundManager and _G.SoundManager.playCursorMove then
                _G.SoundManager.playCursorMove()
            end
        elseif playdate.buttonJustPressed(playdate.kButtonA) then
            -- 解除選中格子上的零件
            for i = #eq, 1, -1 do
                local item = eq[i]
                local slot_w = item.w or 1
                local slot_h = item.h or 1
                -- 檢查選中的格子是否在零件範圍內
                if unequip_selected_col >= item.col and unequip_selected_col < item.col + slot_w and
                   unequip_selected_row >= item.row and unequip_selected_row < item.row + slot_h then
                    -- 從 equipped_parts 移除
                    table.remove(eq, i)
                    
                    -- 將零件重新添加到左側清單
                    local part_data = _G.PartsData and _G.PartsData[item.id]
                    if part_data then
                        local placement_row = part_data.placement_row
                        local category = (placement_row == "TOP") and "TOP" or "BOTTOM"
                        
                        -- 檢查該零件是否已在清單中（避免重複）
                        local parts_list = _G.GameState.parts_by_category[category] or {}
                        local already_in_list = false
                        for _, pid in ipairs(parts_list) do
                            if pid == item.id then
                                already_in_list = true
                                break
                            end
                        end
                        
                        -- 如果不在清單中，加入
                        if not already_in_list then
                            table.insert(_G.GameState.parts_by_category[category], item.id)
                        end
                    end
                    
                    -- 從 GRID_MAP 清除
                    for r = item.row, item.row + slot_h - 1 do
                        for c = item.col, item.col + slot_w - 1 do
                            GRID_MAP[r][c] = nil
                        end
                    end
                    
                    -- 扣除 HP 和 Weight
                    if part_data then
                        if part_data.hp then
                            _G.GameState.mech_stats.total_hp = (_G.GameState.mech_stats.total_hp or 0) - part_data.hp
                        end
                        if part_data.weight then
                            _G.GameState.mech_stats.total_weight = (_G.GameState.mech_stats.total_weight or 0) - part_data.weight
                        end
                    end
                    
                    print("Unequipped part: " .. item.id)
                    -- 播放選擇音效
                    if _G.SoundManager and _G.SoundManager.playSelect then
                        _G.SoundManager.playSelect()
                    end
                    break
                end
            end
        elseif playdate.buttonJustPressed(playdate.kButtonB) then
            -- 按 B 返回零件清單
            is_unequip_mode = false
        end
        return
    end
    
    if hq_mode == "EQUIP" then
        if is_placing_part then
            -- 零件放置中：移動網格游標
            if playdate.buttonJustPressed(playdate.kButtonLeft) then
                cursor_col = math.max(1, cursor_col - 1)
                -- 播放游標移動音效
                if _G.SoundManager and _G.SoundManager.playCursorMove then
                    _G.SoundManager.playCursorMove()
                end
            elseif playdate.buttonJustPressed(playdate.kButtonRight) then
                cursor_col = math.min(GRID_COLS, cursor_col + 1)
                -- 播放游標移動音效
                if _G.SoundManager and _G.SoundManager.playCursorMove then
                    _G.SoundManager.playCursorMove()
                end
            elseif playdate.buttonJustPressed(playdate.kButtonUp) then
                cursor_row = math.min(GRID_ROWS, cursor_row + 1)
                -- 播放游標移動音效
                if _G.SoundManager and _G.SoundManager.playCursorMove then
                    _G.SoundManager.playCursorMove()
                end
            elseif playdate.buttonJustPressed(playdate.kButtonDown) then
                cursor_row = math.max(1, cursor_row - 1)
                -- 播放游標移動音效
                if _G.SoundManager and _G.SoundManager.playCursorMove then
                    _G.SoundManager.playCursorMove()
                end
            elseif playdate.buttonJustPressed(playdate.kButtonB) then
                -- 取消放置，返回零件清單
                is_placing_part = false
                if _G.SoundManager and _G.SoundManager.playCancel then
                    _G.SoundManager.playCancel()
                end
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
                        
                        -- 自動儲存機甲配置
                        if _G.SaveManager and _G.SaveManager.saveCurrent then
                            _G.SaveManager.saveCurrent()
                            print("LOG: Mech configuration auto-saved.")
                        end
                        -- 播放選擇音效
                        if _G.SoundManager and _G.SoundManager.playSelect then
                            _G.SoundManager.playSelect()
                        end
                        
                        is_placing_part = false
                        
                        -- 檢查該分類（TOP/BOTTOM）是否已滿，如果滿了就返回分類選擇
                        local eq = _G.GameState.mech_stats.equipped_parts or {}
                        local has_top_part = false
                        local has_bottom_part = false
                        
                        for _, item in ipairs(eq) do
                            for r = item.row, item.row + (item.h or 1) - 1 do
                                if r == 2 then has_top_part = true end
                                if r == 1 then has_bottom_part = true end
                            end
                        end
                        
                        -- 如果當前分類是 TOP 且已有上半部零件，或是 BOTTOM 且已有下半部零件，則返回分類選擇
                        if (selected_category == "TOP" and has_top_part) or (selected_category == "BOTTOM" and has_bottom_part) then
                            selected_category = nil
                            selected_part_index = 1
                        else
                            -- 否則，自動選取下一個未裝備的零件
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
            if playdate.buttonJustPressed(playdate.kButtonUp) then
                cursor_on_back = false
                cursor_on_ready = true
                -- 播放游標移動音效
                if _G.SoundManager and _G.SoundManager.playCursorMove then
                    _G.SoundManager.playCursorMove()
                end
            elseif playdate.buttonJustPressed(playdate.kButtonA) then
                -- 返回任務選擇畫面
                -- 播放選擇音效
                if _G.SoundManager and _G.SoundManager.playSelect then
                    _G.SoundManager.playSelect()
                end
                setState(_G.StateMissionSelect)
            end
        elseif cursor_on_ready then
            -- 游標在 READY 上
            if show_ready_menu then
                -- READY 選單打開
                if playdate.buttonJustPressed(playdate.kButtonDown) then
                    menu_option_index = math.min(2, menu_option_index + 1)
                    -- 播放游標移動音效
                    if _G.SoundManager and _G.SoundManager.playCursorMove then
                        _G.SoundManager.playCursorMove()
                    end
                elseif playdate.buttonJustPressed(playdate.kButtonUp) then
                    menu_option_index = math.max(1, menu_option_index - 1)
                    -- 播放游標移動音效
                    if _G.SoundManager and _G.SoundManager.playCursorMove then
                        _G.SoundManager.playCursorMove()
                    end
                elseif playdate.buttonJustPressed(playdate.kButtonA) then
                    -- 播放選擇音效
                    if _G.SoundManager and _G.SoundManager.playSelect then
                        _G.SoundManager.playSelect()
                    end
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
                    cursor_on_shop = true  -- 回到 SHOP
                    -- 播放游標移動音效
                    if _G.SoundManager and _G.SoundManager.playCursorMove then
                        _G.SoundManager.playCursorMove()
                    end
                elseif playdate.buttonJustPressed(playdate.kButtonDown) then
                    -- 從 READY 移動到 BACK
                    cursor_on_ready = false
                    cursor_on_back = true
                    -- 播放游標移動音效
                    if _G.SoundManager and _G.SoundManager.playCursorMove then
                        _G.SoundManager.playCursorMove()
                    end
                elseif playdate.buttonJustPressed(playdate.kButtonA) then
                    show_ready_menu = true
                    menu_option_index = 1
                    -- 播放選擇音效
                    if _G.SoundManager and _G.SoundManager.playSelect then
                        _G.SoundManager.playSelect()
                    end
                end
            end
        elseif not selected_category then
            -- 選擇分類或導航到 SHOP/READY
            if playdate.buttonJustPressed(playdate.kButtonUp) then
                if cursor_on_shop then
                    cursor_on_shop = false
                    selected_part_index = last_part_index or 2  -- 回到 BOTTOM PARTS
                elseif cursor_on_ready then
                    cursor_on_ready = false
                    cursor_on_shop = true  -- 從 READY 向上到 SHOP
                else
                    selected_part_index = (selected_part_index == 1) and 2 or 1
                end
                -- 播放游標移動音效
                if _G.SoundManager and _G.SoundManager.playCursorMove then
                    _G.SoundManager.playCursorMove()
                end
            elseif playdate.buttonJustPressed(playdate.kButtonDown) then
                if selected_part_index == 2 then
                    cursor_on_shop = true
                    selected_part_index = 0  -- 清除零件選取狀態
                    last_part_index = 2  -- 記住最後位置
                elseif cursor_on_shop then
                    cursor_on_shop = false
                    cursor_on_ready = true  -- 從 SHOP 向下到 READY
                else
                    selected_part_index = 2
                end
                -- 播放游標移動音效
                if _G.SoundManager and _G.SoundManager.playCursorMove then
                    _G.SoundManager.playCursorMove()
                end
            elseif playdate.buttonJustPressed(playdate.kButtonA) then
                if cursor_on_shop then
                    -- 進入商店狀態
                    -- 播放選擇音效
                    if _G.SoundManager and _G.SoundManager.playSelect then
                        _G.SoundManager.playSelect()
                    end
                    setState(_G.StateShop)
                elseif not cursor_on_ready then
                    selected_category = (selected_part_index == 1) and "TOP" or "BOTTOM"
                    selected_part_index = 1
                    -- 播放選擇音效
                    if _G.SoundManager and _G.SoundManager.playSelect then
                        _G.SoundManager.playSelect()
                    end
                end
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
                -- 播放游標移動音效
                if _G.SoundManager and _G.SoundManager.playCursorMove then
                    _G.SoundManager.playCursorMove()
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
                -- 播放游標移動音效
                if _G.SoundManager and _G.SoundManager.playCursorMove then
                    _G.SoundManager.playCursorMove()
                end
            elseif playdate.buttonJustPressed(playdate.kButtonRight) then
                -- 按右鍵進入解除裝備模式
                is_unequip_mode = true
                -- 初始化選中第一個已安裝的零件
                local eq = _G.GameState.mech_stats.equipped_parts or {}
                if #eq > 0 then
                    unequip_selected_col = eq[1].col
                    unequip_selected_row = eq[1].row
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
                    -- 播放選擇音效
                    if _G.SoundManager and _G.SoundManager.playSelect then
                        _G.SoundManager.playSelect()
                    end
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
            -- 播放游標移動音效
            if _G.SoundManager and _G.SoundManager.playCursorMove then
                _G.SoundManager.playCursorMove()
            end
        elseif playdate.buttonJustPressed(playdate.kButtonRight) then
            cursor_col = math.min(GRID_COLS, cursor_col + 1)
            -- 播放游標移動音效
            if _G.SoundManager and _G.SoundManager.playCursorMove then
                _G.SoundManager.playCursorMove()
            end
        elseif playdate.buttonJustPressed(playdate.kButtonUp) then
            cursor_row = math.min(GRID_ROWS, cursor_row + 1)
            -- 播放游標移動音效
            if _G.SoundManager and _G.SoundManager.playCursorMove then
                _G.SoundManager.playCursorMove()
            end
        elseif playdate.buttonJustPressed(playdate.kButtonDown) then
            cursor_row = math.max(1, cursor_row - 1)
            -- 播放游標移動音效
            if _G.SoundManager and _G.SoundManager.playCursorMove then
                _G.SoundManager.playCursorMove()
            end
        elseif playdate.buttonJustPressed(playdate.kButtonA) then
            local idx, item = findEquippedPartAt(cursor_col, cursor_row)
            if idx and item then
                removeEquippedPart(idx)
                -- 播放選擇音效
                if _G.SoundManager and _G.SoundManager.playSelect then
                    _G.SoundManager.playSelect()
                end
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

    -- 更新粗邊框閃爍計時
    cursor_blink_tick = (cursor_blink_tick + 1) % 20
end


function StateHQ.draw()
    
    gfx.clear(gfx.kColorWhite)
    gfx.setColor(gfx.kColorBlack)
    gfx.setFont(font) 
    -- 使用時間為基準的閃爍，避免某些情況下 tick 未更新導致不閃爍
    local blink_on = (math.floor(playdate.getCurrentTimeMilliseconds() / 250) % 2) == 0
    
    -- 1. 繪製組裝網格背景
    
    -- 2. 繪製機甲網格邊框 (作為機甲本體的佔位符)
    local mech_image_x = GRID_START_X
    local mech_image_y = GRID_START_Y
    local mech_width = GRID_CELL_SIZE * GRID_COLS
    local mech_height = GRID_CELL_SIZE * GRID_ROWS
    
    gfx.drawRect(mech_image_x, mech_image_y, mech_width, mech_height)
--    gfx.drawText("MECH ASSEMBLY GRID", mech_image_x + 5, mech_image_y + 5)
    
    -- Grid and parts rendering handled below (draw grid lines, then draw each equipped part once)
    
    -- 3. 繪製零件預覽 (選中零件後，即使沒進入放置模式也顯示預覽；解除模式時不顯示)
    if hq_mode == "EQUIP" and selected_category and selected_part_index and not cursor_on_ready and not is_unequip_mode then
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
                preview_y = GRID_START_Y - sh - 10  -- 組裝格上方，留40像素間距
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
                -- CANON 特殊處理：繪製底座
                if part_id == "CANON1" or part_id == "CANON2" then
                    if pdata._base_img then
                        pcall(function() pdata._base_img:draw(preview_x, draw_y) end)
                    end
                end
                gfx.setColor(gfx.kColorBlack)
                gfx.drawRect(preview_x, draw_y, sw, sh)
                -- 在選擇時繪製閃爍邊框
                if blink_on then
                    gfx.setLineWidth(3)
                    gfx.drawRect(preview_x - 2, draw_y - 2, sw + 4, sh + 4)
                    gfx.setLineWidth(1)
                end
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
                -- CANON 特殊處理：繪製底座（在砲管後繪製，這樣底座會顯示在上面）
                if part_id == "CANON1" or part_id == "CANON2" then
                    if pdata._base_img then
                        local ok_base, base_width, base_height = pcall(function() return pdata._base_img:getSize() end)
                        if ok_base and base_width and base_height then
                            local base_draw_x = preview_x + math.floor((GRID_CELL_SIZE - base_width) / 2)
                            local base_draw_y = preview_y + math.floor((GRID_CELL_SIZE - base_height) / 2)
                            pcall(function() pdata._base_img:draw(base_draw_x, base_draw_y) end)
                        else
                            pcall(function() pdata._base_img:draw(draw_x, draw_y) end)
                        end
                    end
                end
                gfx.setColor(gfx.kColorBlack)
                gfx.drawRect(preview_x, preview_y, GRID_CELL_SIZE, GRID_CELL_SIZE)
                -- 在選擇時繪製閃爍邊框
                if blink_on then
                    gfx.setLineWidth(3)
                    gfx.drawRect(preview_x - 2, preview_y - 2, GRID_CELL_SIZE + 4, GRID_CELL_SIZE + 4)
                    gfx.setLineWidth(1)
                end
            end
        end
    end

    -- 如果在解除裝備模式，繪製選中框
    if is_unequip_mode and blink_on then
        local cursor_x = GRID_START_X + (unequip_selected_col - 1) * GRID_CELL_SIZE
        local cursor_y = GRID_START_Y + (GRID_ROWS - unequip_selected_row) * GRID_CELL_SIZE
        
        -- 繪製粗框標示選取的零件
        gfx.setColor(gfx.kColorBlack)
        gfx.setLineWidth(2)
        
        -- 找出選中格子所屬的零件並繪製完整範圍的框
        local eq = _G.GameState.mech_stats.equipped_parts or {}
        for _, item in ipairs(eq) do
            local slot_w = item.w or 1
            local slot_h = item.h or 1
            if unequip_selected_col >= item.col and unequip_selected_col < item.col + slot_w and
               unequip_selected_row >= item.row and unequip_selected_row < item.row + slot_h then
                local fx = GRID_START_X + (item.col - 1) * GRID_CELL_SIZE
                local fy = GRID_START_Y + (GRID_ROWS - item.row) * GRID_CELL_SIZE - (slot_h - 1) * GRID_CELL_SIZE
                local fw = slot_w * GRID_CELL_SIZE
                local fh = slot_h * GRID_CELL_SIZE
                gfx.drawRect(fx, fy, fw, fh)
                break
            end
        end
        
        gfx.setLineWidth(1)
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
    gfx.drawText("PARTS:", 5, 20)
    local list_y = 50
    local line_height = 15
    
    if not selected_category then
        -- 顯示分類選擇
        local categories = {"TOP PARTS", "BOTTOM PARTS"}
        for i = 1, 2 do
            local text = categories[i]
            if i == selected_part_index then
                if blink_on then
                    text = "> " .. text .. " <"
                else
                    text = "  " .. text .. "  "
                end
            end
            gfx.drawText(text, 10, list_y + (i - 1) * line_height)
        end
        
        -- 繪製 SHOP 選項
        local shop_y = list_y + 2 * line_height
        local shop_text
        if cursor_on_shop then
            shop_text = blink_on and "> SHOP <" or "  SHOP  "
        else
            shop_text = "  SHOP"
        end
        gfx.drawText(shop_text, 10, shop_y)
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
                if i == selected_part_index and not cursor_on_ready and not is_unequip_mode then
                    if blink_on then
                        text = "> " .. text .. " <"
                    else
                        text = "  " .. text .. "  "
                    end
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
    
    -- 預覽模式：在組裝格子上顯示 dither.png（解除模式時不顯示預覽）
    if selected_category and selected_part_index and not cursor_on_ready and not is_placing_part and not is_unequip_mode then
        local parts_list = _G.GameState.parts_by_category[selected_category]
        local part_id = parts_list and parts_list[selected_part_index]
        local pdata = _G.PartsData and _G.PartsData[part_id]
        
        if pdata and mech_controller and mech_controller.ui_images and mech_controller.ui_images.dither then
            local placement_row = pdata.placement_row
            
            -- 找出第一個空格子（預覽位置）
            local check_col, check_row = findFirstEmptyCell(pdata)
            
            if check_col and check_row then
                -- 根據 placement_row 決定 dither 顯示在哪一排
                local dither_row = nil
                if placement_row == "TOP" or (check_row == 2) then
                    -- TOP 零件安裝在上排，在下排（row=1）顯示 dither
                    dither_row = 1
                elseif placement_row == "BOTTOM" or (check_row == 1) then
                    -- BOTTOM 零件安裝在下排，在上排（row=2）顯示 dither
                    dither_row = 2
                end
                
                -- 繪製 dither.png 在對應的排上（整排 3 格）
                if dither_row then
                    for c = 1, GRID_COLS do
                        local dither_x = GRID_START_X + (c - 1) * GRID_CELL_SIZE
                        local dither_y = GRID_START_Y + (GRID_ROWS - dither_row) * GRID_CELL_SIZE
                        pcall(function() mech_controller.ui_images.dither:draw(dither_x, dither_y) end)
                    end
                end
            end
        end
    end
    
    -- 繪製已放置的零件，每個零件只繪製一次，佔據 w x h 格
    -- 分兩階段繪製：先下排(row=1)再上排(row=2)
                local eq = _G.GameState and _G.GameState.mech_stats and _G.GameState.mech_stats.equipped_parts or {}
                
                -- 第一階段：繪製下排零件（row=1）和對應的上排格子 dither
                for _, item in ipairs(eq) do
                    if item.row == 1 then
                        local pid = item.id
                        local pdata = (_G.PartsData and _G.PartsData[pid]) or nil
                        local px = GRID_START_X + (item.col - 1) * GRID_CELL_SIZE
                        -- convert item.row (bottom-left origin) to top-based y
                        local py_top = GRID_START_Y + (GRID_ROWS - item.row) * GRID_CELL_SIZE
                        local pw = (item.w or 1) * GRID_CELL_SIZE
                        local ph = (item.h or 1) * GRID_CELL_SIZE
                        
                        -- 繪製零件圖片
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
                            -- 繪製 CANON 的底座
                            if pid == "CANON1" or pid == "CANON2" then
                                if pdata._base_img then
                                    pcall(function() pdata._base_img:draw(draw_x, draw_y) end)
                                end
                            end
                        else
                            -- no image: draw text label at the origin cell
                            gfx.setColor(gfx.kColorBlack)
                            gfx.drawText(pid or "?", px + 2, py_top + 2)
                        end
                    end
                end
                
                -- 第二階段：繪製上排零件（row=2）和對應的下排格子 dither
                for _, item in ipairs(eq) do
                    if item.row == 2 then
                        local pid = item.id
                        local pdata = (_G.PartsData and _G.PartsData[pid]) or nil
                        local px = GRID_START_X + (item.col - 1) * GRID_CELL_SIZE
                        -- convert item.row (bottom-left origin) to top-based y
                        local py_top = GRID_START_Y + (GRID_ROWS - item.row) * GRID_CELL_SIZE
                        local pw = (item.w or 1) * GRID_CELL_SIZE
                        local ph = (item.h or 1) * GRID_CELL_SIZE
                        
                        -- 繪製零件圖片
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
                            -- 繪製 CANON 的底座
                            if pid == "CANON1" or pid == "CANON2" then
                                if pdata._base_img then
                                    pcall(function() pdata._base_img:draw(px, py_top) end)
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
                            -- CLAW 特殊處理：繪製額外部件
                            if pid == "CLAW" then
                                if pdata._arm_img then pcall(function() pdata._arm_img:draw(draw_x, draw_y) end) end
                                if pdata._upper_img then pcall(function() pdata._upper_img:draw(draw_x, draw_y) end) end
                                if pdata._lower_img then pcall(function() pdata._lower_img:draw(draw_x, draw_y) end) end
                            end
                            -- CANON 特殊處理：繪製底座
                            if pid == "CANON1" or pid == "CANON2" then
                                if pdata._base_img then
                                    pcall(function() pdata._base_img:draw(draw_x, draw_y) end)
                                end
                            end
                        else
                            -- no image: draw text label at the origin cell
                            gfx.setColor(gfx.kColorBlack)
                            gfx.drawText(pid or "?", px + 2, py_top + 2)
                        end
                    end
                end

    -- 繪製置中的粗框（放置模式／拆卸模式），在零件圖上層
    if blink_on then
        -- 放置模式：在組裝格中繪製粗邊框
        if hq_mode == "EQUIP" and is_placing_part and selected_category and selected_part_index then
            local parts_list = _G.GameState.parts_by_category[selected_category]
            local part_id = parts_list and parts_list[selected_part_index]
            local pdata = _G.PartsData and _G.PartsData[part_id]
            if pdata then
                local w = pdata.slot_x or 1
                local h = pdata.slot_y or 1
                local fx = GRID_START_X + (cursor_col - 1) * GRID_CELL_SIZE
                local fy = GRID_START_Y + (GRID_ROWS - cursor_row) * GRID_CELL_SIZE - (h - 1) * GRID_CELL_SIZE
                local fw = w * GRID_CELL_SIZE
                local fh = h * GRID_CELL_SIZE
                gfx.setColor(gfx.kColorBlack)
                gfx.setLineWidth(2)
                gfx.drawRect(fx, fy, fw, fh)
                gfx.setLineWidth(1)
            end
        end

        -- 拆卸模式：在選中的零件上繪製粗邊框
        if is_unequip_mode then
            local eq2 = _G.GameState.mech_stats.equipped_parts or {}
            for _, item in ipairs(eq2) do
                local slot_w = item.w or 1
                local slot_h = item.h or 1
                if unequip_selected_col >= item.col and unequip_selected_col < item.col + slot_w and
                   unequip_selected_row >= item.row and unequip_selected_row < item.row + slot_h then
                    local fx = GRID_START_X + (item.col - 1) * GRID_CELL_SIZE
                    local fy = GRID_START_Y + (GRID_ROWS - item.row) * GRID_CELL_SIZE - (slot_h - 1) * GRID_CELL_SIZE
                    local fw = slot_w * GRID_CELL_SIZE
                    local fh = slot_h * GRID_CELL_SIZE
                    gfx.setColor(gfx.kColorBlack)
                    gfx.setLineWidth(2)
                    gfx.drawRect(fx, fy, fw, fh)
                    gfx.setLineWidth(1)
                    break
                end
            end
        end
    end
    
    -- 6. 繪製機甲狀態
    gfx.drawText("MECH STATS:", detail_x, detail_y)
    local stats = _G.GameState and _G.GameState.mech_stats or { total_hp = 0, total_weight = 0 }
    gfx.drawText("HP: " .. stats.total_hp, detail_x, detail_y + 20)
    gfx.drawText("Weight: " .. stats.total_weight, detail_x, detail_y + 40)
    
    -- 7. 繪製 READY 選項（置中在組裝格下方）
    local ready_y = GRID_START_Y + GRID_ROWS * GRID_CELL_SIZE + 30
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
        back_text = blink_on and "> " .. back_text .. " <" or "    " .. back_text .. "    "
    end
    local back_text_width = gfx.getTextSize(back_text)
    local back_x = GRID_START_X + (GRID_COLS * GRID_CELL_SIZE - back_text_width) / 2
    gfx.drawText(back_text, back_x, back_y)
    
    -- 如果顯示 READY 選單（以彈出視窗方式顯示，蓋住下方文字）
    if show_ready_menu then
        local dialog_w = 200
        local dialog_h = 60
        local dialog_x = GRID_START_X + (GRID_COLS * GRID_CELL_SIZE - dialog_w) / 2
        local dialog_y = ready_y - 10

        -- 覆蓋背景並繪製對話框框體
        gfx.setColor(gfx.kColorWhite)
        gfx.fillRect(dialog_x, dialog_y, dialog_w, dialog_h)
        gfx.setColor(gfx.kColorBlack)
        gfx.drawRect(dialog_x, dialog_y, dialog_w, dialog_h)

        local options = {"Start Mission", "Back to equip"}
        for i = 1, 2 do
            local text = options[i]
            if i == menu_option_index then
                if blink_on then
                    text = "> " .. text .. " <"
                else
                    text = "  " .. text .. "  "
                end
            else
                text = "  " .. text .. "  "
            end
            local text_width = gfx.getTextSize(text)
            local menu_x = dialog_x + (dialog_w - text_width) / 2
            local menu_y = dialog_y + 15 + (i - 1) * 16
            gfx.drawText(text, menu_x, menu_y)
        end
    end
    
    -- 8. 繪製控制介面 UI（下半部）
    -- 繪製 3x2 控制格子
    local eq = _G.GameState and _G.GameState.mech_stats and _G.GameState.mech_stats.equipped_parts or {}
    
    -- 找出選中格子對應的零件ID（用於高亮所有佔用格子）
    local selected_part_id_for_highlight = nil
    local preview_part_data = nil
    if selected_category and selected_part_index and not cursor_on_ready then
        local parts_list = _G.GameState.parts_by_category[selected_category]
        local part_id = parts_list and parts_list[selected_part_index]
        selected_part_id_for_highlight = part_id
        preview_part_data = _G.PartsData and _G.PartsData[part_id]
    end
    
    for r = 1, UI_GRID_ROWS do
        for c = 1, UI_GRID_COLS do
            local cx = UI_START_X + (c - 1) * UI_CELL_SIZE
            local cy = UI_START_Y + (UI_GRID_ROWS - r) * UI_CELL_SIZE
            
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
                    if mech_controller then
                        mech_controller:drawPartUI(found_part.id, cx, cy, UI_CELL_SIZE)
                    end
                end
                -- 零件佔用的其他格子保持空白（不繪製任何東西）
            else
                -- 沒有零件，繪製空格邊框（不使用 empty.png）
                gfx.setColor(gfx.kColorBlack)
                gfx.setLineWidth(1)
                gfx.drawRect(cx, cy, UI_CELL_SIZE, UI_CELL_SIZE)
            end
        end
    end
    
    -- 繪製選中零件的粗外框（根據零件的 row 顯示在對應的控制介面排）
    if selected_part_id_for_highlight then
        for _, item in ipairs(eq) do
            if item.id == selected_part_id_for_highlight then
                local slot_w = item.w or 1
                local fx = UI_START_X + (item.col - 1) * UI_CELL_SIZE
                -- 根據零件的 row 決定 y 座標：row=2 在上方，row=1 在下方
                local fy = UI_START_Y + (UI_GRID_ROWS - item.row) * UI_CELL_SIZE
                local fw = slot_w * UI_CELL_SIZE
                local fh = UI_CELL_SIZE
                
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
    
    -- 顯示當前選中的零件資訊
--    local info_x = UI_START_X + UI_GRID_COLS * UI_CELL_SIZE + 10
--    if selected_category and selected_part_index and not cursor_on_ready then
--        local parts_list = _G.GameState.parts_by_category[selected_category]
--        local part_id = parts_list and parts_list[selected_part_index]
--        if part_id then
--            gfx.setColor(gfx.kColorBlack)
--            gfx.drawText("Selected: " .. part_id, info_x, UI_START_Y)
--        end
--    else
--        gfx.setColor(gfx.kColorBlack)
--       gfx.drawText("Select category", info_x, UI_START_Y)
--    end
    
    -- 9. 顯示關卡簡介（下半部右側）
    local mission_id = (_G and _G.GameState and _G.GameState.current_mission) or "M001"
    if MissionData and MissionData[mission_id] then
        local mission = MissionData[mission_id]
        local brief_x = UI_START_X + UI_GRID_COLS * UI_CELL_SIZE + 10
        local brief_y = UI_START_Y 
        
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