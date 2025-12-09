-- main.lua (流程不變，確保數據結構)

-- ==========================================
-- 1. 載入核心程式庫 (CoreLibs)
-- ==========================================
import "CoreLibs/graphics"
import "CoreLibs/timer"

-- ==========================================
-- 2. 載入遊戲資料與狀態模組
-- ==========================================
-- 載入資料模組
-- ❗ 假設 module_scene_data 存在
_G.SceneData = import "module_scene_data"

-- 關鍵修正：初始化全域遊戲資料 (確保所有必要的結構存在)
_G.GameState = _G.GameState or {}
_G.GameState.mech_stats = _G.GameState.mech_stats or {
    total_hp = 100,
    total_weight = 0,
    equipped_parts = {}
}
-- ❗ 假設 PartsData 存在
_G.PartsData = _G.PartsData or {}

-- 載入狀態模組 
_G.StateMenu = import "state_menu"
_G.StateHQ = import "state_hq"
_G.StateMission = import "state_mission"

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

function setState(newState)
    
    -- 執行舊狀態的清理工作 (如果有的話)
    if current_state and current_state.tearDown then
        current_state.tearDown()
    end
    
    current_state = newState
    
    -- 執行新狀態的初始化工作
    if current_state and current_state.setup then
        current_state.setup()
    end
end

-- ==========================================
-- 5. 核心函式：初始化 (只執行一次)
-- ==========================================

function playdate.setup()
    playdate.display.setRefreshRate(30)
    
    -- 初始化第一個狀態 (Menu)
    if current_state and current_state.setup then
        current_state.setup()
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
    if playdate.drawFPS then
        playdate.drawFPS(0, 0)
    end
end