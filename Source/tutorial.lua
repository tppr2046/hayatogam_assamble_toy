-- tutorial.lua
-- [[ S10 操作教學 ]] 可疊在任何畫面上的教學覆蓋層（不是獨立狀態）：
-- 讓教學在「實際情境」中出現（組裝介面 / 商店 / 關卡內），玩家看得到自己正在學的畫面。
-- 用法（在各 state 中）：
--   setup : if Tutorial.maybeStart("hq") then ... end          -- 首次才會啟動
--   update: if Tutorial.isActive() then Tutorial.update() return end   -- 教學中吃掉輸入
--   draw  : Tutorial.draw()                                    -- 畫在最上層
-- A：下一句（最後一句＝結束）　B：跳過本段。完成後寫入存檔，不再出現。

local gfx = playdate.graphics

Tutorial = {}

local active = false
local key = nil
local lines = {}
local title = ""
local index = 1

local SCREEN_W, SCREEN_H = 400, 240

-- 該段教學是否還沒看過
function Tutorial.shouldShow(k)
    local t = (_G.GameState and _G.GameState.tutorial) or {}
    return not t[k]
end

local function markDone()
    _G.GameState = _G.GameState or {}
    _G.GameState.tutorial = _G.GameState.tutorial or {}
    if key then _G.GameState.tutorial[key] = true end
    if _G.SaveManager and _G.SaveManager.saveCurrent and _G.GameState.current_save_slot then
        _G.SaveManager.saveCurrent()
    end
end

-- 首次進入某畫面時呼叫；已看過則回傳 false 且不啟動
function Tutorial.maybeStart(k)
    if not Tutorial.shouldShow(k) then return false end
    local data = (_G.TutorialData or {})[k]
    if not data or not data.lines or #data.lines == 0 then return false end
    active = true
    key = k
    lines = data.lines
    title = data.title or "HOW TO PLAY"
    index = 1
    print("LOG: tutorial start -> " .. tostring(k))
    return true
end

function Tutorial.isActive()
    return active
end

function Tutorial.stop()
    active = false
    key = nil
    lines = {}
    index = 1
end

function Tutorial.update()
    if not active then return end
    if playdate.buttonJustPressed(playdate.kButtonB) then
        print("LOG: tutorial skipped -> " .. tostring(key))
        markDone()
        Tutorial.stop()
        return
    end
    if playdate.buttonJustPressed(playdate.kButtonA) then
        if index < #lines then
            index = index + 1
            if _G.SoundManager and _G.SoundManager.playCursorMove then _G.SoundManager.playCursorMove() end
        else
            markDone()
            Tutorial.stop()
            if _G.SoundManager and _G.SoundManager.playSelect then _G.SoundManager.playSelect() end
        end
    end
end

function Tutorial.draw()
    if not active then return end
    local box_x, box_y = 16, 56
    local box_w, box_h = SCREEN_W - 32, 128

    -- 白底 + 3px 粗框（與購買確認框同語言）
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(box_x, box_y, box_w, box_h)
    gfx.setColor(gfx.kColorBlack)
    gfx.setLineWidth(3)
    gfx.drawRect(box_x + 1, box_y + 1, box_w - 2, box_h - 2)
    gfx.setLineWidth(1)

    -- 標題列（黑底白字）
    local tw, th = gfx.getTextSize(title)
    gfx.fillRect(box_x + 4, box_y + 4, tw + 16, th + 6)
    gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
    gfx.drawText(title, box_x + 12, box_y + 7)
    gfx.setImageDrawMode(gfx.kDrawModeCopy)

    -- 內文（自動斷行）
    local text = lines[index] or ""
    pcall(function()
        gfx.drawTextInRect(text, box_x + 12, box_y + 12 + th + 8, box_w - 24, box_h - 60)
    end)

    -- 頁數與操作提示
    gfx.drawText(index .. "/" .. #lines, box_x + box_w - 40, box_y + box_h - 20)
    gfx.drawText("A: next   B: skip", box_x + 12, box_y + box_h - 20)
end

return Tutorial
