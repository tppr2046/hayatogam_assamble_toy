-- menu_items.lua
-- [[ S8 暫停 ]] Playdate 系統選單（Menu 鍵）項目的安裝與清除。
-- 用系統選單而非自製暫停畫面：符合平台慣例、按下 Menu 會自動暫停遊戲，
-- 且不佔用遊戲內任何按鍵（方向鍵 / A / B / crank 都已被機體操作用滿）。
-- 音量不在此提供——Playdate 系統本身已有音量控制。
-- 注意：Playdate 系統選單最多 3 個自訂項目。

local MenuItems = {}

-- 清除所有自訂選單項目（切換狀態時呼叫，避免殘留）
function MenuItems.clear()
    local menu = playdate.getSystemMenu()
    if menu and menu.removeAllMenuItems then menu:removeAllMenuItems() end
end

-- 任務中的暫停選單：重試 / 回任務選擇
function MenuItems.installForMission()
    MenuItems.clear()
    local menu = playdate.getSystemMenu()
    if not menu then return end
    menu:addMenuItem("Retry", function()
        print("LOG: menu Retry")
        setState(_G.StateMission)
    end)
    menu:addMenuItem("Mission Select", function()
        print("LOG: menu Mission Select")
        setState(_G.StateMissionSelect)
    end)
end

-- 前端（HQ / 選關）：目前無自訂項目，僅清除任務選單的殘留
function MenuItems.installForFrontend()
    MenuItems.clear()
end

return MenuItems