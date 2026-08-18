-- state_result.lua - 關卡結果畫面

import "CoreLibs/graphics"

local gfx = playdate.graphics
local font = gfx.font.new('fonts/Assemble') or gfx.font.systemFont

StateResult = {}

local result_success = false
local result_message = ""
local reward_steel = 0
local reward_copper = 0
local reward_rubber = 0
-- [[ CORE ]] 本次結算若取得新核心：新核心 id 與升級前的核心 id，
-- 傳給 StateCoreUpgrade 做前後對照。
-- ★ 2026-08-11：原本還有一個 reward_core_name 用來畫本畫面的橫幅，
--   橫幅隨「只留一行」移除後就不需要了（名稱在升級畫面自己會查）。
local reward_core_id = nil
local reward_core_prev_id = nil
-- [[ S7 ]] 結算選項：成功＝NEXT/SELECT（有下一關時）；失敗＝RETRY/SELECT
local result_options = {}
local result_option_index = 1
local result_mission_id = nil
-- [[ S11 ]] 本次結算是否為「全破」（→ 接結局過場而非回任務選擇）
local result_is_ending = false

-- [[ 結算演出 2026-08-11 ]] 資源獲得三段式：先顯示**現有**數字 → 閃爍 **+N** → 變成**最終**數字。
-- 與商店購買後的 res_flash_timer 同一套語感（那邊也是閃完才顯示新數字）。
-- ★ 調參都在這三個常數（refresh rate 固定 30fps，單位＝幀）：
local ANIM_HOLD_F  = 18   -- 第 1 段：停在現有數字幾幀（18 ≈ 0.6 秒）
local ANIM_FLASH_F = 36   -- 第 2 段：閃爍 +N 幾幀（36 ≈ 1.2 秒）
local ANIM_BLINK_F = 4    -- 閃爍週期（每幾幀切換一次，與 state_shop 的 `// 4` 一致）
local anim_frames = 0     -- 進入本畫面後經過的幀數
-- 加獎勵**之前**的存量，用來演出「現有 → +N → 最終」
local before_steel, before_copper, before_rubber = 0, 0, 0

-- [[ 底圖 2026-08-11 ]] images/save_bg.png（400×240，**暫代**，專屬的 result_bg 尚未製作）
-- ⚠️ 這張是滿版細點陣場景圖，不是留白的框線底圖 → 黑字疊上去會消失（HANDOFF §3-4）。
-- 本畫面的所有文字都鋪白底處理，版面座標沒動。畫專屬底圖時照 ArtAssets §6.5 A「框內留白」，
-- 那時就能把這些白底拿掉。
local result_bg_img = nil

-- 文字白底（同 state_mission.lua / state_save_select.lua 的 drawTextOnWhite）
local function drawTextOnWhite(text, x, y, pad)
    pad = pad or 3
    local tw, th = gfx.getTextSize(text)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(x - pad, y - pad, tw + pad * 2, (th or 14) + pad * 2)
    gfx.setColor(gfx.kColorBlack)
    gfx.drawText(text, x, y)
end

-- 版面（三欄：標籤靠左、數字靠右對齊、+N 接在後面）
local RES_LABEL_X = 118   -- 標籤左緣
local RES_VALUE_R = 248   -- 數字**右**對齊到這條線
local RES_PLUS_X  = 260   -- "+N" 左緣
local RES_Y0      = 100   -- 第一列 y
local RES_LINE_H  = 22    -- 列距

-- 找出下一個「已解鎖且未完成」的任務（依 id 排序）
local function findNextMission()
    local completed = (_G.GameState and _G.GameState.completed_missions) or {}
    local ids = {}
    for id, _ in pairs(_G.MissionData or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        if not completed[id] then
            local m = _G.MissionData[id]
            local pre = m and m.prerequisite
            local unlocked = (pre == 0) or (type(pre) == "string" and completed[pre])
            if unlocked then return id end
        end
    end
    return nil
end

-- [[ S11 ]] 是否所有關卡都已完成（結局的保險條件：即使沒人標 final 也不會卡住）
local function allMissionsCleared()
    local completed = (_G.GameState and _G.GameState.completed_missions) or {}
    local any = false
    for id, _ in pairs(_G.MissionData or {}) do
        any = true
        if not completed[id] then return false end
    end
    return any
end

function StateResult.setup(success, message, mission_id)
    gfx.setFont(font)
    -- 播放標題/一般介面 BGM（循環）
    if _G.SoundManager and _G.SoundManager.playTitleBGM then
        _G.SoundManager.playTitleBGM()
    end
    result_success = success or false
    result_message = message or ""
    reward_steel = 0
    reward_copper = 0
    reward_rubber = 0
    reward_core_id = nil
    reward_core_prev_id = nil

    -- [[ 結算演出 ]] 先記下加獎勵**之前**的存量（下面就會把獎勵加進去）
    do
        local r = (_G.GameState and _G.GameState.resources) or {}
        before_steel  = r.steel  or 0
        before_copper = r.copper or 0
        before_rubber = r.rubber or 0
    end
    anim_frames = 0

    -- 如果任務成功，檢查任務獎勵
    if result_success and mission_id then
        local MissionData = _G.MissionData or {}
        local mission = MissionData and MissionData[mission_id]
        if mission then
            _G.GameState = _G.GameState or {}
            _G.GameState.completed_missions = _G.GameState.completed_missions or {}

            -- [[ §8.08 ]] 關卡獎勵**只有首次過關才給**（2026-08-12 拍板）。
            -- ★ 必須在下面標記 completed 之**前**判斷，否則永遠讀到 true、等於全部關掉獎勵。
            -- 重打的收入來源是敵人掉落（見 entity_controller 的掉落物），
            -- 這一對規則是配套的：少了掉落，重打不給獎勵會變成死鎖。
            local is_first_clear = not _G.GameState.completed_missions[mission_id]

            if is_first_clear then
                reward_steel = mission.reward_steel or 0
                reward_copper = mission.reward_copper or 0
                reward_rubber = mission.reward_rubber or 0

                -- 添加資源到玩家
                _G.GameState.resources = _G.GameState.resources or {steel = 0, copper = 0, rubber = 0}
                _G.GameState.resources.steel = _G.GameState.resources.steel + reward_steel
                _G.GameState.resources.copper = _G.GameState.resources.copper + reward_copper
                _G.GameState.resources.rubber = _G.GameState.resources.rubber + reward_rubber
            else
                -- 重打：三個 reward_* 維持 0 → 結算畫面的 rows 為空，
                -- 資源區塊整塊不畫（不會出現 "+0"）。
                print("LOG: Mission " .. tostring(mission_id) .. " replayed - no clear reward.")
            end

            -- 標記任務為已完成
            _G.GameState.completed_missions[mission_id] = true

            -- [[ CORE ]] 核心獎勵：關卡 JSON 的 "reward_core": "CORE2"（GDD §8.05a）。
            -- 核心是純階梯升級，取得後直接自動裝上，不需要選擇介面。
            -- 重打舊關卡不會降級（grant 內部只在「比目前高階」時才換上）。
            if mission.reward_core and _G.CoreData and _G.CoreData.grant then
                local before = _G.GameState.core_id     -- 先記下升級前的核心，供對照畫面用
                if _G.CoreData.grant(mission.reward_core) then
                    local c = _G.CoreData.get(mission.reward_core)
                    reward_core_id = mission.reward_core
                    reward_core_prev_id = before
                    print("LOG: CORE granted -> " .. mission.reward_core .. " (" .. c.name .. ")")
                    -- HP 上限與負重上限來自核心，立刻重算
                    if _G.recalcMechStats then _G.recalcMechStats() end
                end
            end

            -- 自動儲存遊戲進度
            if _G.SaveManager and _G.SaveManager.saveCurrent then
                _G.SaveManager.saveCurrent()
                print("LOG: Game progress auto-saved.")
            end
            
            print("LOG: Mission " .. mission_id .. " completed!")
            print("LOG: Obtained resources - Steel:" .. reward_steel .. " Copper:" .. reward_copper .. " Rubber:" .. reward_rubber)
        end
    end

    -- [[ S7 ]] 組出結算選項
    result_mission_id = mission_id or (_G.GameState and _G.GameState.current_mission)
    result_options = {}

    -- [[ S11 ]] 全破判定（此時 completed_missions 已標記完畢，所以判斷的是清完之後的狀態）
    -- 條件一：關卡 JSON 標了 "final": true（最終 BOSS 關用這個）→ 重打也會再播一次結局
    -- 條件二：所有關卡都完成（保險，切片期間沒有任何關標 final 也能看到結局）
    --         ★ 這條只在「尚未通關過」時生效，否則全破後重打任一關都會再跳結局
    local cleared_mission = result_mission_id and (_G.MissionData or {})[result_mission_id]
    local already_cleared = (_G.GameState and _G.GameState.tutorial and _G.GameState.tutorial.game_cleared) or false
    result_is_ending = result_success
        and ((cleared_mission and cleared_mission.final == true)
             or (not already_cleared and allMissionsCleared()))

    if result_is_ending then
        print("LOG: game cleared -> outro")
        result_options[#result_options + 1] = { label = "CONTINUE", ending = true }
        result_option_index = 1
        return
    end

    if result_success then
        local nxt = findNextMission()
        if nxt then result_options[#result_options + 1] = { label = "NEXT", mission = nxt } end
    else
        if result_mission_id then
            result_options[#result_options + 1] = { label = "RETRY", mission = result_mission_id }
        end
    end
    result_options[#result_options + 1] = { label = "MISSION SELECT" }
    result_option_index = 1
end

function StateResult.update()
    anim_frames = anim_frames + 1   -- [[ 結算演出 ]] 資源三段式動畫的計時

    -- [[ S7 ]] 左右選擇、A 確認
    if playdate.buttonJustPressed(playdate.kButtonLeft) or playdate.buttonJustPressed(playdate.kButtonRight) then
        if #result_options > 1 then
            result_option_index = (result_option_index % #result_options) + 1
            if _G.SoundManager and _G.SoundManager.playCursorMove then _G.SoundManager.playCursorMove() end
        end
    elseif playdate.buttonJustPressed(playdate.kButtonA) then
        if _G.SoundManager and _G.SoundManager.playSelect then _G.SoundManager.playSelect() end
        local opt = result_options[result_option_index]
        -- 先算出「原本要去哪」，核心升級畫面只是插在中間的一段演出
        local dest = _G.StateMissionSelect
        if opt and opt.ending then
            dest = _G.StateOutro          -- [[ S11 ]] 全破：進結局過場 → CREDITS
        elseif opt and opt.mission then
            _G.GameState = _G.GameState or {}
            _G.GameState.current_mission = opt.mission
            dest = _G.StateHQ             -- 下一關/重試：先進 HQ 組裝
        end
        -- [[ CORE ]] 本次取得新核心 → 先播升級畫面，看完再前往目的地（GDD §8.05a）
        if reward_core_id and _G.StateCoreUpgrade then
            setState(_G.StateCoreUpgrade, reward_core_id, reward_core_prev_id, dest)
        else
            setState(dest)
        end
    end
end

function StateResult.draw()
    -- [[ 底圖 ]] 有 save_bg 就鋪滿全螢幕，否則退回白底
    if not result_bg_img then
        result_bg_img = gfx.image.new("images/save_bg")
        if not result_bg_img then print("WARNING: failed to load images/save_bg.png") end
    end
    if result_bg_img then
        pcall(function() result_bg_img:draw(0, 0) end)
    else
        gfx.clear(gfx.kColorWhite)
    end
    gfx.setColor(gfx.kColorBlack)
    gfx.setFont(font)

    -- [[ 版面 2026-08-11 ]] 成功時**只留 MISSION COMPLETE 一行**。已移除的兩樣：
    --   1. 原本的第二行訊息（成功時是 "Mission Complete!"，與標題重複）
    --   2. 「CORE UPGRADED」橫幅 —— 核心升級本來就有專屬畫面 state_core_upgrade
    --      （結算後會自動插進去），在這裡再講一次是重複
    -- ★ **失敗時仍保留第二行**：那是「為什麼失敗」（掉下懸崖／時間到／機體損毀／NPC 陣亡），
    --   是玩家唯一的失敗原因回饋，不能一起砍掉。
    local result_text = result_success and "MISSION COMPLETE" or "MISSION FAILED"
    local result_width = gfx.getTextSize(result_text)
    drawTextOnWhite(result_text, (400 - result_width) / 2, 60)

    if (not result_success) and result_message and result_message ~= "" then
        local msg_width = gfx.getTextSize(result_message)
        drawTextOnWhite(result_message, (400 - msg_width) / 2, 90)
    end

    -- [[ 結算演出 ]] 資源三段式：現有數字 → 閃爍 +N → 最終數字
    if result_success then
        local rows = {}
        if reward_steel  > 0 then rows[#rows+1] = { "STEEL",  before_steel,  reward_steel  } end
        if reward_copper > 0 then rows[#rows+1] = { "COPPER", before_copper, reward_copper } end
        if reward_rubber > 0 then rows[#rows+1] = { "RUBBER", before_rubber, reward_rubber } end

        -- 三段：hold → flash → done
        local phase_done  = anim_frames >= (ANIM_HOLD_F + ANIM_FLASH_F)
        local phase_flash = (not phase_done) and anim_frames >= ANIM_HOLD_F
        -- 閃爍：每 ANIM_BLINK_F 幀切換一次（與 state_shop 的資源列同一套）
        local blink_on = ((anim_frames // ANIM_BLINK_F) % 2 == 0)

        -- 整塊鋪白底：比每行各自鋪白底乾淨，數字長度變化時也不會有白框跳動
        if #rows > 0 then
            local _, lh = gfx.getTextSize("0")
            lh = lh or 14
            local pad = 6
            local bx0 = RES_LABEL_X - pad
            local bx1 = RES_PLUS_X + gfx.getTextSize("+000") + pad
            local by0 = RES_Y0 - pad
            local by1 = RES_Y0 + (#rows - 1) * RES_LINE_H + lh + pad
            gfx.setColor(gfx.kColorWhite)
            gfx.fillRect(bx0, by0, bx1 - bx0, by1 - by0)
            gfx.setColor(gfx.kColorBlack)
        end

        for i, r in ipairs(rows) do
            local label, base, gain = r[1], r[2], r[3]
            local y = RES_Y0 + (i - 1) * RES_LINE_H
            gfx.drawText(label, RES_LABEL_X, y)
            -- 數字右對齊：完成後顯示最終值，否則顯示原本的存量
            local value = phase_done and (base + gain) or base
            local vtext = tostring(value)
            gfx.drawText(vtext, RES_VALUE_R - gfx.getTextSize(vtext), y)
            -- +N 只在第 2 段出現並閃爍；第 3 段它已經併進數字裡，所以不再畫
            if phase_flash and blink_on then
                gfx.drawText("+" .. gain, RES_PLUS_X, y)
            end
        end
    end

    -- [[ S7 ]] 結算選項列（NEXT / RETRY / MISSION SELECT）：選中＝黑底白字並閃爍
    local pad_x, pad_y, gap = 12, 6, 14
    local by = 180
    local blink_on = (playdate.getCurrentTimeMilliseconds() // 300) % 2 == 0
    -- 先算總寬以置中
    local total_w, widths = 0, {}
    for i, opt in ipairs(result_options) do
        local tw = gfx.getTextSize(opt.label)
        widths[i] = tw + pad_x * 2
        total_w = total_w + widths[i] + (i > 1 and gap or 0)
    end
    local bx = (400 - total_w) // 2
    local _, th = gfx.getTextSize("A")
    local bh = th + pad_y * 2
    for i, opt in ipairs(result_options) do
        local w = widths[i]
        local selected = (i == result_option_index)
        if selected and blink_on then
            gfx.setColor(gfx.kColorBlack)
            gfx.fillRect(bx, by, w, bh)
            gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
            gfx.drawText(opt.label, bx + pad_x, by + pad_y)
            gfx.setImageDrawMode(gfx.kDrawModeCopy)
        else
            -- 未選中：先填白再描框（黑字直接疊在 save_bg 的點陣上會看不見）
            gfx.setColor(gfx.kColorWhite)
            gfx.fillRect(bx, by, w, bh)
            gfx.setColor(gfx.kColorBlack)
            gfx.drawRect(bx, by, w, bh)
            gfx.drawText(opt.label, bx + pad_x, by + pad_y)
        end
        bx = bx + w + gap
    end
end

return StateResult
