-- state_save_select.lua - 選擇紀錄檔畫面

import "CoreLibs/graphics"

local gfx = playdate.graphics
local font = gfx.font.new('fonts/Charlie Ninja') or gfx.font.systemFont

StateSaveSelect = {}

local SAVE_SLOTS = 3  -- 三個存檔槽
local selected_slot = 1
local mode = "new_game"  -- "new_game" 或 "continue"
local confirm_mode = false  -- 是否顯示 OVERWRITE 確認對話框
local confirm_choice = 1  -- 1 = OVERWRITE, 2 = CANCEL
local save_info = {}  -- 存檔資訊快取

-- ==========================================
-- 初始化
-- ==========================================
function StateSaveSelect.setup(select_mode)
    gfx.setFont(font)
    mode = select_mode or "new_game"
    confirm_mode = false
    confirm_choice = 1
    
    -- 載入存檔資訊
    local SaveManager = _G.SaveManager
    if SaveManager then
        for i = 1, SAVE_SLOTS do
            save_info[i] = SaveManager.getSaveSlotInfo(i)
        end
    end
    
    -- 設定初始選擇的存檔格
    if mode == "continue" then
        -- CONTINUE 模式：焦點移到上次使用的存檔格
        selected_slot = (_G.GameState and _G.GameState.last_save_slot) or 1
    else
        -- NEW GAME 模式：焦點移到第一個空的存檔格
        selected_slot = 1
        for i = 1, SAVE_SLOTS do
            if not save_info[i].exists then
                selected_slot = i
                break
            end
        end
    end
    
    print("LOG: StateSaveSelect initialized. Mode: " .. mode .. ", Selected slot: " .. selected_slot)
end

-- ==========================================
-- 更新邏輯
-- ==========================================
function StateSaveSelect.update()
    if confirm_mode then
        -- 確認對話框模式
        if playdate.buttonJustPressed(playdate.kButtonLeft) or playdate.buttonJustPressed(playdate.kButtonRight) then
            -- 切換選項（OVERWRITE / CANCEL）
            confirm_choice = (confirm_choice == 1) and 2 or 1
        elseif playdate.buttonJustPressed(playdate.kButtonA) then
            if confirm_choice == 1 then
                -- OVERWRITE：刪除舊存檔，創建新存檔並開始遊戲
                local SaveManager = _G.SaveManager
                if SaveManager then
                    SaveManager.deleteSave(selected_slot)
                    SaveManager.createNewSave(selected_slot)
                    SaveManager.loadSave(selected_slot)
                end
                setState(_G.StateHQ)  -- 進入 HQ
            else
                -- CANCEL：返回存檔選擇
                confirm_mode = false
            end
        elseif playdate.buttonJustPressed(playdate.kButtonB) then
            -- B 鍵也可以取消
            confirm_mode = false
        end
    else
        -- 正常存檔選擇模式
        -- 上下選擇存檔槽
        if playdate.buttonJustPressed(playdate.kButtonUp) then
            selected_slot = selected_slot - 1
            if selected_slot < 1 then
                selected_slot = SAVE_SLOTS
            end
        elseif playdate.buttonJustPressed(playdate.kButtonDown) then
            selected_slot = selected_slot + 1
            if selected_slot > SAVE_SLOTS then
                selected_slot = 1
            end
        elseif playdate.buttonJustPressed(playdate.kButtonA) then
            -- 按 A 確認選擇
            local SaveManager = _G.SaveManager
            local slot_exists = save_info[selected_slot].exists
            
            if mode == "new_game" then
                if slot_exists then
                    -- 存檔格有資料：彈出確認對話框
                    confirm_mode = true
                    confirm_choice = 1
                else
                    -- 空格：直接創建新存檔並開始遊戲
                    if SaveManager then
                        SaveManager.createNewSave(selected_slot)
                        SaveManager.loadSave(selected_slot)
                    end
                    setState(_G.StateHQ)  -- 進入 HQ
                end
            elseif mode == "continue" then
                if slot_exists then
                    -- 讀取存檔並進入 HQ
                    if SaveManager then
                        SaveManager.loadSave(selected_slot)
                    end
                    setState(_G.StateHQ)
                else
                    -- 空格：無法繼續（可選擇是否顯示錯誤訊息或忽略）
                    print("WARNING: Cannot continue from empty save slot!")
                end
            end
        elseif playdate.buttonJustPressed(playdate.kButtonB) then
            -- 返回主選單
            if _G.StateMenu then
                setState(_G.StateMenu)
            end
        end
    end
end

-- ==========================================
-- 繪製
-- ==========================================
function StateSaveSelect.draw()
    gfx.clear(gfx.kColorWhite)
    gfx.setColor(gfx.kColorBlack)
    gfx.setFont(font)
    
    -- 標題
    local title = (mode == "continue") and "SELECT SAVE FILE" or "SELECT SAVE FILE"
    local title_width = gfx.getTextSize(title)
    gfx.drawText(title, (400 - title_width) / 2, 20)
    
    -- 繪製存檔槽
    for i = 1, SAVE_SLOTS do
        local y = 70 + (i - 1) * 40
        local text = "SAVE " .. i
        
        -- 顯示存檔資訊
        local info = ""
        if save_info[i].exists then
            local missions = save_info[i].completed_missions_count or 0
            local parts = save_info[i].owned_parts_count or 0
            info = string.format("Missions:%d Parts:%d", missions, parts)
        else
            info = "Empty"
        end
        
        -- 選中標記
        if i == selected_slot then
            text = "> " .. text .. " <"
        end
        
        gfx.drawText(text, 50, y)
        gfx.drawText(info, 180, y)
        
        -- 顯示資源（如果存檔存在）
        if save_info[i].exists then
            local resources = string.format("S:%d C:%d R:%d", 
                save_info[i].steel or 0, 
                save_info[i].copper or 0, 
                save_info[i].rubber or 0)
            gfx.drawText(resources, 180, y + 12)
        end
    end
    
    -- 提示文字
    if not confirm_mode then
        gfx.drawText("A: Select  B: Back", 10, 220)
    end
    
    -- 確認對話框
    if confirm_mode then
        -- 繪製半透明背景
        gfx.setColor(gfx.kColorBlack)
        gfx.fillRect(50, 90, 300, 80)
        gfx.setColor(gfx.kColorWhite)
        gfx.fillRect(52, 92, 296, 76)
        gfx.setColor(gfx.kColorBlack)
        
        -- 對話框文字
        local msg = "Overwrite existing save?"
        local msg_width = gfx.getTextSize(msg)
        gfx.drawText(msg, (400 - msg_width) / 2, 100)
        
        -- 選項
        local option1 = (confirm_choice == 1) and "> OVERWRITE <" or "OVERWRITE"
        local option2 = (confirm_choice == 2) and "> CANCEL <" or "CANCEL"
        
        gfx.drawText(option1, 100, 130)
        gfx.drawText(option2, 230, 130)
        
        gfx.drawText("Left/Right: Select  A: Confirm", 60, 155)
    end
end

return StateSaveSelect
