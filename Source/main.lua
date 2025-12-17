-- main.lua (流程不變，確保數據結構)

-- ==========================================
-- 1. 載入核心程式庫 (CoreLibs)
-- ==========================================
import "CoreLibs/graphics"
import "CoreLibs/timer"

-- ==========================================
-- 2. 載入遊戲資料與狀態模組
-- ==========================================
-- 初始化全域遊戲資料（確保基本結構存在）
_G.GameState = _G.GameState or {}

-- 載入存檔管理模組
local sm = import "save_manager"
_G.SaveManager = sm or {}

-- 載入音效管理模組
local sound = import "sound_manager"
_G.SoundManager = sound or {}

-- 讀取零件資料模組（若不存在則回退為空表）
local pd = import "parts_data"
_G.PartsData = pd or _G.PartsData or {}

-- 載入任務資料並設置為全域
local md = import "mission_data"
_G.MissionData = md or _G.MissionData or {}

-- 載入狀態模組 
_G.StateMenu = import "state_menu"
_G.StateSaveSelect = import "state_save_select"
_G.StateMissionSelect = import "state_mission_select"
_G.StateHQ = import "state_hq"
_G.StateShop = import "state_shop"
_G.StateMission = import "state_mission"
_G.StateResult = import "state_result"
_G.StateCredits = import "state_credits"

-- ==========================================
-- 3. 遊戲狀態機變數
-- ==========================================
-- 修正流程：遊戲從 StateMenu 開始
local current_state = _G.StateMenu

-- ==========================================
-- 4. 狀態機輔助函式 (用於切換狀態)
-- ------------------------------------------
-- ❗ setState 函式是全域的，供其他模組呼叫
-- ------------------------------------------
-- ==========================================

function setState(newState, ...)
    local function nameOf(s)
        if s == _G.StateMenu then return "StateMenu" end
        if s == _G.StateSaveSelect then return "StateSaveSelect" end
        if s == _G.StateMissionSelect then return "StateMissionSelect" end
        if s == _G.StateHQ then return "StateHQ" end
        if s == _G.StateMission then return "StateMission" end
        if s == _G.StateResult then return "StateResult" end
        if s == _G.StateCredits then return "StateCredits" end
        return tostring(s)
    end

    print("LOG: setState requested. From:", nameOf(current_state), "To:", nameOf(newState))

    -- 執行舊狀態的清理工作 (如果有的話)
    if current_state and current_state.tearDown then
        current_state.tearDown()
    end

    current_state = newState

    -- 執行新狀態的初始化工作
    if current_state then
        print("LOG: setState calling setup for:", nameOf(current_state))
        if current_state.setup then
            current_state.setup(...)  -- 傳遞額外參數
            print("LOG: setState setup complete for:", nameOf(current_state))
        else
            print("LOG: new state has no setup() function:", nameOf(current_state))
        end
    else
        print("ERROR: setState received nil newState")
    end
end

-- ==========================================
-- 5. 核心函式：初始化 (只執行一次)
-- ==========================================

function playdate.setup()
    print("LOG: playdate.setup() called")
    playdate.display.setRefreshRate(30)
    
    -- 初始化存檔系統
    if _G.SaveManager and _G.SaveManager.init then
        _G.SaveManager.init()
        print("LOG: SaveManager initialized.")
    end
    
    -- 初始化音效系統
    if _G.SoundManager and _G.SoundManager.init then
        _G.SoundManager.init()
        print("LOG: SoundManager initialized.")
    end
    
    -- 初始化第一個狀態 (Menu)
    if current_state and current_state.setup then
        print("LOG: Calling current_state.setup()")
        current_state.setup()
    else
        print("ERROR: current_state or current_state.setup not found")
    end
    
    print("LOG: Game setup complete. Starting in Menu.")
end

-- ==========================================
-- 6. 核心函式：遊戲循環 (每幀呼叫)
-- ==========================================

function playdate.update()
    
    playdate.timer.updateTimers()
    
    -- 讓目前狀態處理遊戲邏輯
    if current_state and current_state.update then
        current_state.update()
    end
    
    -- 讓目前狀態繪製畫面
    if current_state and current_state.draw then
        current_state.draw()
    end
    
    -- ❗ 繪製 FPS (除錯用)
    -- 修正: 檢查 playdate.drawFPS 是否存在，避免 'nil value' 錯誤。
--    if playdate.drawFPS then
--        playdate.drawFPS(0, 0)
--    end
end