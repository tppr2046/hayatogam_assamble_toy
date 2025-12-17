-- state_shop.lua - 商店介面

import "CoreLibs/graphics"

local gfx = playdate.graphics
local font = gfx.font.new('fonts/Assemble') or gfx.font.systemFont

StateShop = {}

local shop_selected_part_index = 1
local cursor_on_back = false
local shop_confirm_mode = false
local shop_confirm_option = 1  -- 1=BUY, 2=CANCEL
local scroll_offset = 0  -- 捲動偏移量
local VISIBLE_ITEMS = 7  -- 畫面可顯示的零件數量

function StateShop.setup()
    gfx.setFont(font)
    -- 播放標題/一般介面 BGM（循環）
    if _G.SoundManager and _G.SoundManager.playTitleBGM then
        _G.SoundManager.playTitleBGM()
    end
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
            
            -- 播放游標移動音效
            if _G.SoundManager and _G.SoundManager.playCursorMove then
                _G.SoundManager.playCursorMove()
            end
        elseif playdate.buttonJustPressed(playdate.kButtonA) then
            -- 播放選擇音效
            if _G.SoundManager and _G.SoundManager.playSelect then
                _G.SoundManager.playSelect()
            end
            
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
            
            -- 播放游標移動音效
            if _G.SoundManager and _G.SoundManager.playCursorMove then
                _G.SoundManager.playCursorMove()
            end
        elseif playdate.buttonJustPressed(playdate.kButtonDown) then
            shop_selected_part_index = math.min(#all_parts, shop_selected_part_index + 1)
            
            -- 向下捲動：當選擇項目超出可視範圍時
            if shop_selected_part_index > scroll_offset + VISIBLE_ITEMS then
                scroll_offset = shop_selected_part_index - VISIBLE_ITEMS
            end
            
            -- 播放游標移動音效
            if _G.SoundManager and _G.SoundManager.playCursorMove then
                _G.SoundManager.playCursorMove()
            end
        elseif playdate.buttonJustPressed(playdate.kButtonRight) then
            -- 按右鍵移到 BACK
            cursor_on_back = true
            
            -- 播放游標移動音效
            if _G.SoundManager and _G.SoundManager.playCursorMove then
                _G.SoundManager.playCursorMove()
            end
        elseif playdate.buttonJustPressed(playdate.kButtonA) then
            -- 播放選擇音效
            if _G.SoundManager and _G.SoundManager.playSelect then
                _G.SoundManager.playSelect()
            end
            
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
    
    -- 計算閃爍狀態
    local blink_on = (math.floor(playdate.getCurrentTimeMilliseconds() / 250) % 2) == 0
    
    -- 繪製標題
    gfx.drawText("SHOP", 10, 10)
    
    -- 繪製 BACK 按鈕（右上角固定）
    local back_text
    if cursor_on_back then
        back_text = blink_on and "> BACK <" or "  BACK  "
    else
        back_text = "BACK"
    end
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
            cost_text = ""  -- 已擁有不能購買
        end
        
        -- 顯示選擇標記（只在焦點不在 BACK 時）
        if i == shop_selected_part_index and not cursor_on_back then
            if blink_on then
                text = "> " .. text
            else
                text = "  " .. text
            end
        else
            text = "  " .. text
        end
        
        -- 計算繪製位置（相對於捲動偏移）
        local display_index = i - scroll_offset
        local item_y = shop_list_y + (display_index - 1) * shop_line_height
        
        gfx.drawText(text, 10, item_y)
    end
    
    -- 繪製捲動提示（如果清單超出畫面）
    if scroll_offset > 0 then
        gfx.drawText("^ More above", 10, shop_list_y - 15)
    end
    if end_index < #all_parts then
        gfx.drawText("v More below", 10, shop_list_y + VISIBLE_ITEMS * shop_line_height + 5)
    end
    
    -- 繪製選中零件的預覽窗口（不在購買對話框時顯示）
    if not shop_confirm_mode and not cursor_on_back then
        local all_parts = {}
        for pid, _ in pairs(_G.PartsData or {}) do
            table.insert(all_parts, pid)
        end
        table.sort(all_parts)
        
        if shop_selected_part_index > 0 and shop_selected_part_index <= #all_parts then
            local part_id = all_parts[shop_selected_part_index]
            local part_data = _G.PartsData[part_id]
            
            if part_data and part_data._img then
                -- 繪製預覽窗口背景
                local preview_x = 240
                local preview_y = 80
                local preview_w = 100
                local preview_h = 100
                
                gfx.setColor(gfx.kColorWhite)
                gfx.fillRect(preview_x, preview_y, preview_w, preview_h)
                gfx.setColor(gfx.kColorBlack)
                gfx.drawRect(preview_x, preview_y, preview_w, preview_h)
                
                -- 繪製零件圖片（原尺寸，居中）
                local ok, img_width, img_height = pcall(function() return part_data._img:getSize() end)
                if ok and img_width and img_height then
                    -- CANON 特殊處理：砲管最左側對齊底座中心點
                    if part_id == "CANON1" or part_id == "CANON2" then
                        if part_data._base_img then
                            local ok_base, base_width, base_height = pcall(function() return part_data._base_img:getSize() end)
                            if ok_base and base_width and base_height then
                                -- 計算底座位置（居中）
                                local base_x = preview_x + (preview_w - base_width) / 2
                                local base_y = preview_y + (preview_h - base_height) / 2
                                -- 計算砲管位置：最左側對齊底座中心點
                                local barrel_x = base_x + base_width / 2  -- 砲管最左側 = 底座中心
                                local barrel_y = preview_y + (preview_h - img_height) / 2
                                -- 先繪製底座
                                pcall(function() part_data._base_img:draw(base_x, base_y) end)
                                -- 再繪製砲管
                                pcall(function() part_data._img:draw(barrel_x, barrel_y) end)
                            else
                                -- 備用：兩者都居中
                                local img_x = preview_x + (preview_w - img_width) / 2
                                local img_y = preview_y + (preview_h - img_height) / 2
                                pcall(function() part_data._img:draw(img_x, img_y) end)
                            end
                        else
                            -- 沒有底座，砲管居中
                            local img_x = preview_x + (preview_w - img_width) / 2
                            local img_y = preview_y + (preview_h - img_height) / 2
                            pcall(function() part_data._img:draw(img_x, img_y) end)
                        end
                    else
                        -- 其他零件：正常居中
                        local img_x = preview_x + (preview_w - img_width) / 2
                        local img_y = preview_y + (preview_h - img_height) / 2
                        pcall(function() part_data._img:draw(img_x, img_y) end)
                    end
                else
                    -- 無法取得大小，不繪製
                end
                
                -- CLAW 特殊處理：繪製額外部件
                if part_id == "CLAW" then
                    local img_x = preview_x + (preview_w - img_width) / 2
                    local img_y = preview_y + (preview_h - img_height) / 2
                    if part_data._arm_img then pcall(function() part_data._arm_img:draw(img_x, img_y) end) end
                    if part_data._upper_img then pcall(function() part_data._upper_img:draw(img_x, img_y) end) end
                    if part_data._lower_img then pcall(function() part_data._lower_img:draw(img_x, img_y) end) end
                end
                
                -- 繪製資源花費（在窗口上方）
                local cost_y = preview_y - 20
                local cost_text = string.format("S:%d C:%d R:%d", 
                    part_data.cost_steel or 0,
                    part_data.cost_copper or 0,
                    part_data.cost_rubber or 0)
                gfx.drawText(cost_text, preview_x, cost_y)
                
                -- 繪製零件名稱
                gfx.drawText(part_id, preview_x + 5, preview_y + preview_h + 5)
            end
        end
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
        
        local buy_text
        local cancel_text
        if shop_confirm_option == 1 then
            buy_text = blink_on and "> BUY <" or "  BUY  "
        else
            buy_text = "  BUY"
        end
        if shop_confirm_option == 2 then
            cancel_text = blink_on and "> CANCEL <" or "  CANCEL  "
        else
            cancel_text = "  CANCEL"
        end
        gfx.drawText(buy_text, dialog_x + 30, dialog_y + 35)
        gfx.drawText(cancel_text, dialog_x + 30, dialog_y + 50)
    end
    
    -- 提示文字
    gfx.drawText("Up/Down: Move  Right: BACK  A: Select", 10, 220)
end

return StateShop
