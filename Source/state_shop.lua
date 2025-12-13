-- state_shop.lua - 商店介面

import "CoreLibs/graphics"

local gfx = playdate.graphics
local font = gfx.font.new('fonts/Charlie Ninja') or gfx.font.systemFont

StateShop = {}

local shop_selected_part_index = 1
local cursor_on_back = false
local shop_confirm_mode = false
local shop_confirm_option = 1  -- 1=BUY, 2=CANCEL

function StateShop.setup()
    gfx.setFont(font)
    shop_selected_part_index = 1
    cursor_on_back = false
    shop_confirm_mode = false
    shop_confirm_option = 1
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
        if playdate.buttonJustPressed(playdate.kButtonUp) then
            cursor_on_back = false
            -- 回到零件列表最後一項
            local all_parts = {}
            for pid, _ in pairs(_G.PartsData or {}) do
                table.insert(all_parts, pid)
            end
            table.sort(all_parts)
            shop_selected_part_index = #all_parts
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
        elseif playdate.buttonJustPressed(playdate.kButtonDown) then
            if shop_selected_part_index < #all_parts then
                shop_selected_part_index = shop_selected_part_index + 1
            else
                cursor_on_back = true
            end
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
    
    -- 繪製資源顯示
    local res = _G.GameState.resources
    gfx.drawText("Steel: " .. res.steel, 10, 30)
    gfx.drawText("Copper: " .. res.copper, 10, 45)
    gfx.drawText("Rubber: " .. res.rubber, 10, 60)
    
    -- 繪製零件列表
    local shop_list_y = 85
    local shop_line_height = 20
    local all_parts = {}
    for pid, _ in pairs(_G.PartsData or {}) do
        table.insert(all_parts, pid)
    end
    table.sort(all_parts)
    
    for i, part_id in ipairs(all_parts) do
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
        
        if i == shop_selected_part_index and not cursor_on_back then
            text = "> " .. text
        else
            text = "  " .. text
        end
        
        gfx.drawText(text, 10, shop_list_y + (i - 1) * shop_line_height)
        gfx.drawText(cost_text, 150, shop_list_y + (i - 1) * shop_line_height)
    end
    
    -- 繪製 BACK 選項
    local back_y = shop_list_y + #all_parts * shop_line_height + 10
    local back_text = cursor_on_back and "> BACK <" or "  BACK"
    gfx.drawText(back_text, 10, back_y)
    
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
        
        local part_id = all_parts[shop_selected_part_index]
        gfx.drawText("Buy " .. part_id .. "?", dialog_x + 10, dialog_y + 10)
        
        local buy_text = shop_confirm_option == 1 and "> BUY <" or "  BUY"
        local cancel_text = shop_confirm_option == 2 and "> CANCEL <" or "  CANCEL"
        gfx.drawText(buy_text, dialog_x + 30, dialog_y + 35)
        gfx.drawText(cancel_text, dialog_x + 30, dialog_y + 50)
    end
    
    -- 提示文字
    gfx.drawText("A: Select  B: Cancel", 10, 220)
end

return StateShop
