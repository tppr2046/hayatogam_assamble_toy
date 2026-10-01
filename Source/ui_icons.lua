-- ui_icons.lua
-- [[ 介面：資源圖示 ]] 2026-09-28（使用者拍板）
--
-- 資源在介面上原本寫成 S / C / R 三個字母，玩家要先記住哪個字母是哪種資源。
-- 改成直接畫**掉落物的圖**（1=鐵 2=銅 3=橡膠）——
-- 場上撿到的是什麼樣子，介面上就是什麼樣子，不必再翻譯一次。
--
-- ★ 2026-09-28 使用者改圖：介面用的是**專屬的 `drop_ui-table-10-10`**，不是場上的
--   `drop-table-8-8`。場上那張是 8×8、放大 2 倍會比文字大一圈；介面這張直接照文字的
--   尺寸畫（10×10、線條也加粗），兩者用途不同就分兩張，不要硬套同一張。
--
-- ★★ 這個檔案是資源圖示的**唯一來源**：商店的購買／修理、HQ 的任務報酬都讀這裡。
--    每個畫面各自載一次圖、各自算一次寬度的話，圖示大小與間距一定會慢慢走鐘
--    （HANDOFF §3-5）。
-- ★ 圖只放大**整數倍**：1-bit 的點陣圖非整數縮放會糊掉（§3-4）。
--   倍率由「目前字體的高度」決定 → 圖示自動跟文字差不多大，換字體也不用回來改。

local UIIcons = {}

local gfx = playdate.graphics

-- 格號＝ drop_ui-table-10-10 的順序（與場上掉落物的 DROP_KINDS 一致）
local KIND_INDEX = { steel = 1, copper = 2, rubber = 3 }

local ICON_SRC = 10     -- 原圖邊長（介面專用圖）
-- ★ 2026-09-28：字形底部留了 1px 空白 → 純粹置中會讓圖示看起來比文字低 1px。
--   統一在這裡往上抬，呼叫端不必各自補（不然會有人補、有人忘）。
local ICON_LIFT = 1
local TEXT_GAP = 2      -- 圖示與數字之間
local LABEL_GAP = 1     -- 名稱與圖示之間（"STEEL▣ 12" 的那個貼合感）

-- 圖表只載一次；載不到就回 nil，呼叫端會退回純文字
function UIIcons.sheet()
    if not UIIcons._tried then
        UIIcons._tried = true
        local ok, tbl = pcall(function() return gfx.imagetable.new("images/drop_ui") end)
        if ok and tbl then
            UIIcons._sheet = tbl
        else
            print("WARN: ui_icons failed to load images/drop_ui")
        end
    end
    return UIIcons._sheet
end

-- 回傳：放大倍率, 文字高度, 圖示邊長
-- ★ 介面圖本來就是照文字尺寸畫的 → 目前字體（高 16）算出來是 1 倍，原寸畫。
--   只有換成更大的字體時才會放到 2 倍，而且一定是整數倍（非整數會糊掉 §3-4）。
function UIIcons.metrics()
    local _, th = gfx.getTextSize("0")
    th = th or 14
    local s = math.floor(th / ICON_SRC)
    if s < 1 then s = 1 end
    return s, th, ICON_SRC * s
end

-- 單項寬度（label + 圖示 + 空格 + 數字）
function UIIcons.itemWidth(item)
    local _, _, isz = UIIcons.metrics()
    local w = 0
    if item.label then w = w + gfx.getTextSize(item.label) + LABEL_GAP end
    w = w + isz + TEXT_GAP + gfx.getTextSize(item.text or "")
    return w
end

-- 一整列的寬度（含前綴與各項之間的間距）
function UIIcons.rowWidth(items, sep, prefix)
    sep = sep or 10
    local w = 0
    if prefix and prefix ~= "" then w = w + gfx.getTextSize(prefix) + sep end
    for i, item in ipairs(items) do
        if i > 1 then w = w + sep end
        w = w + UIIcons.itemWidth(item)
    end
    return w
end

-- 畫一項，回傳寬度。y ＝**文字的**基準 y（圖示會自己對齊文字中線）
function UIIcons.drawItem(item, x, y)
    local sheet = UIIcons.sheet()
    local s, th, isz = UIIcons.metrics()
    local x0 = x
    if item.label then
        gfx.drawText(item.label, x, y)
        x = x + gfx.getTextSize(item.label) + LABEL_GAP
    end
    local img = sheet and sheet:getImage(KIND_INDEX[item.kind] or 1)
    if img then
        local iy = y + math.floor((th - isz) / 2) - ICON_LIFT
        local dx, dy = x, iy
        -- ★ 反白的列（黑底白字，如存檔選擇的選中列）：圖示也要跟著反白，
        --   否則黑線條會整個沉進黑底裡看不見（§3-4）。
        if item.invert then
            local prev = gfx.kDrawModeCopy
            if gfx.getImageDrawMode then
                local okm, m = pcall(function() return gfx.getImageDrawMode() end)
                if okm and m then prev = m end
            end
            gfx.setImageDrawMode(gfx.kDrawModeInverted)
            pcall(function() img:drawScaled(dx, dy, s) end)
            gfx.setImageDrawMode(prev)
        else
            pcall(function() img:drawScaled(dx, dy, s) end)
        end
    else
        -- 後備：沒有圖時退回原本的字母（S/C/R）
        gfx.drawText((item.kind or "?"):sub(1, 1):upper(), x, y)
    end
    x = x + isz + TEXT_GAP
    gfx.drawText(item.text or "", x, y)
    return (x + gfx.getTextSize(item.text or "")) - x0
end

-- 畫一整列（可選前綴文字），回傳寬度
function UIIcons.drawRow(items, x, y, sep, prefix)
    sep = sep or 10
    local x0 = x
    if prefix and prefix ~= "" then
        gfx.drawText(prefix, x, y)
        x = x + gfx.getTextSize(prefix) + sep
    end
    for i, item in ipairs(items) do
        if i > 1 then x = x + sep end
        x = x + UIIcons.drawItem(item, x, y)
    end
    return x - x0
end

-- 三種資源一次做成一列（最常用的形式）。value 為 0 的也會顯示，
-- ★ 要省略哪一項由呼叫端決定 —— 報酬與價格的規則不同，別在這裡猜。
function UIIcons.resourceItems(steel, copper, rubber, labels, invert)
    return {
        { kind = "steel",  text = tostring(steel  or 0), label = labels and "STEEL"  or nil, invert = invert },
        { kind = "copper", text = tostring(copper or 0), label = labels and "COPPER" or nil, invert = invert },
        { kind = "rubber", text = tostring(rubber or 0), label = labels and "RUBBER" or nil, invert = invert },
    }
end

return UIIcons
