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
local VISIBLE_ITEMS = 8  -- 畫面可顯示的零件數量（清單框放得下 8 行）
local res_flash_timer = 0   -- [[ G2b ]] 購買成功後上方資源列閃爍幀數
local buy_error_flash = 0   -- [[ G2b ]] 資源不足按 BUY 的錯誤閃爍幀數

-- [[ G2b ]] 版型（框線由底圖 shop_bg.png 提供，程式只畫內容；座標量自底圖）
local SHOP_LAYOUT = {
    res      = { x = 4,   y = 4,   w = 389, h = 24 },   -- 上橫條：資源列
    list     = { x = 4,   y = 34,  w = 180, h = 194 },  -- 左框：零件清單
    preview  = { x = 192, y = 34,  w = 201, h = 128 },  -- 右上框：圖+名字+部位
    desc     = { x = 192, y = 171, w = 137, h = 57 },   -- 下中框：文字說明
    back     = { x = 335, y = 171, w = 58,  h = 57 },   -- 右下框：BACK 鈕
}
local SHOP_LINE_H = 20
local shop_bg_img = nil  -- images/shop_bg.png，於 setup 載入

-- [[ G2b ]] 反白選取（黑底白字，穩定不閃）— 與 state_hq 的 drawSelectableText 同風格
local function drawInverted(text, x, y, w, selected)
    if selected then
        local _, th = gfx.getTextSize(text)
        gfx.setColor(gfx.kColorBlack)
        gfx.fillRect(x - 3, y - 2, w, th + 4)
        gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
        gfx.drawText(text, x, y)
        gfx.setImageDrawMode(gfx.kDrawModeCopy)
    else
        gfx.setColor(gfx.kColorBlack)
        gfx.drawText(text, x, y)
    end
end

-- [[ G2b ]] 取得排序後的零件 id 清單（多處共用）
local function sortedPartIds()
    local ids = {}
    for pid, _ in pairs(_G.PartsData or {}) do ids[#ids + 1] = pid end
    table.sort(ids)
    return ids
end

-- [[ G2b ]] 檢查各資源是否足夠購買。回傳 steel_ok, copper_ok, rubber_ok, all_ok
local function affordability(part_data)
    local res = (_G.GameState and _G.GameState.resources) or { steel = 0, copper = 0, rubber = 0 }
    local s_ok = res.steel  >= (part_data.cost_steel  or 0)
    local c_ok = res.copper >= (part_data.cost_copper or 0)
    local r_ok = res.rubber >= (part_data.cost_rubber or 0)
    return s_ok, c_ok, r_ok, (s_ok and c_ok and r_ok)
end

function StateShop.setup()
    gfx.setFont(font)
    if not shop_bg_img then
        shop_bg_img = gfx.image.new("images/shop_bg")
    end
    -- 播放標題/一般介面 BGM（循環）
    if _G.SoundManager and _G.SoundManager.playTitleBGM then
        _G.SoundManager.playTitleBGM()
    end
    shop_selected_part_index = 1
    cursor_on_back = false
    shop_confirm_mode = false
    shop_confirm_option = 1
    scroll_offset = 0
    -- [[ S10 ]] 首次進入商店：播放教學
    if _G.Tutorial and _G.Tutorial.maybeStart then
        _G.Tutorial.maybeStart("shop")
    end
end

function StateShop.update()
    -- [[ S10 ]] 教學覆蓋層作用中：吃掉輸入
    if _G.Tutorial and _G.Tutorial.isActive and _G.Tutorial.isActive() then
        _G.Tutorial.update()
        return
    end
    -- [[ G2b ]] 效果計時器每幀遞減
    if res_flash_timer > 0 then res_flash_timer = res_flash_timer - 1 end
    if buy_error_flash > 0 then buy_error_flash = buy_error_flash - 1 end

    if shop_confirm_mode then
        -- 確認購買模式：BUY/CANCEL 用左右鍵切換
        local part_id = sortedPartIds()[shop_selected_part_index]
        local part_data = _G.PartsData[part_id]
        if playdate.buttonJustPressed(playdate.kButtonLeft) or playdate.buttonJustPressed(playdate.kButtonRight) then
            shop_confirm_option = (shop_confirm_option == 1) and 2 or 1
            if _G.SoundManager and _G.SoundManager.playCursorMove then
                _G.SoundManager.playCursorMove()
            end
        elseif playdate.buttonJustPressed(playdate.kButtonA) then
            if shop_confirm_option == 2 then
                -- CANCEL
                shop_confirm_mode = false
                if _G.SoundManager and _G.SoundManager.playCursorMove then
                    _G.SoundManager.playCursorMove()
                end
            else
                -- BUY
                local _, _, _, can_afford = affordability(part_data)
                if _G.GameState.owned_parts[part_id] then
                    shop_confirm_mode = false
                elseif can_afford then
                    local resources = _G.GameState.resources
                    resources.steel  = resources.steel  - (part_data.cost_steel  or 0)
                    resources.copper = resources.copper - (part_data.cost_copper or 0)
                    resources.rubber = resources.rubber - (part_data.cost_rubber or 0)
                    _G.GameState.owned_parts[part_id] = true
                    if _G.SaveManager and _G.SaveManager.saveCurrent then
                        _G.SaveManager.saveCurrent()
                        print("LOG: Game progress auto-saved after purchase.")
                    end
                    print("LOG: Purchased part: " .. part_id)
                    if _G.SoundManager and _G.SoundManager.playSelect then
                        _G.SoundManager.playSelect()
                    end
                    res_flash_timer = 24  -- 資源列先閃爍再顯示新數字
                    shop_confirm_mode = false
                else
                    -- 資源不足：閃爍 + 錯誤音，視窗不關閉
                    print("LOG: Not enough resources to buy " .. part_id)
                    buy_error_flash = 12
                    if _G.SoundManager and _G.SoundManager.playHit then
                        _G.SoundManager.playHit()
                    end
                end
            end
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

-- [[ G2b ]] 在指定矩形內置中繪製零件圖（含 CANON/CLAW 特例），scale 放大倍率（對齊組裝介面 2x）
local function drawPartImage(part_id, part_data, bx, by, bw, bh, scale)
    scale = scale or 1
    if not (part_data and part_data._img) then return end
    local ok, iw, ih = pcall(function() return part_data._img:getSize() end)
    if not (ok and iw and ih) then return end
    local cx = bx + bw / 2
    local cy = by + bh / 2
    local img_x = cx - iw * scale / 2
    local img_y = cy - ih * scale / 2
    if part_data.part_type == "CANON" then
        local ok_b, bw2, bh2 = false, nil, nil
        if part_data._base_img then
            ok_b, bw2, bh2 = pcall(function() return part_data._base_img:getSize() end)
        end
        if ok_b and bw2 and bh2 then
            -- [[ BUGFIX 2026-08-08 ]] 砲座與砲管**左緣對齊、底部對齊**，整組置中於框內。
            -- 與機體上（entity_mech_render 的 drawPart）和 HQ 預覽框的畫法一致。
            -- 舊版是「砲管最左側對齊底座中心點」——那是為 64×8 細長砲管設計的，
            -- 砲管改成 40×16 之後會整根往右偏半個底座，跟裝在機體上的樣子對不起來。
            local uw = math.max(bw2, iw)          -- 整組寬度（砲管 40 > 底座 32）
            local uh = math.max(bh2, ih)
            local ox = cx - uw * scale / 2
            local oy = cy - uh * scale / 2
            pcall(function() part_data._base_img:drawScaled(ox, oy + (uh - bh2) * scale, scale) end)
            local b_off = (part_data.barrel_offset_y or 0) * scale
            pcall(function() part_data._img:drawScaled(ox, oy + (uh - ih) * scale + b_off, scale) end)
        else
            pcall(function() part_data._img:drawScaled(img_x, img_y, scale) end)
        end
    else
        pcall(function() part_data._img:drawScaled(img_x, img_y, scale) end)
        if part_id == "CLAW" then
            if part_data._arm_img   then pcall(function() part_data._arm_img:drawScaled(img_x, img_y, scale) end) end
            if part_data._upper_img then pcall(function() part_data._upper_img:drawScaled(img_x, img_y, scale) end) end
            if part_data._lower_img then pcall(function() part_data._lower_img:drawScaled(img_x, img_y, scale) end) end
        end
    end
end

function StateShop.draw()
    -- 底圖（框線由 shop_bg.png 提供）
    if shop_bg_img then
        shop_bg_img:draw(0, 0)
    else
        gfx.clear(gfx.kColorWhite)
    end
    gfx.setColor(gfx.kColorBlack)
    gfx.setFont(font)

    local L = SHOP_LAYOUT
    local res = (_G.GameState and _G.GameState.resources) or { steel = 0, copper = 0, rubber = 0 }
    local owned_map = (_G.GameState and _G.GameState.owned_parts) or {}
    local all_parts = sortedPartIds()

    -- 上橫條：資源列（框線由底圖提供）。購買後 res_flash_timer 期間閃爍再顯示新數字
    do
        local r = L.res
        local ty = r.y + (r.h - select(2, gfx.getTextSize("0"))) // 2
        local blink_hide = res_flash_timer > 0 and ((res_flash_timer // 4) % 2 == 0)
        if not blink_hide then
            gfx.drawText("STEEL " .. res.steel, r.x + 12, ty)
            gfx.drawText("COPPER " .. res.copper, r.x + 145, ty)
            gfx.drawText("RUBBER " .. res.rubber, r.x + 280, ty)
        end
    end

    -- 左框：零件清單（反白選取）
    local lb = L.list
    local row_y0 = lb.y + 8
    local start_index = scroll_offset + 1
    local end_index = math.min(#all_parts, scroll_offset + VISIBLE_ITEMS)
    for i = start_index, end_index do
        local part_id = all_parts[i]
        local part_data = _G.PartsData[part_id]
        local owned = owned_map[part_id]
        local selected = (i == shop_selected_part_index and not cursor_on_back)
        local display_index = i - scroll_offset
        local item_y = row_y0 + (display_index - 1) * SHOP_LINE_H
        local name_x = lb.x + 8
        -- 花費簡寫（右側）；已擁有顯示 OWNED
        local right_text = owned and "OWNED" or string.format("%d/%d/%d",
            part_data.cost_steel or 0, part_data.cost_copper or 0, part_data.cost_rubber or 0)
        local rtw = gfx.getTextSize(right_text)
        local right_x = lb.x + lb.w - 8 - rtw
        if selected then
            gfx.setColor(gfx.kColorBlack)
            gfx.fillRect(lb.x + 2, item_y - 2, lb.w - 4, SHOP_LINE_H)
            gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
            gfx.drawText(part_id, name_x, item_y)
            gfx.drawText(right_text, right_x, item_y)
            gfx.setImageDrawMode(gfx.kDrawModeCopy)
        else
            gfx.setColor(gfx.kColorBlack)
            gfx.drawText(part_id, name_x, item_y)
            gfx.drawText(right_text, right_x, item_y)
        end
    end
    -- ▲▼ 捲動指示（框右緣內側）
    local arrow_x = lb.x + lb.w - 12
    gfx.setColor(gfx.kColorBlack)
    if scroll_offset > 0 then
        gfx.fillTriangle(arrow_x, lb.y + 6, arrow_x + 8, lb.y + 6, arrow_x + 4, lb.y + 1)
    end
    if end_index < #all_parts then
        local by = lb.y + lb.h - 6
        gfx.fillTriangle(arrow_x, by, arrow_x + 8, by, arrow_x + 4, by + 5)
    end

    -- 右上框：零件圖 + 名字 + 部位；下中框：文字說明
    local pb = L.preview
    local db = L.desc
    if shop_selected_part_index >= 1 and shop_selected_part_index <= #all_parts then
        local part_id = all_parts[shop_selected_part_index]
        local part_data = _G.PartsData[part_id]
        gfx.setColor(gfx.kColorBlack)
        -- 名稱（置中於框頂）
        local ntw = gfx.getTextSize(part_id)
        gfx.drawText(part_id, pb.x + (pb.w - ntw) // 2, pb.y + 6)
        -- 圖（置中於中段；2x 放大對齊組裝介面）
        drawPartImage(part_id, part_data, pb.x, pb.y + 22, pb.w, pb.h - 60, 2)
        -- 部位 TOP/BOTTOM + 花費/OWNED（框底兩行）
        local slot_text = tostring(part_data.placement_row or "-")
        local stw = gfx.getTextSize(slot_text)
        gfx.drawText(slot_text, pb.x + (pb.w - stw) // 2, pb.y + pb.h - 36)
        local owned = owned_map[part_id]
        local bottom_text = owned and "OWNED" or string.format("S:%d  C:%d  R:%d",
            part_data.cost_steel or 0, part_data.cost_copper or 0, part_data.cost_rubber or 0)
        local btw = gfx.getTextSize(bottom_text)
        gfx.drawText(bottom_text, pb.x + (pb.w - btw) // 2, pb.y + pb.h - 18)
        -- 下中框：文字說明（自動換行）
        gfx.drawTextInRect(part_data.description or "", db.x + 6, db.y + 6, db.w - 12, db.h - 12)
    end

    -- 右下框：BACK 鈕（框線由底圖提供；選中＝反白）
    do
        local b = L.back
        local t = "BACK"
        local tw, th = gfx.getTextSize(t)
        local tx = b.x + (b.w - tw) // 2
        local ty = b.y + (b.h - th) // 2
        if cursor_on_back then
            gfx.setColor(gfx.kColorBlack)
            gfx.fillRect(b.x, b.y, b.w, b.h)
            gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
            gfx.drawText(t, tx, ty)
            gfx.setImageDrawMode(gfx.kDrawModeCopy)
        else
            gfx.setColor(gfx.kColorBlack)
            gfx.drawText(t, tx, ty)
        end
    end

    -- 購買確認框（置中覆蓋）
    if shop_confirm_mode then
        local part_id = all_parts[shop_selected_part_index]
        local part_data = _G.PartsData[part_id]
        local s_ok, c_ok, r_ok, can_afford = affordability(part_data)

        local dw, dh = 214, 104
        local dx = (400 - dw) // 2
        local dy = (240 - dh) // 2
        gfx.setColor(gfx.kColorWhite)
        gfx.fillRect(dx, dy, dw, dh)
        -- [[ G2b ]] 3px 粗外框
        gfx.setColor(gfx.kColorBlack)
        gfx.setLineWidth(3)
        gfx.drawRect(dx + 1, dy + 1, dw - 2, dh - 2)
        gfx.setLineWidth(1)

        -- 標題
        local q = "Buy " .. tostring(part_id) .. " ?"
        local qtw = gfx.getTextSize(q)
        gfx.drawText(q, dx + (dw - qtw) // 2, dy + 12)

        -- [[ G2b ]] 中間：扣除的資源；不足者以外框標示
        local segs = {
            { "S:" .. (part_data.cost_steel  or 0), s_ok },
            { "C:" .. (part_data.cost_copper or 0), c_ok },
            { "R:" .. (part_data.cost_rubber or 0), r_ok },
        }
        local gap = 20
        local total, sw = 0, {}
        for i, seg in ipairs(segs) do
            sw[i] = gfx.getTextSize(seg[1])
            total = total + sw[i] + (i > 1 and gap or 0)
        end
        local cy = dy + 44
        local _, sth = gfx.getTextSize("0")
        local xrun = dx + (dw - total) // 2
        for i, seg in ipairs(segs) do
            gfx.setColor(gfx.kColorBlack)
            gfx.drawText(seg[1], xrun, cy)
            if not seg[2] then
                gfx.setLineWidth(1)
                gfx.drawRect(xrun - 3, cy - 2, sw[i] + 6, sth + 4)
            end
            xrun = xrun + sw[i] + gap
        end

        -- [[ G2b ]] BUY / CANCEL（左右切換；BUY 於資源不足時淡色 dither，錯誤時閃爍）
        local opt_y = dy + 74
        local DITHER = { 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55 }
        local function boxOf(text, ox)
            local tw, th = gfx.getTextSize(text)
            return ox - 8, opt_y - 3, tw + 16, th + 6, tw, th
        end
        -- BUY
        do
            local ox = dx + 46
            local bx, by, bw, bh = boxOf("BUY", ox)
            local selected = (shop_confirm_option == 1)
            local flash_on = buy_error_flash > 0 and ((buy_error_flash // 3) % 2 == 0)
            if selected then
                if can_afford then
                    gfx.setColor(gfx.kColorBlack)
                    gfx.fillRect(bx, by, bw, bh)
                    gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
                    gfx.drawText("BUY", ox, opt_y)
                    gfx.setImageDrawMode(gfx.kDrawModeCopy)
                else
                    -- 資源不足：淡色 dither 底 + 黑字
                    gfx.setPattern(DITHER)
                    gfx.fillRect(bx, by, bw, bh)
                    gfx.setColor(gfx.kColorBlack)
                    gfx.drawRect(bx, by, bw, bh)
                    gfx.drawText("BUY", ox, opt_y)
                end
            else
                gfx.setColor(gfx.kColorBlack)
                gfx.drawText("BUY", ox, opt_y)
            end
            -- 錯誤閃爍：外圈粗框閃動
            if flash_on then
                gfx.setColor(gfx.kColorBlack)
                gfx.setLineWidth(2)
                gfx.drawRect(bx - 2, by - 2, bw + 4, bh + 4)
                gfx.setLineWidth(1)
            end
        end
        -- CANCEL
        do
            local ox = dx + 122
            local bx, by, bw, bh = boxOf("CANCEL", ox)
            if shop_confirm_option == 2 then
                gfx.setColor(gfx.kColorBlack)
                gfx.fillRect(bx, by, bw, bh)
                gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
                gfx.drawText("CANCEL", ox, opt_y)
                gfx.setImageDrawMode(gfx.kDrawModeCopy)
            else
                gfx.setColor(gfx.kColorBlack)
                gfx.drawText("CANCEL", ox, opt_y)
            end
        end
    end

    -- [[ S10 ]] 教學覆蓋層（畫在最上層）
    if _G.Tutorial and _G.Tutorial.draw then _G.Tutorial.draw() end
end

return StateShop
