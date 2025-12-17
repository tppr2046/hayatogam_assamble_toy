-- state_credits.lua - 製作人員名單畫面

import "CoreLibs/graphics"

local gfx = playdate.graphics
local font = gfx.font.new('fonts/Assemble') or gfx.font.systemFont

StateCredits = {}

local items = {
    "GAME DESIGN: YOU",
    "PROGRAMMING: YOU",
    "ART: YOU",
    "MUSIC: YOU",
}
local selected_index = 1 -- 只用於 Back 選項

function StateCredits.setup()
    gfx.setFont(font)
    selected_index = 1
    -- 播放標題/一般介面 BGM（循環）
    if _G.SoundManager and _G.SoundManager.playTitleBGM then
        _G.SoundManager.playTitleBGM()
    end
end

function StateCredits.update()
    -- Back 選項：按 A 返回主選單
    if playdate.buttonJustPressed(playdate.kButtonA) then
        if _G.StateMenu then
            setState(_G.StateMenu)
        end
    end
end

function StateCredits.draw()
    gfx.clear(gfx.kColorWhite)
    gfx.setColor(gfx.kColorBlack)
    gfx.setFont(font)

    local title = "CREDITS"
    local title_w = gfx.getTextSize(title)
    gfx.drawText(title, (400 - title_w) / 2, 20)

    local y = 60
    for i, line in ipairs(items) do
        local w = gfx.getTextSize(line)
        gfx.drawText(line, (400 - w) / 2, y)
        y = y + 18
    end

    local back = "> BACK <"
    local back_w = gfx.getTextSize(back)
    gfx.drawText(back, (400 - back_w) / 2, 200)
    gfx.drawText("Press A to return", 10, 220)
end

return StateCredits
