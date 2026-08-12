-- state_core_upgrade.lua
-- [[ CORE ]] 核心升級畫面（GDD §8.05a）。取得新核心是整個進程中最重大的提升——
-- HP 上限、負重上限、跳躍能力三者同時跳一階——所以給它一個專屬畫面，
-- 而不是只在結算畫面閃一行字。
--
-- 流程：結算畫面按 A → 本畫面（顯示前後對照）→ 原本要去的目的地（HQ / 選關 / 結局）。
-- 目的地由結算畫面傳進來，本畫面只負責演出。

import "CoreLibs/graphics"

local gfx = playdate.graphics
local font = gfx.font.new('fonts/Assemble') or gfx.font.systemFont

local SCREEN_WIDTH = 400
local SCREEN_HEIGHT = 240

local CORE_SCALE = 3   -- 核心圖放大倍率（32×16 → 96×48）

StateCoreUpgrade = {}

local new_core = nil
local prev_core = nil
local next_state = nil
local core_imagetable = nil
local blink_tick = 0

function StateCoreUpgrade.setup(new_id, prev_id, dest_state)
    gfx.setFont(font)
    new_core = _G.CoreData and _G.CoreData.get(new_id) or nil
    -- prev_id 可能與 new_id 相同（理論上不會，但別讓畫面壞掉）
    prev_core = (_G.CoreData and prev_id and _G.CoreData.list[prev_id]) or nil
    next_state = dest_state
    blink_tick = 0

    if not core_imagetable then
        local ok, tbl = pcall(function() return gfx.imagetable.new("images/core") end)
        if ok and tbl then core_imagetable = tbl end
    end

    if _G.MenuItems and _G.MenuItems.clear then _G.MenuItems.clear() end
    if _G.SoundManager and _G.SoundManager.playTitleBGM then _G.SoundManager.playTitleBGM() end

    -- 資料異常時不要把玩家卡在這個畫面
    if not new_core then
        print("LOG: core upgrade screen has no core data, skipping")
        StateCoreUpgrade.finish()
    end
end

function StateCoreUpgrade.finish()
    if next_state then
        setState(next_state)
    elseif _G.StateMissionSelect then
        setState(_G.StateMissionSelect)
    end
end

function StateCoreUpgrade.update()
    blink_tick = blink_tick + 1
    if playdate.buttonJustPressed(playdate.kButtonA) or playdate.buttonJustPressed(playdate.kButtonB) then
        if _G.SoundManager and _G.SoundManager.playSelect then _G.SoundManager.playSelect() end
        StateCoreUpgrade.finish()
    end
end

-- 一列「項目 舊值 → 新值」；有變化的列在數值上加粗框強調。
-- 舊值**靠右對齊箭頭**（不是固定起點）——文字寬度差很多（"MEDIUM" 53px vs "16" 20px），
-- 左對齊會讓長的值撞到箭頭。新值靠左，讓三列的新值垂直對齊。
local function drawStatRow(label, old_text, new_text, y, changed)
    local label_x, arrow_x, new_x = 96, 244, 272
    gfx.setColor(gfx.kColorBlack)
    gfx.drawText(label, label_x, y)
    if old_text then
        local ow = gfx.getTextSize(old_text)
        gfx.drawText(old_text, arrow_x - 8 - ow, y)
    end
    gfx.drawText("->", arrow_x, y)
    gfx.drawText(new_text, new_x, y)
    if changed then
        local tw, th = gfx.getTextSize(new_text)
        gfx.drawRect(new_x - 4, y - 3, tw + 8, (th or 14) + 5)
    end
end

function StateCoreUpgrade.draw()
    gfx.clear(gfx.kColorWhite)
    gfx.setColor(gfx.kColorBlack)
    gfx.setFont(font)
    if not new_core then return end

    -- 標題：黑底白字橫幅
    local title = "CORE UPGRADED"
    local tw, th = gfx.getTextSize(title)
    local tx, ty = (SCREEN_WIDTH - tw) / 2, 16
    gfx.fillRect(tx - 10, ty - 4, tw + 20, (th or 14) + 8)
    gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
    gfx.drawText(title, tx, ty)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)

    -- 核心圖：放大置中（圖尺寸自動讀，換圖不必改這裡）
    if core_imagetable then
        local img = core_imagetable:getImage(new_core.frame or 1)
        if img then
            local ok, iw, ih = pcall(function() return img:getSize() end)
            iw = (ok and iw) or 32
            ih = (ok and ih) or 16
            local dw, dh = iw * CORE_SCALE, ih * CORE_SCALE
            pcall(function()
                img:drawScaled((SCREEN_WIDTH - dw) / 2, 52, CORE_SCALE)
            end)
            local _ = dh
        end
    end

    -- 核心名稱
    local nm = new_core.name or new_core.id
    local nw = gfx.getTextSize(nm)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawText(nm, (SCREEN_WIDTH - nw) / 2, 112)

    -- 前後對照：只有變化的項目才加框，讓玩家一眼看到「解鎖了什麼」
    local py = 142
    local ph = prev_core and prev_core.base_hp or nil
    local pc = prev_core and prev_core.weight_cap or nil
    -- 跳躍顯示等級名稱（NONE / MEDIUM / HIGH），不顯示倍率數字——
    -- 玩家不需要知道 ×1.3 是什麼，只需要知道「跳得更高了」。名稱來自 core_data。
    local pj = prev_core and prev_core.jump_label or nil
    local nj = new_core.jump_label or "NONE"
    drawStatRow("HP",     ph and tostring(ph) or nil, tostring(new_core.base_hp),
                py,      ph ~= new_core.base_hp)
    drawStatRow("WEIGHT", pc and tostring(pc) or nil, tostring(new_core.weight_cap),
                py + 18, pc ~= new_core.weight_cap)
    drawStatRow("JUMP",   pj, nj,
                py + 36, pj ~= nj)

    -- 提示（閃爍）
    if (blink_tick // 15) % 2 == 0 then
        local hint = "Press A"
        local hw = gfx.getTextSize(hint)
        gfx.drawText(hint, (SCREEN_WIDTH - hw) / 2, 212)
    end
end

return StateCoreUpgrade
