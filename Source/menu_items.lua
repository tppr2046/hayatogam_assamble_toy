-- menu_items.lua
-- [[ S8 暫停 ]] Playdate 系統選單（Menu 鍵）項目的安裝與清除。
-- 用系統選單而非自製暫停畫面：符合平台慣例、按下 Menu 會自動暫停遊戲，
-- 且不佔用遊戲內任何按鍵（方向鍵 / A / B / crank 都已被機體操作用滿）。
-- 音量不在此提供——Playdate 系統本身已有音量控制。
-- 注意：Playdate 系統選單最多 3 個自訂項目。

local MenuItems = {}

-- ⚠️ [[ 暫時：測試用 ]] 2026-08-07 加入的核心切換，**正式版要移除**。
-- 核心的取得時機（幕別解鎖）與更換介面都還沒做（GDD §8.05），
-- 但 CORE1 的 jump_mult = 0 代表預設狀態完全不能跳，沒有東西可以測。
-- 這個選項讓你在 HQ 與關卡中隨時切 CORE1/2/3，驗證 HP、負重上限、跳躍高度。
-- 移除時：刪掉 addCoreSwitcher() 與下方兩處呼叫即可。
local function addCoreSwitcher(menu)
    if not (menu and _G.CoreData and _G.CoreData.order) then return end
    local order = _G.CoreData.order
    menu:addOptionsMenuItem("CORE(test)", order, _G.GameState and _G.GameState.core_id or order[1],
        function(value)
            _G.GameState = _G.GameState or {}
            _G.GameState.core_id = value
            local c = _G.CoreData.get(value)
            print(string.format("LOG: [test] core -> %s  hp=%d cap=%d jump x%.1f",
                                value, c.base_hp, c.weight_cap, c.jump_mult))
            -- HP / 負重上限要立刻反映（recalcMechStats 是 state_hq 掛在 _G 的全域函式）
            if _G.recalcMechStats then _G.recalcMechStats() end
        end)
end

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
    addCoreSwitcher(menu)   -- ⚠️ 暫時：測試用，正式版移除
end

-- 前端（HQ / 選關）：僅清除任務選單的殘留
function MenuItems.installForFrontend()
    MenuItems.clear()
    addCoreSwitcher(playdate.getSystemMenu())   -- ⚠️ 暫時：測試用，正式版移除
end

return MenuItems