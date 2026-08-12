-- state_outro.lua
-- [[ S11 結局過場 ]] 打倒最終 BOSS 後的結局劇情：多頁（每頁一張圖 + 數句文字），
-- 呈現形式與開場過場（state_intro）完全一致：上方靜圖 + 下方打字機文字框。
-- A：加速/下一句/下一頁　B：跳過整段。結束後進入 CREDITS（帶 THE END 標題）。
--
-- 與 state_intro 的差異只有三點：
--   1. 讀 _G.OutroData 而非 _G.IntroData
--   2. 圖片載不到時退回 images/dialog_bg（正式過場圖尚未產出）
--   3. finish() 記錄 game_cleared 並進 StateCredits，而非任務選擇

import "CoreLibs/graphics"

local gfx = playdate.graphics
local font = gfx.font.new('fonts/Assemble') or gfx.font.systemFont

local SCREEN_WIDTH = 400
local SCREEN_HEIGHT = 240

-- [[ 版面 ]] 文字框上緣。以上＝插圖可視區（400 × 163），以下＝滿版白底文字框。
-- 三處必須一致：state_intro / state_outro / state_mission 的對話框。
local DIALOG_Y = 163

local FALLBACK_IMAGE = "images/dialog_bg"   -- 正式過場圖未就位時的暫代

StateOutro = {}

local pages = {}
local page_index = 1
local line_index = 1
local typewriter_progress = 0
local typewriter_speed = 30      -- 字/秒（與開場、任務對話一致）
local page_image = nil

local function tryLoad(path)
    if not path then return nil end
    local ok, img = pcall(function() return gfx.image.new(path) end)
    if ok and img then return img end
    return nil
end

local function loadPageImage()
    local p = pages[page_index]
    page_image = tryLoad(p and p.image) or tryLoad(FALLBACK_IMAGE)
end

local function finish()
    -- 記錄通關（存於 tutorial 表，save_manager 已會持久化，不必改存檔結構）
    _G.GameState = _G.GameState or {}
    _G.GameState.tutorial = _G.GameState.tutorial or {}
    _G.GameState.tutorial.outro_done = true
    _G.GameState.tutorial.game_cleared = true
    if _G.SaveManager and _G.SaveManager.saveCurrent and _G.GameState.current_save_slot then
        _G.SaveManager.saveCurrent()
    end
    print("LOG: outro finished -> credits")
    setState(_G.StateCredits, true)   -- true＝從結局進來，credits 顯示 THE END
end

function StateOutro.setup()
    gfx.setFont(font)
    local data = _G.OutroData or {}
    pages = data.pages or {}
    page_index = 1
    line_index = 1
    typewriter_progress = 0
    loadPageImage()
    if _G.SoundManager and _G.SoundManager.playTitleBGM then
        _G.SoundManager.playTitleBGM()
    end
    if _G.MenuItems and _G.MenuItems.clear then _G.MenuItems.clear() end
    if #pages == 0 then
        print("LOG: outro has no pages, skipping")
        finish()
    end
end

function StateOutro.update()
    local page = pages[page_index]
    if not page then finish() return end
    local lines = page.lines or {}
    local text = lines[line_index] or ""

    typewriter_progress = typewriter_progress + typewriter_speed * (1 / 30)

    -- B：跳過整段結局
    if playdate.buttonJustPressed(playdate.kButtonB) then
        print("LOG: outro skipped")
        finish()
        return
    end

    -- A：先補完本句；已完整則下一句／下一頁／結束
    if playdate.buttonJustPressed(playdate.kButtonA) then
        if typewriter_progress < #text then
            typewriter_progress = #text
        elseif line_index < #lines then
            line_index = line_index + 1
            typewriter_progress = 0
        elseif page_index < #pages then
            page_index = page_index + 1
            line_index = 1
            typewriter_progress = 0
            loadPageImage()
            if _G.SoundManager and _G.SoundManager.playCursorMove then _G.SoundManager.playCursorMove() end
        else
            finish()
        end
    end
end

function StateOutro.draw()
    gfx.clear(gfx.kColorWhite)
    gfx.setColor(gfx.kColorBlack)
    gfx.setFont(font)

    -- 上方靜圖（實際可視區只有上方 136px，以下會被文字框蓋住）
    if page_image then
        pcall(function() page_image:draw(0, 0) end)
    end

    -- 下方文字框（滿版寬度，與開場、任務對話同樣式；版面理由見 state_intro）
    local box_x, box_y, box_w, box_h = 0, DIALOG_Y, SCREEN_WIDTH, SCREEN_HEIGHT - DIALOG_Y
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(box_x, box_y, box_w, box_h)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawRect(box_x, box_y, box_w, box_h)

    local page = pages[page_index]
    local lines = (page and page.lines) or {}
    local text = lines[line_index] or ""
    local shown = string.sub(text, 1, math.min(#text, math.floor(typewriter_progress)))
    pcall(function()
        gfx.drawTextInRect(shown, box_x + 8, box_y + 6, box_w - 16, box_h - 26)
    end)

    -- 頁數與操作提示（框內底部）
    gfx.drawText("A: next   B: skip", box_x + 8, SCREEN_HEIGHT - 20)
    gfx.drawText(page_index .. "/" .. #pages, box_x + box_w - 40, SCREEN_HEIGHT - 20)
end

return StateOutro
