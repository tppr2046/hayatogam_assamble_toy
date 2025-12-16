-- state_save_select.lua - 選擇紀錄檔畫面

import "CoreLibs/graphics"

local gfx = playdate.graphics
local font = gfx.font.new('fonts/Charlie Ninja') or gfx.font.systemFont

StateSaveSelect = {}

local SAVE_SLOTS = 3  -- 三個存檔槽
local selected_slot = 1
local selected_back = false  -- 是否選中 BACK 選項
local confirm_delete_mode = false  -- 是否顯示刪除確認對話框
local confirm_choice = 1  -- 1 = OK, 2 = CANCEL
local save_info = {}  -- 存檔資訊快取

-- ==========================================
-- 初始化
-- ==========================================
function StateSaveSelect.setup()
    gfx.setFont(font)
    -- 播放標題/一般介面 BGM（循環）
    if _G.SoundManager and _G.SoundManager.playTitleBGM then
        _G.SoundManager.playTitleBGM()
    end
    confirm_delete_mode = false
    confirm_choice = 1
    selected_slot = 1
    selected_back = false
    
    -- 載入存檔資訊
    local SaveManager = _G.SaveManager
    if SaveManager then
        for i = 1, SAVE_SLOTS do
            save_info[i] = SaveManager.getSaveSlotInfo(i)
        end
    end
    
    print("LOG: StateSaveSelect initialized. Selected slot: " .. selected_slot)
end

-- ==========================================
-- 更新邏輯
-- ==========================================
function StateSaveSelect.update()
    if confirm_delete_mode then
        -- 刪除確認對話框模式
        if playdate.buttonJustPressed(playdate.kButtonLeft) or playdate.buttonJustPressed(playdate.kButtonRight) then
            -- 切換選項（OK / CANCEL）
            confirm_choice = (confirm_choice == 1) and 2 or 1
            -- 播放游標移動音效
            if _G.SoundManager and _G.SoundManager.playCursorMove then
                _G.SoundManager.playCursorMove()
            end
        elseif playdate.buttonJustPressed(playdate.kButtonA) then
            -- 播放選擇音效
            if _G.SoundManager and _G.SoundManager.playSelect then
                _G.SoundManager.playSelect()
            end
            if confirm_choice == 1 then
                -- OK：刪除存檔
                local SaveManager = _G.SaveManager
                if SaveManager then
                    SaveManager.deleteSave(selected_slot)
                    -- 重新載入存檔資訊
                    for i = 1, SAVE_SLOTS do
                        save_info[i] = SaveManager.getSaveSlotInfo(i)
                    end
                end
                confirm_delete_mode = false
            else
                -- CANCEL：返回存檔選擇
                confirm_delete_mode = false
            end
        elseif playdate.buttonJustPressed(playdate.kButtonB) then
            -- B 鍵也可以取消
            confirm_delete_mode = false
        end
    else
        -- 正常存檔選擇模式
        -- 上下選擇存檔槽或 BACK
        if playdate.buttonJustPressed(playdate.kButtonUp) then
            if selected_back then
                selected_back = false
                selected_slot = SAVE_SLOTS
            else
                selected_slot = selected_slot - 1
                if selected_slot < 1 then
                    selected_slot = SAVE_SLOTS
                end
            end
            -- 播放游標移動音效
            if _G.SoundManager and _G.SoundManager.playCursorMove then
                _G.SoundManager.playCursorMove()
            end
        elseif playdate.buttonJustPressed(playdate.kButtonDown) then
            if selected_back then
                selected_slot = 1
                selected_back = false
            else
                selected_slot = selected_slot + 1
                if selected_slot > SAVE_SLOTS then
                    selected_back = true
                end
            end
            -- 播放游標移動音效
            if _G.SoundManager and _G.SoundManager.playCursorMove then
                _G.SoundManager.playCursorMove()
            end
        elseif playdate.buttonJustPressed(playdate.kButtonA) then
            -- 播放選擇音效
            if _G.SoundManager and _G.SoundManager.playSelect then
                _G.SoundManager.playSelect()
            end
            
            if selected_back then
                -- 返回主選單
                if _G.StateMenu then
                    setState(_G.StateMenu)
                end
            else
                -- 選擇存檔槽
                local SaveManager = _G.SaveManager
                local slot_exists = save_info[selected_slot].exists
                
                if slot_exists then
                    -- 已有存檔：讀取並進入任務選擇
                    if SaveManager then
                        SaveManager.loadSave(selected_slot)
                    end
                    setState(_G.StateMissionSelect)
                else
                    -- 空存檔：創建新存檔
                    if SaveManager then
                        SaveManager.createNewSave(selected_slot)
                        SaveManager.loadSave(selected_slot)
                    end
                    setState(_G.StateMissionSelect)
                end
            end
        elseif playdate.buttonJustPressed(playdate.kButtonB) then
            if not selected_back then
                -- 在存檔槽上按 B：已有存檔顯示刪除確認
                local slot_exists = save_info[selected_slot].exists
                if slot_exists then
                    confirm_delete_mode = true
                    confirm_choice = 1
                end
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
    local title = "SELECT SAVE FILE"
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
        
        -- 選中時黑底白字（與任務選擇風格一致）
        if i == selected_slot and not selected_back then
            local band_x = 40
            local band_y = y - 6
            local band_w = 320
            local band_h = 34
            gfx.setColor(gfx.kColorBlack)
            gfx.fillRect(band_x, band_y, band_w, band_h)
            gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
        end
        gfx.drawText(text, 50, y)
        gfx.drawText(info, 180, y)
        if save_info[i].exists then
            local resources = string.format("S:%d C:%d R:%d", 
                save_info[i].steel or 0, 
                save_info[i].copper or 0, 
                save_info[i].rubber or 0)
            gfx.drawText(resources, 180, y + 12)
        end
        if i == selected_slot and not selected_back then
            gfx.setImageDrawMode(gfx.kDrawModeCopy)
            gfx.setColor(gfx.kColorBlack)
        end
    end
    
    -- 繪製 BACK 選項（選中時黑底白字）
    local back_y = 70 + SAVE_SLOTS * 40 + 10
    local back_text = "BACK"
    if selected_back then
        local text_w, text_h = gfx.getTextSize(back_text)
        local pad_x, pad_y = 6, 2
        local bx = 50 - pad_x
        local by = back_y - pad_y
        gfx.setColor(gfx.kColorBlack)
        gfx.fillRect(bx, by, text_w + pad_x * 2, text_h + pad_y * 2)
        gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
        gfx.drawText(back_text, 50, back_y)
        gfx.setImageDrawMode(gfx.kDrawModeCopy)
        gfx.setColor(gfx.kColorBlack)
    else
        gfx.drawText(back_text, 50, back_y)
    end
    
    -- 提示文字
    if not confirm_delete_mode then
        gfx.drawText("A: LOAD, B: DELETE", 10, 220)
    end
    
    -- 刪除確認對話框
    if confirm_delete_mode then
        -- 繪製半透明背景
        gfx.setColor(gfx.kColorBlack)
        gfx.fillRect(50, 90, 300, 80)
        gfx.setColor(gfx.kColorWhite)
        gfx.fillRect(52, 92, 296, 76)
        gfx.setColor(gfx.kColorBlack)
        
        -- 對話框文字
        local msg = "Delete this save?"
        local msg_width = gfx.getTextSize(msg)
        gfx.drawText(msg, (400 - msg_width) / 2, 100)
        
        -- 選項（閃爍）
        local option1
        local option2
        if confirm_choice == 1 then
            option1 = blink_on and "> OK <" or "  OK  "
        else
            option1 = "OK"
        end
        if confirm_choice == 2 then
            option2 = blink_on and "> CANCEL <" or "  CANCEL  "
        else
            option2 = "CANCEL"
        end
        
        gfx.drawText(option1, 120, 130)
        gfx.drawText(option2, 230, 130)
        
        gfx.drawText("Left/Right: Select  A: Confirm", 60, 155)
    end
end

return StateSaveSelect