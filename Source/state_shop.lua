-- state_shop.lua — PARTS 介面（2026-08-13 由「商店」改版）
--
-- ★ 這個畫面現在叫 **PARTS**，同時負責 購買 / 修理 / 安裝。
--   進入方式：HQ 主選單的 TOP PARTS 或 BOTTOM PARTS（舊的 SHOP 鈕已移除）。
--   進來時 `_G.GameState.parts_filter_row` 指定要顯示哪一排的零件。
--
-- 操作模型：游標在「左側清單」或「右下三顆按鈕」之間切換
--   清單：上下選零件、**CRANK 捲動**、右鍵跳到按鈕
--   按鈕：上下換鈕、左鍵回清單、A 執行、B 回 HQ
--
-- 版面座標由 tools/scan_hq_bg.py 掃描 shop_bg.png 量得（全部 100% 乾淨矩形）。

import "CoreLibs/graphics"

local gfx = playdate.graphics
local font = gfx.font.new('fonts/Assemble') or gfx.font.systemFont

StateShop = {}

-- ============================================================
-- 版面（量自 shop_bg.png）
-- ============================================================
local SHOP_LAYOUT = {
    res     = { x = 6,   y = 6,   w = 386, h = 21 },   -- 上橫條：資源列
    list    = { x = 6,   y = 36,  w = 121, h = 192 },  -- 左框：零件清單（只放名稱）
    preview = { x = 137, y = 36,  w = 255, h = 117 },  -- 右上框：名稱＋圖＋價格/耐久
    desc    = { x = 137, y = 162, w = 166, h = 66 },   -- 下中框：說明文字
    btn     = {                                        -- 右下三顆按鈕
        { x = 313, y = 162, w = 79, h = 18 },          -- 1: BUY / REPAIR
        { x = 313, y = 186, w = 79, h = 18 },          -- 2: INSTALL
        { x = 313, y = 210, w = 79, h = 18 },          -- 3: BACK
    },
}
local SHOP_LINE_H  = 20
-- 清單框高 192、起點內縮 8 → 放得下 9 行
local VISIBLE_ITEMS = 9
-- CRANK 捲動：轉這麼多度捲一格（與 state_mission_select 的手感一致）
local CRANK_DEG_PER_STEP = 30

local shop_bg_img = nil

-- ============================================================
-- 狀態
-- ============================================================
local sel_index    = 1        -- 清單選取索引
local scroll_offset = 0
local focus        = "list"   -- "list" | "buttons"
local btn_index    = 1        -- 1=BUY/REPAIR 2=INSTALL 3=BACK
local crank_accum  = 0
local res_flash_timer = 0     -- 花費後資源列閃爍
local act_error_flash = 0     -- 資源不足／不可執行的錯誤閃爍

-- ============================================================
-- 輔助
-- ============================================================
-- 零件顯示名稱：讀 parts_data 的 `name`，沒有才退回 id。
-- ★ 舊零件的 id 剛好可讀（GUN/CLAW/FEET），所以 `name` 欄位一直是死的；
--   加入 BACK_GUN / HIGH_GUN 後畫面就出現底線了。與 state_hq 的 partLabel 同一套規則。
local function partLabel(part_id)
    local d = _G.PartsData and _G.PartsData[part_id]
    return (d and d.name) or part_id
end

-- 目前要顯示的零件清單：依 HQ 進來時指定的排別過濾。
-- ★ 顯示「該排全部零件」（含未擁有的）—— 購買與組裝在同一個畫面，只需要一套清單。
local function visibleParts()
    local want = (_G.GameState and _G.GameState.parts_filter_row) or "TOP"
    local out = {}
    for pid, pdata in pairs(_G.PartsData or {}) do
        local row = pdata.placement_row or "BOTH"
        if row == want or row == "BOTH" then
            out[#out + 1] = pid
        end
    end
    table.sort(out)
    return out
end

local function isOwned(part_id)
    return (_G.GameState and _G.GameState.owned_parts and _G.GameState.owned_parts[part_id]) and true or false
end

local function canAffordBuy(part_data)
    local res = (_G.GameState and _G.GameState.resources) or { steel = 0, copper = 0, rubber = 0 }
    return (res.steel  or 0) >= (part_data.cost_steel  or 0)
       and (res.copper or 0) >= (part_data.cost_copper or 0)
       and (res.rubber or 0) >= (part_data.cost_rubber or 0)
end

-- 第 1 顆鈕的文字與可用性（未擁有＝BUY／已擁有且有損耗＝REPAIR／否則無事可做）
local function actionButton(part_id, part_data)
    if not isOwned(part_id) then
        return "BUY", true
    end
    local D = _G.Durability
    if D and D.repairCost and D.repairCost(part_id).total > 0 then
        return "REPAIR", true
    end
    return "BUY", false      -- 已擁有且全滿：顯示 BUY 但不可按
end

local function canInstall(part_id)
    if not isOwned(part_id) then return false end
    local D = _G.Durability
    if D and D.isBroken and D.isBroken(part_id) then return false end
    -- 已裝備的就不必再裝
    local eq = _G.GameState and _G.GameState.mech_stats
               and _G.GameState.mech_stats.equipped_parts or {}
    for _, item in ipairs(eq) do
        if item.id == part_id then return false end
    end
    return true
end

-- ★ 三顆鈕的可用狀態：**繪製端與輸入端共用這一個函式**。
--   不可用的鈕整顆隱藏，所以游標也必須跳過它們，否則會「選著一顆看不見的鈕」。
--   兩邊各寫一份判斷 = 遲早不同步（HANDOFF §3-5）。
local function buttonEnabled(part_id, part_data)
    local _, act_ok = actionButton(part_id, part_data)
    return { act_ok, canInstall(part_id), true }   -- BACK 永遠可用
end

-- 往 dir 方向找下一顆「可用」的鈕；找不到就留在原地
local function nextEnabledBtn(from, dir, en)
    local i = from
    for _ = 1, 3 do
        i = i + dir
        if i < 1 or i > 3 then return nil end
        if en[i] then return i end
    end
    return nil
end

-- [[ G2b ]] 在指定矩形內置中繪製零件圖
local function drawPartImage(part_id, part_data, bx, by, bw, bh, scale)
    scale = scale or 1
    if not (part_data and part_data._img) then return end

    -- ★★ 優先使用 state_hq 於 setup 預先合成的 `_img_scaled`。
    --   那張圖已把「底座+臂+上爪+下爪」(CLAW) 與「底座+上移砲管」(CANON) 組好，
    --   **與關卡內和 HQ 組裝格畫的是同一張** → 三個畫面必然一致。
    --   舊版在這裡把 base/arm/upper/lower 全畫在同一個座標，所以 CLAW 整疊在一起。
    -- ★ 不在這裡重算相對位置：那會變成第三份 CLAW 版面計算（HANDOFF §3-5）。
    if part_data._img_scaled then
        local okc, cw, ch = pcall(function() return part_data._img_scaled:getSize() end)
        if okc and cw and ch then
            local ox = bx + bw / 2 - cw * scale / 2
            local oy = by + bh / 2 - ch * scale / 2
            pcall(function() part_data._img_scaled:drawScaled(ox, oy, scale) end)
            return
        end
    end

    -- fallback：_img_scaled 尚未建立時（理論上不會 —— 只能從 HQ 進來，合成在 StateHQ.setup）
    local ok, iw, ih = pcall(function() return part_data._img:getSize() end)
    if not (ok and iw and ih) then return end
    pcall(function()
        part_data._img:drawScaled(bx + bw / 2 - iw * scale / 2, by + bh / 2 - ih * scale / 2, scale)
    end)
end

-- ============================================================
-- 狀態機接口
-- ============================================================
function StateShop.setup()
    gfx.setFont(font)
    if not shop_bg_img then
        shop_bg_img = gfx.image.new("images/shop_bg")
    end
    if _G.SoundManager and _G.SoundManager.playTitleBGM then
        _G.SoundManager.playTitleBGM()
    end
    sel_index    = 1
    scroll_offset = 0
    focus        = "list"
    btn_index    = 1
    crank_accum  = 0
    res_flash_timer = 0
    act_error_flash = 0
    if _G.Tutorial and _G.Tutorial.maybeStart then
        _G.Tutorial.maybeStart("shop")
    end
end

-- 讓選取項保持在可視範圍內
local function clampScroll(total)
    if sel_index < 1 then sel_index = 1 end
    if sel_index > total then sel_index = total end
    if sel_index <= scroll_offset then
        scroll_offset = sel_index - 1
    elseif sel_index > scroll_offset + VISIBLE_ITEMS then
        scroll_offset = sel_index - VISIBLE_ITEMS
    end
    if scroll_offset < 0 then scroll_offset = 0 end
    local maxoff = math.max(0, total - VISIBLE_ITEMS)
    if scroll_offset > maxoff then scroll_offset = maxoff end
end

function StateShop.update()
    if _G.Tutorial and _G.Tutorial.isActive and _G.Tutorial.isActive() then
        _G.Tutorial.update()
        return
    end
    if res_flash_timer > 0 then res_flash_timer = res_flash_timer - 1 end
    if act_error_flash > 0 then act_error_flash = act_error_flash - 1 end

    local parts = visibleParts()
    local total = #parts
    if total == 0 then
        if playdate.buttonJustPressed(playdate.kButtonB) then setState(_G.StateHQ) end
        return
    end

    local function cursorMove()
        if _G.SoundManager and _G.SoundManager.playCursorMove then _G.SoundManager.playCursorMove() end
    end

    if focus == "list" then
        -- [[ CRANK 捲動 ]] 轉 CRANK_DEG_PER_STEP 度換一格（與選關畫面同一套手感）
        local dc = playdate.getCrankChange()
        if dc and dc ~= 0 then
            crank_accum = crank_accum + dc
            while crank_accum >= CRANK_DEG_PER_STEP do
                crank_accum = crank_accum - CRANK_DEG_PER_STEP
                if sel_index < total then sel_index = sel_index + 1; cursorMove() end
            end
            while crank_accum <= -CRANK_DEG_PER_STEP do
                crank_accum = crank_accum + CRANK_DEG_PER_STEP
                if sel_index > 1 then sel_index = sel_index - 1; cursorMove() end
            end
        end

        if playdate.buttonJustPressed(playdate.kButtonUp) then
            if sel_index > 1 then sel_index = sel_index - 1; cursorMove() end
        elseif playdate.buttonJustPressed(playdate.kButtonDown) then
            if sel_index < total then sel_index = sel_index + 1; cursorMove() end
        elseif playdate.buttonJustPressed(playdate.kButtonRight)
            or playdate.buttonJustPressed(playdate.kButtonA) then
            -- 進按鈕區時落在**第一顆可用**的鈕（可能 BUY/INSTALL 都被隱藏，只剩 BACK）
            local pid = parts[sel_index]
            local en = buttonEnabled(pid, _G.PartsData[pid])
            local first = (en[1] and 1) or (en[2] and 2) or 3
            focus = "buttons"; btn_index = first; cursorMove()
        elseif playdate.buttonJustPressed(playdate.kButtonB) then
            setState(_G.StateHQ)
        end
        clampScroll(total)
        return
    end

    -- focus == "buttons"
    local part_id   = parts[sel_index]
    local part_data = _G.PartsData[part_id]

    local en = buttonEnabled(part_id, part_data)
    -- 目前停的鈕如果因為狀態改變而被隱藏（例如剛買完 BUY 就消失），立刻移到可用的鈕
    if not en[btn_index] then
        btn_index = (en[1] and 1) or (en[2] and 2) or 3
    end

    if playdate.buttonJustPressed(playdate.kButtonUp) then
        local n = nextEnabledBtn(btn_index, -1, en)
        if n then btn_index = n; cursorMove() end
    elseif playdate.buttonJustPressed(playdate.kButtonDown) then
        local n = nextEnabledBtn(btn_index, 1, en)
        if n then btn_index = n; cursorMove() end
    elseif playdate.buttonJustPressed(playdate.kButtonLeft) then
        focus = "list"; cursorMove()
    elseif playdate.buttonJustPressed(playdate.kButtonB) then
        setState(_G.StateHQ)
    elseif playdate.buttonJustPressed(playdate.kButtonA) then
        if btn_index == 3 then
            -- BACK
            setState(_G.StateHQ)

        elseif btn_index == 2 then
            -- INSTALL：把要裝的零件交給 HQ，HQ 進場時直接進入「選位置」狀態
            if canInstall(part_id) then
                _G.GameState.pending_install = part_id
                if _G.SoundManager and _G.SoundManager.playSelect then _G.SoundManager.playSelect() end
                setState(_G.StateHQ)
            else
                act_error_flash = 12
                if _G.SoundManager and _G.SoundManager.playHit then _G.SoundManager.playHit() end
            end

        else
            -- BUY / REPAIR
            local label, enabled = actionButton(part_id, part_data)
            if not enabled then
                act_error_flash = 12
                if _G.SoundManager and _G.SoundManager.playHit then _G.SoundManager.playHit() end
            elseif label == "BUY" then
                if canAffordBuy(part_data) then
                    local r = _G.GameState.resources
                    r.steel  = r.steel  - (part_data.cost_steel  or 0)
                    r.copper = r.copper - (part_data.cost_copper or 0)
                    r.rubber = r.rubber - (part_data.cost_rubber or 0)
                    _G.GameState.owned_parts[part_id] = true
                    if _G.SaveManager and _G.SaveManager.saveCurrent then _G.SaveManager.saveCurrent() end
                    print("LOG: Purchased part: " .. part_id)
                    if _G.SoundManager and _G.SoundManager.playSelect then _G.SoundManager.playSelect() end
                    res_flash_timer = 24
                else
                    print("LOG: Not enough resources to buy " .. part_id)
                    act_error_flash = 12
                    if _G.SoundManager and _G.SoundManager.playHit then _G.SoundManager.playHit() end
                end
            else
                -- REPAIR：扣款與費用都在 Durability 模組，這裡不重算（公式只有一個家）
                local D = _G.Durability
                if D and D.repair and D.repair(part_id) then
                    if _G.SaveManager and _G.SaveManager.saveCurrent then _G.SaveManager.saveCurrent() end
                    print("LOG: Repaired part: " .. part_id)
                    if _G.SoundManager and _G.SoundManager.playSelect then _G.SoundManager.playSelect() end
                    res_flash_timer = 24
                else
                    print("LOG: Not enough resources to repair " .. part_id)
                    act_error_flash = 12
                    if _G.SoundManager and _G.SoundManager.playHit then _G.SoundManager.playHit() end
                end
            end
        end
    end
end

-- ============================================================
-- 繪製
-- ============================================================
local function drawCentered(text, bx, bw, y)
    local tw = gfx.getTextSize(text)
    gfx.drawText(text, bx + (bw - tw) // 2, y)
end

function StateShop.draw()
    if shop_bg_img then shop_bg_img:draw(0, 0) else gfx.clear(gfx.kColorWhite) end
    gfx.setColor(gfx.kColorBlack)
    gfx.setFont(font)

    local L = SHOP_LAYOUT
    local res = (_G.GameState and _G.GameState.resources) or { steel = 0, copper = 0, rubber = 0 }
    local parts = visibleParts()
    local total = #parts

    -- 上橫條：資源列（花費後閃爍再顯示新數字）
    do
        local r = L.res
        local ty = r.y + (r.h - select(2, gfx.getTextSize("0"))) // 2
        if not (res_flash_timer > 0 and ((res_flash_timer // 4) % 2 == 0)) then
            gfx.drawText("STEEL " .. res.steel,   r.x + 12,  ty)
            gfx.drawText("COPPER " .. res.copper, r.x + 145, ty)
            gfx.drawText("RUBBER " .. res.rubber, r.x + 280, ty)
        end
    end

    -- 左框：零件清單 —— ★ 只顯示名稱（OWNED 與資源數量已依使用者要求移除）
    local lb = L.list
    do
        local y0 = lb.y + 8
        local last = math.min(total, scroll_offset + VISIBLE_ITEMS)
        for i = scroll_offset + 1, last do
            local pid = parts[i]
            local iy = y0 + (i - scroll_offset - 1) * SHOP_LINE_H
            local selected = (i == sel_index)
            if selected then
                gfx.setColor(gfx.kColorBlack)
                gfx.fillRect(lb.x + 2, iy - 2, lb.w - 4, SHOP_LINE_H)
                gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
                gfx.drawText(partLabel(pid), lb.x + 8, iy)
                gfx.setImageDrawMode(gfx.kDrawModeCopy)
            else
                gfx.setColor(gfx.kColorBlack)
                gfx.drawText(partLabel(pid), lb.x + 8, iy)
            end
        end
        -- ▲▼ 捲動指示
        gfx.setColor(gfx.kColorBlack)
        local ax = lb.x + lb.w - 12
        if scroll_offset > 0 then
            gfx.fillTriangle(ax, lb.y + 6, ax + 8, lb.y + 6, ax + 4, lb.y + 1)
        end
        if last < total then
            local by = lb.y + lb.h - 6
            gfx.fillTriangle(ax, by, ax + 8, by, ax + 4, by + 5)
        end
    end

    if total == 0 then return end
    local part_id   = parts[sel_index]
    local part_data = _G.PartsData[part_id]
    local owned     = isOwned(part_id)
    local D         = _G.Durability

    -- 右上框：名稱 ＋ 圖 ＋（未擁有→購買資源／已擁有→耐久度與修理資源）
    local pb = L.preview
    do
        gfx.setColor(gfx.kColorBlack)
        drawCentered(partLabel(part_id), pb.x, pb.w, pb.y + 4)
        drawPartImage(part_id, part_data, pb.x, pb.y + 22, pb.w, 50, 2)

        local line1_y = pb.y + 76
        local line2_y = pb.y + 95
        if not owned then
            -- 購買需求資源
            drawCentered(string.format("S:%d   C:%d   R:%d",
                part_data.cost_steel or 0, part_data.cost_copper or 0, part_data.cost_rubber or 0),
                pb.x, pb.w, line1_y)
        else
            -- 耐久度
            local indestructible = D and D.isIndestructible and D.isIndestructible(part_id)
            if indestructible then
                drawCentered("DURABILITY  ---", pb.x, pb.w, line1_y)
            else
                local dur = (D and D.get and D.get(part_id)) or 100
                drawCentered("DURABILITY  " .. math.floor(dur) .. "%", pb.x, pb.w, line1_y)
                -- 修理需要的資源（滿耐久時不顯示）
                local c = (D and D.repairCost and D.repairCost(part_id)) or nil
                if c and c.total > 0 then
                    drawCentered(string.format("REPAIR  S:%d   C:%d   R:%d", c.steel, c.copper, c.rubber),
                        pb.x, pb.w, line2_y)
                end
            end
        end
    end

    -- 下中框：說明
    do
        local db = L.desc
        gfx.setColor(gfx.kColorBlack)
        gfx.drawTextInRect(part_data.description or "", db.x + 6, db.y + 6, db.w - 12, db.h - 12)
    end

    -- 右下三顆按鈕
    do
        local act_label = actionButton(part_id, part_data)
        local labels  = { act_label, "INSTALL", "BACK" }
        local enabled = buttonEnabled(part_id, part_data)
        for i = 1, 3 do
            -- [[ 2026-08-13 ]] 不可用的按鈕**整顆隱藏**（依使用者要求），不再用 dither 淡化。
            -- ★ 隱藏之後游標不能停在上面，否則會出現「選著一顆看不見的鈕」——
            --   跳過邏輯在 update 的 moveBtn()，兩邊用同一個 enabled 判斷。
            if enabled[i] then
                local b = L.btn[i]
                local selected = (focus == "buttons" and btn_index == i)
                local tw, th = gfx.getTextSize(labels[i])
                local tx = b.x + (b.w - tw) // 2
                local ty = b.y + (b.h - th) // 2
                if selected then
                    gfx.setColor(gfx.kColorBlack)
                    gfx.fillRect(b.x, b.y, b.w, b.h)
                    gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
                    gfx.drawText(labels[i], tx, ty)
                    gfx.setImageDrawMode(gfx.kDrawModeCopy)
                else
                    gfx.setColor(gfx.kColorBlack)
                    gfx.drawText(labels[i], tx, ty)
                end
                if selected and act_error_flash > 0 and ((act_error_flash // 3) % 2 == 0) then
                    gfx.setColor(gfx.kColorBlack)
                    gfx.setLineWidth(2)
                    gfx.drawRect(b.x - 2, b.y - 2, b.w + 4, b.h + 4)
                    gfx.setLineWidth(1)
                end
            end
        end
    end
end

return StateShop