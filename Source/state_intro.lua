-- state_intro.lua
-- [[ S9 開場過場 ]] 新遊戲開始的劇情：多頁（每頁一張圖 + 數句文字），
-- 呈現形式與關卡開始前的劇情畫面一致（上方靜圖 + 下方打字機文字框）。
-- A：加速/下一句/下一頁　B：跳過整段。結束後進入任務選擇。

import "CoreLibs/graphics"

local gfx = playdate.graphics
local font = gfx.font.new('fonts/Assemble') or gfx.font.systemFont

local SCREEN_WIDTH = 400
local SCREEN_HEIGHT = 240

StateIntro = {}

local pages = {}
local page_index = 1
local line_index = 1
local typewriter_progress = 0
local typewriter_speed = 30      -- 字/秒（與任務對話一致）
local page_image = nil

local function loadPageImage()
    page_image = nil
    local p = pages[page_index]
    if p and p.image then
        local ok, img = pcall(function() return gfx.image.new(p.image) end)
        if ok and img then page_image = img end
    end
end

local function finish()
    -- 記錄開場已看過（存檔保存；S10 教學亦使用 tutorial 表）
    _G.GameState = _G.GameState or {}
    _G.GameState.tutorial = _G.GameState.tutorial or {}
    _G.GameState.tutorial.intro_done = true
    if _G.SaveManager and _G.SaveManager.saveCurrent and _G.GameState.current_save_slot then
        _G.SaveManager.saveCurrent()
    end
    setState(_G.StateMissionSelect)
end

function StateIntro.setup()
    gfx.setFont(font)
    local data = _G.IntroData or {}
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
        print("LOG: intro has no pages, skipping")
        finish()
    end
end

function StateIntro.update()
    local page = pages[page_index]
    if not page then finish() return end
    local lines = page.lines or {}
    local text = lines[line_index] or ""

    typewriter_progress = typewriter_progress + typewriter_speed * (1 / 30)

    -- B：跳過整段開場
    if playdate.buttonJustPressed(playdate.kButtonB) then
        print("LOG: intro skipped")
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

function StateIntro.draw()
    gfx.clear(gfx.kColorWhite)
    gfx.setColor(gfx.kColorBlack)
    gfx.setFont(font)

    -- 上方靜圖
    if page_image then
        pcall(function() page_image:draw(0, 0) end)
    end

    -- 下方文字框（與任務對話同樣式）
    local box_x, box_y, box_w, box_h = 10, SCREEN_HEIGHT - 104, SCREEN_WIDTH - 20, 80
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(box_x, box_y, box_w, box_h)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawRect(box_x, box_y, box_w, box_h)

    local page = pages[page_index]
    local lines = (page and page.lines) or {}
    local text = lines[line_index] or ""
    local shown = string.sub(text, 1, math.min(#text, math.floor(typewriter_progress)))
    pcall(function()
        gfx.drawTextInRect(shown, box_x + 8, box_y + 6, box_w - 16, box_h - 12)
    end)

    -- 頁數與操作提示
    gfx.drawText(page_index .. "/" .. #pages, box_x + box_w - 34, box_y + box_h + 4)
    gfx.drawText("A: next   B: skip", box_x, box_y + box_h + 4)
end

return StateIntro
