-- state_mission_select.lua
-- 任務選擇畫面：顯示所有任務列表，選擇任務進入 HQ

import "CoreLibs/graphics"
import "CoreLibs/ui"

local gfx = playdate.graphics
-- 任務資料從 _G.MissionData 獲取（在 main.lua 中載入）

-- 狀態物件
StateMissionSelect = {}
StateMissionSelect.__index = StateMissionSelect

local mission_list = {}  -- 任務列表（排序後的 ID）
local selected_index = 1  -- 當前選擇的任務索引
local scroll_offset = 0   -- 捲動偏移量

local VISIBLE_ROWS = 4    -- 清單一次看得到幾列（與 draw 的版面一致）

-- [[ 2026-08-09 ]] crank 捲動：累積轉動角度，每 CRANK_DEG_PER_STEP 度移動一列。
-- 與上下鍵並存（都走同一個 moveSelection），手上在轉 crank 時不必再去按方向鍵。
local CRANK_DEG_PER_STEP = 30
local crank_accum = 0

-- 依 selected_index 修正捲動位置，讓選中列一定在可視範圍內。
-- 舊版是「選中列固定貼在最上面」，往回選時整個清單會跳；改成只有超出視窗才捲。
local function clampScroll()
    local max_offset = math.max(0, #mission_list - VISIBLE_ROWS)
    if selected_index - 1 < scroll_offset then
        scroll_offset = selected_index - 1
    elseif selected_index > scroll_offset + VISIBLE_ROWS then
        scroll_offset = selected_index - VISIBLE_ROWS
    end
    scroll_offset = math.min(math.max(0, scroll_offset), max_offset)
end

-- 移動選擇（delta = ±1），循環，並播游標音效
local function moveSelection(delta)
    if #mission_list == 0 then return end
    selected_index = selected_index + delta
    if selected_index < 1 then selected_index = #mission_list end
    if selected_index > #mission_list then selected_index = 1 end
    clampScroll()
    if _G.SoundManager and _G.SoundManager.playCursorMove then
        _G.SoundManager.playCursorMove()
    end
end

local FONT_SMALL = nil
local FONT_LARGE = nil
local SCREEN_HEIGHT = 240

-- [[ 底圖 2026-08-11 ]] 暫用 images/save_bg.png（400×240），專屬的 mission_select_bg 尚未製作。
-- ⚠️ 這張是**滿版細點陣場景圖**，不是 hq_bg 那種留白的框線底圖 —— 黑字直接疊上去會消失（HANDOFF §3-4）。
-- 所以未選中的任務列改成**先填白再描框**，其餘文字鋪白底；版面座標一律沒動。
-- 之後畫專屬底圖時請照 ArtAssets §6.5 A 的原則「框內留白」，那時就能把這些白底拿掉。
local select_bg_img = nil

local function drawTextOnWhite(text, x, y, pad)
    pad = pad or 3
    local tw, th = gfx.getTextSize(text)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(x - pad, y - pad, tw + pad * 2, (th or 14) + pad * 2)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawText(text, x, y)
end

function StateMissionSelect:setup()
    print("StateMissionSelect setup called")
    
    -- 載入字體
    FONT_SMALL = gfx.getFont("fonts/Assemble")
    FONT_LARGE = gfx.getFont("fonts/Assemble")
    
    -- 使用全域 MissionData
    local MissionData = _G.MissionData or {}
    
    -- 建立任務列表（只包含可用的任務）
    mission_list = {}
    for id, mission in pairs(MissionData) do
        -- 檢查前置任務條件
        local prerequisite = mission.prerequisite
        local can_show = false
        
        if prerequisite == 0 then
            -- 初始任務，直接顯示
            can_show = true
        elseif prerequisite and type(prerequisite) == "string" then
            -- 需要前置任務完成
            local completed = _G.GameState.completed_missions or {}
            if completed[prerequisite] then
                can_show = true
            end
        end
        
        if can_show then
            table.insert(mission_list, id)
        end
    end
    table.sort(mission_list)
    
    -- [[ 2026-08-09 ]] 焦點預設放在**最新的未完成關卡**，不再一律從第一關開始。
    -- 清單已依 id 排序，所以「第一個未完成的」就是玩家目前的進度點。
    -- 全部打完時停在最後一關（讓玩家看到自己走到哪，而不是被丟回第一關）。
    local completed = (_G.GameState and _G.GameState.completed_missions) or {}
    selected_index = #mission_list > 0 and #mission_list or 1
    for i, id in ipairs(mission_list) do
        if not completed[id] then
            selected_index = i
            break
        end
    end
    scroll_offset = 0
    clampScroll()
    crank_accum = 0

    print("StateMissionSelect setup complete. Available missions: " .. #mission_list
          .. ", focus = " .. tostring(mission_list[selected_index]))
    -- [[ S8 ]] 前端設定選單（Menu 鍵）：BGM / SFX 音量
    if _G.MenuItems and _G.MenuItems.installForFrontend then
        _G.MenuItems.installForFrontend()
    end
    -- 播放標題/一般介面 BGM（循環）
    if _G.SoundManager and _G.SoundManager.playTitleBGM then
        _G.SoundManager.playTitleBGM()
    end
end

function StateMissionSelect:update()
    -- A 鍵：選擇任務，進入 HQ
    if playdate.buttonJustPressed(playdate.kButtonA) then
        -- 播放選擇音效
        if _G.SoundManager and _G.SoundManager.playSelect then
            _G.SoundManager.playSelect()
        end
        
        if #mission_list > 0 then
            local selected_mission_id = mission_list[selected_index]
            print("Selected mission: " .. selected_mission_id)
            
            -- 設定當前任務到全域
            _G.GameState = _G.GameState or {}
            _G.GameState.current_mission = selected_mission_id
            
            -- 進入 HQ 畫面
            setState(_G.StateHQ)
        end
    end
    
    -- [[ S7 ]] B 鍵：回主選單
    if playdate.buttonJustPressed(playdate.kButtonB) then
        if _G.SoundManager and _G.SoundManager.playCursorMove then _G.SoundManager.playCursorMove() end
        setState(_G.StateMenu)
        return
    end

    -- 上下鍵：選擇任務
    if playdate.buttonJustPressed(playdate.kButtonUp) then
        moveSelection(-1)
    end
    if playdate.buttonJustPressed(playdate.kButtonDown) then
        moveSelection(1)
    end

    -- [[ 2026-08-09 ]] crank 捲動：順時針往下、逆時針往上。
    -- 累積角度而非每幀判斷，慢慢轉也不會漏掉；一次轉很快則連續移動多列。
    local cc = (playdate.getCrankChange and playdate.getCrankChange()) or 0
    if cc ~= 0 then
        crank_accum = crank_accum + cc
        while crank_accum >= CRANK_DEG_PER_STEP do
            crank_accum = crank_accum - CRANK_DEG_PER_STEP
            moveSelection(1)
        end
        while crank_accum <= -CRANK_DEG_PER_STEP do
            crank_accum = crank_accum + CRANK_DEG_PER_STEP
            moveSelection(-1)
        end
    end
end

function StateMissionSelect:draw()
    -- [[ 底圖 ]] 有 save_bg 就鋪滿全螢幕，否則退回原本的清空
    if not select_bg_img then
        select_bg_img = gfx.image.new("images/save_bg")
        if not select_bg_img then print("WARNING: failed to load images/save_bg.png") end
    end
    if select_bg_img then
        pcall(function() select_bg_img:draw(0, 0) end)
    else
        gfx.clear()
    end
    gfx.setColor(gfx.kColorBlack)

    -- 繪製標題（[[ S7 ]] 右側顯示總進度）
    gfx.setFont(FONT_LARGE)
    drawTextOnWhite("MISSION SELECT", 10, 10)
    do
        local completed = (_G.GameState and _G.GameState.completed_missions) or {}
        local total, done = 0, 0
        for id, _ in pairs(_G.MissionData or {}) do
            total = total + 1
            if completed[id] then done = done + 1 end
        end
        local ptext = "CLEARED " .. done .. "/" .. total
        local ptw = gfx.getTextSize(ptext)
        drawTextOnWhite(ptext, 390 - ptw, 10)
    end
    
    -- 繪製任務列表
    gfx.setFont(FONT_LARGE)
    local y = 50
    local line_height = 40
    -- 可視列數用共用常數，避免與 clampScroll 的捲動計算各算一次而漂移。
    -- （版面上 (240-50-30)/40 = 4，與 VISIBLE_ROWS 一致；改版面時兩邊一起看。）
    local visible_count = VISIBLE_ROWS

    local MissionData = _G.MissionData or {}
    
    for i = 1, math.min(visible_count, #mission_list) do
        local index = scroll_offset + i
        if index > #mission_list then break end
        
        local mission_id = mission_list[index]
        local mission = MissionData[mission_id]
        
        -- 繪製選擇框。未選中的列**要先填白再描框** ——
        -- 否則列內的黑字會直接疊在 save_bg 的點陣上、完全看不見（HANDOFF §3-4）
        if index == selected_index then
            gfx.setColor(gfx.kColorBlack)
            gfx.fillRect(5, y - 2, 390, line_height)
            gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
        else
            gfx.setColor(gfx.kColorWhite)
            gfx.fillRect(5, y - 2, 390, line_height)
            gfx.setColor(gfx.kColorBlack)
            gfx.drawRect(5, y - 2, 390, line_height)
            gfx.setImageDrawMode(gfx.kDrawModeCopy)
        end
        
        -- 繪製任務名稱
        gfx.drawText(mission.name or mission_id, 10, y)

        -- [[ S7 ]] 已通關標記（右側 CLEAR）
        local completed = (_G.GameState and _G.GameState.completed_missions) or {}
        if completed[mission_id] then
            local ctw = gfx.getTextSize("CLEAR")
            gfx.drawText("CLEAR", 390 - ctw - 8, y)
        end

        -- 繪製任務目標（[[ S7 ]] 含新目標類型；多場景取第一個場景的目標）
        local obj = mission.objective
        if (not obj) and mission.scenes and mission.scenes[1] then obj = mission.scenes[1].objective end
        local LABELS = {
            ELIMINATE_ALL = "Eliminate All", DELIVER_STONE = "Deliver Stone",
            REACH = "Reach the Goal", PROTECT = "Protect the Escort", BOSS_KILL = "Destroy the Boss",
        }
        local objective_text = ""
        if obj then objective_text = LABELS[obj.type] or obj.description or "" end
        -- 多場景關卡標示場景數
        if mission.scenes and #mission.scenes > 1 then
            objective_text = objective_text .. "  (" .. #mission.scenes .. " scenes)"
        end
        gfx.drawText(objective_text, 10, y + 16)
        
        gfx.setImageDrawMode(gfx.kDrawModeCopy)
        y = y + line_height
    end
    
    -- 繪製捲動提示
    if #mission_list > visible_count then
        drawTextOnWhite("^v/crank: " .. (selected_index) .. "/" .. #mission_list, 10, 210)
    end

    -- 繪製控制提示
        -- 顯示上/下捲動提示箭頭
        if scroll_offset > 0 then
            drawTextOnWhite("^", 390, 35)
        end
        local max_offset = math.max(0, #mission_list - visible_count)
        if scroll_offset < max_offset then
            drawTextOnWhite("v", 390, 210)
        end
        drawTextOnWhite("A: SELECT   B: TITLE", 10, 225)
end

function StateMissionSelect:cleanup()
    print("StateMissionSelect cleanup")
end

return StateMissionSelect
