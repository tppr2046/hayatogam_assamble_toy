-- state_save_select.lua - 選擇紀錄檔畫面

import "CoreLibs/graphics"

local gfx = playdate.graphics
local font = gfx.font.new('fonts/Assemble') or gfx.font.systemFont

StateSaveSelect = {}

local SAVE_SLOTS = 3  -- 三個存檔槽
local selected_slot = 1
local selected_back = false  -- 是否選中 BACK 選項
local confirm_delete_mode = false  -- 是否顯示刪除確認對話框
local confirm_choice = 1  -- 1 = OK, 2 = CANCEL
local save_info = {}  -- 存檔資訊快取

-- [[ 底圖 2026-08-11 ]] images/save_bg.png（400×240，暫用）
-- ⚠️ 這張是**滿版細點陣場景圖**，不是 hq_bg 那種留白的框線底圖 —— 黑字直接疊上去會消失（HANDOFF §3-4）。
-- 所以本畫面的所有文字都先鋪白底（白卡片 + 選中反黑），版面本身沒有動。
-- 之後畫專屬底圖時請照 ArtAssets §6.5 A 的原則「框內留白」，那時就能把這些白卡片拿掉。
local save_bg_img = nil

-- 文字白底（同 state_mission.lua 的 drawTextOnWhite，這裡是本檔的局部複本）
local function drawTextOnWhite(text, x, y, pad)
    pad = pad or 3
    local tw, th = gfx.getTextSize(text)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(x - pad, y - pad, tw + pad * 2, (th or 14) + pad * 2)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawText(text, x, y)
end

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
                    -- [[ S9 ]] 新遊戲：先播開場過場，再進任務選擇
                    if _G.StateIntro then
                        setState(_G.StateIntro)
                    else
                        setState(_G.StateMissionSelect)
                    end
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
    -- [[ 底圖 ]] 有 save_bg 就鋪滿全螢幕，否則退回白底
    if not save_bg_img then
        save_bg_img = gfx.image.new("images/save_bg")
        if not save_bg_img then print("WARNING: failed to load images/save_bg.png") end
    end
    if save_bg_img then
        pcall(function() save_bg_img:draw(0, 0) end)
    else
        gfx.clear(gfx.kColorWhite)
    end
    gfx.setColor(gfx.kColorBlack)
    gfx.setFont(font)

    -- 標題
    local title = "SELECT SAVE FILE"
    local title_width = gfx.getTextSize(title)
    drawTextOnWhite(title, (400 - title_width) / 2, 20)

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
        
        -- 選中時黑底白字（與任務選擇風格一致）；未選中時**鋪白底**，
        -- 否則黑字疊在 save_bg 的點陣上會看不見（HANDOFF §3-4）
        local band_x, band_y, band_w, band_h = 40, y - 6, 320, 34
        if i == selected_slot and not selected_back then
            gfx.setColor(gfx.kColorBlack)
            gfx.fillRect(band_x, band_y, band_w, band_h)
            gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
        else
            gfx.setColor(gfx.kColorWhite)
            gfx.fillRect(band_x, band_y, band_w, band_h)
            gfx.setColor(gfx.kColorBlack)
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
        drawTextOnWhite(back_text, 50, back_y)
    end

    -- 提示文字
    if not confirm_delete_mode then
        drawTextOnWhite("A: LOAD, B: DELETE", 10, 220)
    end
    
    -- 刪除確認對話框
    -- [[ 統一風格 ]] 版面/邊框/按鈕與商店的購買確認框一致（state_shop.lua 的 shop_confirm_mode）：
    --   214×104 置中、3px 粗外框、選中項＝黑底白字（非閃爍）。
    if confirm_delete_mode then
        local dw, dh = 214, 104
        local dx = (400 - dw) // 2
        local dy = (240 - dh) // 2
        gfx.setColor(gfx.kColorWhite)
        gfx.fillRect(dx, dy, dw, dh)
        -- 3px 粗外框（同購買確認）
        gfx.setColor(gfx.kColorBlack)
        gfx.setLineWidth(3)
        gfx.drawRect(dx + 1, dy + 1, dw - 2, dh - 2)
        gfx.setLineWidth(1)

        -- 標題
        local q = "Delete this save?"
        local qtw = gfx.getTextSize(q)
        gfx.drawText(q, dx + (dw - qtw) // 2, dy + 12)

        -- 中段：標明是哪一個存檔槽（對應購買確認框的資源列位置）
        local slot_text = "SLOT " .. tostring(selected_slot)
        local stw, sth = gfx.getTextSize(slot_text)
        local scx = dx + (dw - stw) // 2
        local scy = dy + 44
        gfx.drawText(slot_text, scx, scy)
        gfx.setLineWidth(1)
        gfx.drawRect(scx - 3, scy - 2, stw + 6, (sth or 14) + 4)

        -- OK / CANCEL（左右切換；選中＝黑底白字，同購買確認）
        local opt_y = dy + 74
        local function boxOf(text, ox)
            local tw, th = gfx.getTextSize(text)
            return ox - 8, opt_y - 3, tw + 16, (th or 14) + 6
        end
        -- 兩顆按鈕整組置中（OK 與 CANCEL 寬度差很多，寫死座標會歪）
        local ok_w = gfx.getTextSize("OK") + 16
        local cancel_w = gfx.getTextSize("CANCEL") + 16
        local gap = 24
        local run = dx + (dw - (ok_w + gap + cancel_w)) // 2 + 8
        for i, label in ipairs({ "OK", "CANCEL" }) do
            local bx, by, bw, bh = boxOf(label, run)
            if confirm_choice == i then
                gfx.setColor(gfx.kColorBlack)
                gfx.fillRect(bx, by, bw, bh)
                gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
                gfx.drawText(label, run, opt_y)
                gfx.setImageDrawMode(gfx.kDrawModeCopy)
            else
                gfx.setColor(gfx.kColorBlack)
                gfx.drawText(label, run, opt_y)
            end
            run = run + bw + gap
        end
    end
end

return StateSaveSelect