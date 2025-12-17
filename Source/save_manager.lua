-- save_manager.lua - 存檔管理模組

import "CoreLibs/graphics"

local gfx = playdate.graphics

SaveManager = {}

-- 存檔配置
local SAVE_SLOTS = 3
local SAVE_FILE_PREFIX = "save_slot_"
local METADATA_FILE = "save_metadata"

-- ==========================================
-- 初始化存檔系統
-- ==========================================
function SaveManager.init()
    -- 確保全域資料表存在
    _G.GameState = _G.GameState or {}
    
    -- 讀取存檔元資料（上次使用的存檔格子）
    local metadata = playdate.datastore.read(METADATA_FILE)
    if metadata and metadata.last_save_slot then
        _G.GameState.last_save_slot = metadata.last_save_slot
        print("LOG: Last used save slot: " .. metadata.last_save_slot)
    else
        _G.GameState.last_save_slot = 1  -- 預設為第一個格子
    end
end

-- ==========================================
-- 讀取存檔槽位資訊（用於顯示存檔列表）
-- ==========================================
function SaveManager.getSaveSlotInfo(slot_id)
    local filename = SAVE_FILE_PREFIX .. slot_id
    local data = playdate.datastore.read(filename)
    
    if data then
        return {
            exists = true,
            completed_missions_count = (data.completed_missions and #data.completed_missions) or 0,
            owned_parts_count = (data.owned_parts and SaveManager._countTable(data.owned_parts)) or 0,
            steel = data.resources and data.resources.steel or 0,
            copper = data.resources and data.resources.copper or 0,
            rubber = data.resources and data.resources.rubber or 0,
        }
    else
        return {
            exists = false
        }
    end
end

-- ==========================================
-- 建立新存檔（初始化預設資料）
-- ==========================================
function SaveManager.createNewSave(slot_id)
    local save_data = {
        completed_missions = {},  -- 空的已完成任務列表
        owned_parts = {           -- 初始給予的零件
            GUN = true,
            WHEEL1 = true,
        },
        resources = {             -- 初始資源
            steel = 0,
            copper = 0,
            rubber = 0
        },
        -- 初始化機甲格子（3×2）
        mech_grid = {
            cols = 3,
            rows = 2,
            cell_size = 16
        },
        mech_stats = {
            total_hp = 30,
            total_weight = 0,
            equipped_parts = {}
        }
    }
    
    -- 寫入存檔
    local filename = SAVE_FILE_PREFIX .. slot_id
    playdate.datastore.write(save_data, filename)
    
    -- 更新元資料（記錄上次使用的存檔格子）
    SaveManager._updateLastUsedSlot(slot_id)
    
    print("LOG: Created new save in slot " .. slot_id)
    return true
end

-- ==========================================
-- 讀取存檔到全域 GameState
-- ==========================================
function SaveManager.loadSave(slot_id)
    local filename = SAVE_FILE_PREFIX .. slot_id
    local data = playdate.datastore.read(filename)
    
    if data then
        -- 將存檔資料載入到全域 GameState
        _G.GameState = _G.GameState or {}
        _G.GameState.completed_missions = data.completed_missions or {}
        _G.GameState.owned_parts = data.owned_parts or {}
        _G.GameState.resources = data.resources or {steel = 100, copper = 100, rubber = 100}
        _G.GameState.mech_grid = data.mech_grid or {cols = 3, rows = 2, cell_size = 16}
        _G.GameState.mech_stats = data.mech_stats or {total_hp = 100, total_weight = 0, equipped_parts = {}}
        _G.GameState.current_save_slot = slot_id
        
        -- 更新元資料
        SaveManager._updateLastUsedSlot(slot_id)
        
        print("LOG: Loaded save from slot " .. slot_id)
        return true
    else
        print("ERROR: Failed to load save from slot " .. slot_id)
        return false
    end
end

-- ==========================================
-- 儲存當前遊戲狀態
-- ==========================================
function SaveManager.saveCurrent()
    local slot_id = _G.GameState.current_save_slot
    if not slot_id then
        print("ERROR: No save slot selected!")
        return false
    end
    
    local save_data = {
        completed_missions = _G.GameState.completed_missions or {},
        owned_parts = _G.GameState.owned_parts or {},
        resources = _G.GameState.resources or {steel = 100, copper = 100, rubber = 100},
        mech_grid = _G.GameState.mech_grid or {cols = 3, rows = 2, cell_size = 16},
        mech_stats = _G.GameState.mech_stats or {total_hp = 100, total_weight = 0, equipped_parts = {}}
    }
    
    local filename = SAVE_FILE_PREFIX .. slot_id
    playdate.datastore.write(save_data, filename)
    
    print("LOG: Saved current game to slot " .. slot_id)
    return true
end

-- ==========================================
-- 刪除存檔
-- ==========================================
function SaveManager.deleteSave(slot_id)
    local filename = SAVE_FILE_PREFIX .. slot_id
    playdate.datastore.delete(filename)
    print("LOG: Deleted save in slot " .. slot_id)
end

-- ==========================================
-- 私有函式：更新上次使用的存檔格子
-- ==========================================
function SaveManager._updateLastUsedSlot(slot_id)
    local metadata = {
        last_save_slot = slot_id
    }
    playdate.datastore.write(metadata, METADATA_FILE)
    _G.GameState.last_save_slot = slot_id
end

-- ==========================================
-- 私有函式：計算表格中的項目數量
-- ==========================================
function SaveManager._countTable(t)
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    return count
end

return SaveManager
