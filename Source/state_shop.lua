-- state_shop.lua - 商店介面

import "CoreLibs/graphics"

local gfx = playdate.graphics
local font = gfx.font.new('fonts/Charlie Ninja') or gfx.font.systemFont

StateShop = {}

local shop_selected_part_index = 1
local cursor_on_back = false
local shop_confirm_mode = false
local shop_confirm_option = 1  -- 1=BUY, 2=CANCEL
local scroll_offset = 0  -- 捲動偏移量
local VISIBLE_ITEMS = 7  -- 畫面可顯示的零件數量

function StateShop.setup()
    gfx.setFont(font)
    shop_selected_part_index = 1
    cursor_on_back = false
    shop_confirm_mode = false
    shop_confirm_option = 1
    scroll_offset = 0
end

function StateShop.update()
    if shop_confirm_mode then
        -- 確認購買模式
        if playdate.buttonJustPressed(playdate.kButtonUp) or playdate.buttonJustPressed(playdate.kButtonDown) then
            shop_confirm_option = (shop_confirm_option == 1) and 2 or 1
        elseif playdate.buttonJustPressed(playdate.kButtonA) then
            if shop_confirm_option == 1 then
                -- 購買零件
                local all_parts = {}
                for pid, pdata in pairs(_G.PartsData or {}) do
                    table.insert(all_parts, pid)
                end
                table.sort(all_parts)
                local part_id = all_parts[shop_selected_part_index]
                local part_data = _G.PartsData[part_id]
                
                -- 檢查是否已擁有
                if not _G.GameState.owned_parts[part_id] then
                    -- 檢查資源是否足夠
                    local resources = _G.GameState.resources
                    local cost_steel = part_data.cost_steel or 0
                    local cost_copper = part_data.cost_copper or 0
                    local cost_rubber = part_data.cost_rubber or 0
                    
                    if resources.steel >= cost_steel and 
                       resources.copper >= cost_copper and 
                       resources.rubber >= cost_rubber then
                        -- 扣除資源
                        resources.steel = resources.steel - cost_steel
                        resources.copper = resources.copper - cost_copper
                        resources.rubber = resources.rubber - cost_rubber
                        -- 添加零件到擁有列表
                        _G.GameState.owned_parts[part_id] = true
                        
                        -- 自動儲存遊戲進度
                        if _G.SaveManager and _G.SaveManager.saveCurrent then
                            _G.SaveManager.saveCurrent()
                            print("LOG: Game progress auto-saved after purchase.")
                        end
                        
                        print("LOG: Purchased part: " .. part_id)
                    else
                        print("LOG: Not enough resources to buy " .. part_id)
                    end
                else
                    print("LOG: Part already owned: " .. part_id)
                end
            end
            shop_confirm_mode = false
        elseif playdate.buttonJustPressed(playdate.kButtonB) then
            shop_confirm_mode = false
        end
    elseif cursor_on_back then
        -- 在 BACK 選項上
        if playdate.buttonJustPressed(playdate.kButtonLeft) then
            -- 返回零件列表
            cursor_on_back = false
        elseif playdate.buttonJustPressed(playdate.kButtonA) then
            -- 返回 HQ 界面
            setState(_G.StateHQ)
        end
    else
        -- 選擇零件
        local all_parts = {}
        for pid, _ in pairs(_G.PartsData or {}) do
            table.insert(all_parts, pid)
        end
        table.sort(all_parts)
        
        if playdate.buttonJustPressed(playdate.kButtonUp) then
            shop_selected_part_index = math.max(1, shop_selected_part_index - 1)
            
            -- 向上捲動：當選擇項目小於捲動偏移時
            if shop_selected_part_index <= scroll_offset then
                scroll_offset = math.max(0, shop_selected_part_index - 1)
            end
        elseif playdate.buttonJustPressed(playdate.kButtonDown) then
            shop_selected_part_index = math.min(#all_parts, shop_selected_part_index + 1)
            
            -- 向下捲動：當選擇項目超出可視範圍時
            if shop_selected_part_index > scroll_offset + VISIBLE_ITEMS then
                scroll_offset = shop_selected_part_index - VISIBLE_ITEMS
            end
        elseif playdate.buttonJustPressed(playdate.kButtonRight) then
            -- 按右鍵移到 BACK
            cursor_on_back = true
        elseif playdate.buttonJustPressed(playdate.kButtonA) then
            -- 進入確認購買模式（只有未擁有的零件才能購買）
            local part_id = all_parts[shop_selected_part_index]
            if not _G.GameState.owned_parts[part_id] then
                shop_confirm_mode = true
                shop_confirm_option = 1
            end
        end
    end
end

function StateShop.draw()
    gfx.clear(gfx.kColorWhite)
    gfx.setColor(gfx.kColorBlack)
    gfx.setFont(font)
    
    -- 繪製標題
    gfx.drawText("SHOP", 10, 10)
    
    -- 繪製 BACK 按鈕（右上角固定）
    local back_text = cursor_on_back and "> BACK <" or "BACK"
    gfx.drawText(back_text, 320, 10)
    
    -- 繪製資源顯示
    local res = _G.GameState.resources
    gfx.drawText("Steel: " .. res.steel, 10, 30)
    gfx.drawText("Copper: " .. res.copper, 130, 30)
    gfx.drawText("Rubber: " .. res.rubber, 260, 30)
    
    -- 繪製零件列表（帶捲動）
    local shop_list_y = 60
    local shop_line_height = 20
    local all_parts = {}
    for pid, _ in pairs(_G.PartsData or {}) do
        table.insert(all_parts, pid)
    end
    table.sort(all_parts)
    
    -- 只繪製可視範圍內的零件
    local start_index = scroll_offset + 1
    local end_index = math.min(#all_parts, scroll_offset + VISIBLE_ITEMS)
    
    for i = start_index, end_index do
        local part_id = all_parts[i]
        local part_data = _G.PartsData[part_id]
        local text = part_id
        local cost_text = string.format("S:%d C:%d R:%d", 
            part_data.cost_steel or 0,
            part_data.cost_copper or 0,
            part_data.cost_rubber or 0)
        
        -- 檢查是否已擁有
        local owned = _G.GameState.owned_parts[part_id]
        if owned then
            text = text .. " [OWNED]"
            cost_text = "OWNED"  -- 已擁有不能購買
        end
        
        -- 顯示選擇標記（只在焦點不在 BACK 時）
        if i == shop_selected_part_index and not cursor_on_back then
            text = "> " .. text
        else
            text = "  " .. text
        end
        
        -- 計算繪製位置（相對於捲動偏移）
        local display_index = i - scroll_offset
        gfx.drawText(text, 10, shop_list_y + (display_index - 1) * shop_line_height)
        gfx.drawText(cost_text, 150, shop_list_y + (display_index - 1) * shop_line_height)
    end
    
    -- 繪製捲動提示（如果清單超出畫面）
    if scroll_offset > 0 then
        gfx.drawText("^ More above", 10, shop_list_y - 15)
    end
    if end_index < #all_parts then
        gfx.drawText("v More below", 10, shop_list_y + VISIBLE_ITEMS * shop_line_height + 5)
    end
    
    -- 繪製確認購買對話框
    if shop_confirm_mode then
        local dialog_x = 100
        local dialog_y = 60
        local dialog_w = 200
        local dialog_h = 80
        
        -- 繪製對話框背景
        gfx.setColor(gfx.kColorWhite)
        gfx.fillRect(dialog_x, dialog_y, dialog_w, dialog_h)
        gfx.setColor(gfx.kColorBlack)
        gfx.drawRect(dialog_x, dialog_y, dialog_w, dialog_h)
        
        local all_parts = {}
        for pid, _ in pairs(_G.PartsData or {}) do
            table.insert(all_parts, pid)
        end
        table.sort(all_parts)
        local part_id = all_parts[shop_selected_part_index]
        gfx.drawText("Buy " .. part_id .. "?", dialog_x + 10, dialog_y + 10)
        
        local buy_text = shop_confirm_option == 1 and "> BUY <" or "  BUY"
        local cancel_text = shop_confirm_option == 2 and "> CANCEL <" or "  CANCEL"
        gfx.drawText(buy_text, dialog_x + 30, dialog_y + 35)
        gfx.drawText(cancel_text, dialog_x + 30, dialog_y + 50)
    end
    
    -- 提示文字
    gfx.drawText("Up/Down: Move  Right: BACK  A: Select", 10, 220)
end

return StateShop
