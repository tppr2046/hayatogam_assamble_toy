-- state_menu.lua (最終穩定版 - 使用 字體)

import "CoreLibs/graphics"

local gfx = playdate.graphics

-- 載入 Assemble 字體，如果失敗則使用系統字體
local custom_font = gfx.font.new('fonts/Assemble')
local font = custom_font or gfx.font.systemFont

StateMenu = {}

local menu_options = {"START GAME", "CREDITS"}
local selected_index = 1
local menu_x = 150
local menu_y_start = 170
local line_height = 20
local cover_image = nil
local setup_done = false

-- [[ 標題背景 2026-08-11 ]] 零件隨機組合的 4 排橫向捲動
-- cover.png 已改成**透明底**（只剩標題字，不透明範圍 y=16~142），下層由這裡填。
--
-- ★ 調參都在這一區：
local ROWS          = 4       -- 排數
local ROW_SPEEDS    = { 0.7, -0.5, 0.9, -0.6 }  -- 每排每幀移動的像素（正=向右、負=向左）
                              -- 第 1/3 排向右、第 2/4 排向左（速度不同才不會看起來像同一張圖）
local STRIP_W       = 480     -- 每排「一段」的寬度；比螢幕寬，畫兩段就能無縫循環
local ROW_GAP_MIN   = 20      -- 機體之間的最小間距
local ROW_GAP_MAX   = 64      -- 最大間距（越大越稀疏，標題越好讀）
local ROW_BASELINE  = 6       -- 距離該排底部幾 px＝共用的「地面線」
local ROW_JITTER    = 0       -- 上下隨機偏移。★這批是**站著的機體**，共用基線才像列隊；
                              --   設 >0 會變成高低飄浮，除非你要那個效果
-- ★ 背景減淡：零件圖有 60~83% 是黑的，直接鋪滿會把黑色標題字吃掉（HANDOFF §3-4）。
--   用 50% Bayer 白點打散成灰，標題才讀得到。設 0 = 不減淡（零件全黑、標題會糊）。
local BG_DIM        = 0.5

-- [[ 2026-08-11 ]] 標題背景改用**已經組裝好的機體圖** cover_asset_01~10
-- （原本是散裝零件 gun/wheel/canon/claw… 各自單獨飄，看起來像零件庫存而不是玩具兵團）。
-- 尺寸 48~80 寬 × 33~42 高，**都站在自己畫布的底部、且一律朝右**。
local COVER_ASSET_FILES = {
    "images/cover_asset_01", "images/cover_asset_02", "images/cover_asset_03",
    "images/cover_asset_04", "images/cover_asset_05", "images/cover_asset_06",
    "images/cover_asset_07", "images/cover_asset_08", "images/cover_asset_09",
    "images/cover_asset_10",
}

local bg_strips = {}    -- 4 張預先合成的長條圖
local bg_offsets = {}   -- 每排目前的捲動位移

-- 把零件隨機排成一條 STRIP_W 寬的長條。
-- ★ 超出右緣的零件會**再畫一次在 x-STRIP_W**，這樣頭尾接起來才不會有縫。
-- flip = true 時整排水平鏡射（往左跑的排要讓機體**面向前進方向**，
-- 否則會看起來像整排在倒退嚕）
local function buildStrip(parts, row_h, flip)
    local ok, buf = pcall(function() return gfx.image.new(STRIP_W, row_h) end)
    if not (ok and buf) then return nil end
    local mode = flip and gfx.kImageFlippedX or gfx.kImageUnflipped
    gfx.pushContext(buf)
    gfx.clear(gfx.kColorClear)
    -- ★★ 2026-08-11 修「有些圖疊在一起」：
    --   舊版最後一台超出右緣時會「補畫在 x − STRIP_W」讓接縫連續，
    --   但第一台的起點是 random(0, ROW_GAP_MAX)，那條補畫的尾巴就會壓在第一台身上。
    --   實測 **四分之一的長條圖會出現重疊**。
    --   改法：不補畫，改成**每次只從「剩餘空間放得下的圖」裡挑**——
    --   既不會超出右緣（所以不必補畫），也不會在尾端留一大塊空白。
    local x0 = math.random(0, ROW_GAP_MIN)   -- 起點縮小，接縫處的空隙才不會過大
    -- 接縫空隙 = (STRIP_W − 最後一台右緣) + x0，要 ≥ ROW_GAP_MIN 才不會頭尾黏在一起
    local right_limit = math.min(STRIP_W, STRIP_W - ROW_GAP_MIN + x0)
    local x = x0
    while true do
        local candidates = {}
        for _, im in ipairs(parts) do
            local w = im:getSize()
            if x + w <= right_limit then candidates[#candidates + 1] = im end
        end
        if #candidates == 0 then break end   -- 放不下任何一台 → 收工
        local img = candidates[math.random(#candidates)]
        local iw, ih = img:getSize()
        -- ★ 底部對齊（不是置中）：這批圖的機體都站在自己畫布的底部，
        --   置中會讓高矮不同的機體踩在不同高度，看起來像浮在空中。
        local y = row_h - ih - ROW_BASELINE
        if ROW_JITTER > 0 then y = y + math.random(-ROW_JITTER, ROW_JITTER) end
        img:draw(x, y, mode)
        x = x + iw + math.random(ROW_GAP_MIN, ROW_GAP_MAX)
    end
    gfx.popContext()
    return buf
end

local function buildTitleBackground()
    bg_strips, bg_offsets = {}, {}
    local parts = {}
    for _, path in ipairs(COVER_ASSET_FILES) do
        local okp, img = pcall(function() return gfx.image.new(path) end)
        if okp and img then parts[#parts + 1] = img end
    end
    if #parts == 0 then
        print("WARNING: StateMenu 標題背景找不到任何 cover_asset 圖")
        return
    end
    local row_h = 240 // ROWS
    for i = 1, ROWS do
        -- 往左跑的排（速度為負）整排鏡射，讓機體朝著前進方向
        local flip = (ROW_SPEEDS[i] or 0) < 0
        bg_strips[i] = buildStrip(parts, row_h, flip)
        bg_offsets[i] = math.random(0, STRIP_W - 1)   -- 起始相位打散，4 排才不會同步
    end
end

local function drawTitleBackground()
    if #bg_strips == 0 then return end
    local row_h = 240 // ROWS
    for i = 1, ROWS do
        local strip = bg_strips[i]
        if strip then
            -- ★ 起點必須是 (offset − STRIP_W)，**不是 −offset**。
            --   寫成 −offset 的話 offset 一變大 x 就變小 → 整排往「左」跑，
            --   與 ROW_SPEEDS 宣告的「正=向右」剛好相反（2026-08-11 修）。
            --   而且 flip 是看速度正負決定的，方向錯會連朝向一起錯，變成整排倒退嚕。
            local x = (bg_offsets[i] % STRIP_W) - STRIP_W
            while x < 400 do
                pcall(function() strip:draw(x, (i - 1) * row_h) end)
                x = x + STRIP_W
            end
        end
    end
    -- 減淡：鋪一層 50% 白點，把零件打散成灰，讓標題與選單的黑字浮出來
    if BG_DIM and BG_DIM > 0 then
        gfx.setColor(gfx.kColorWhite)
        gfx.setDitherPattern(BG_DIM, gfx.image.kDitherTypeBayer8x8)
        gfx.fillRect(0, 0, 400, 240)
        gfx.setColor(gfx.kColorBlack)   -- setColor 會清掉 pattern，這就是 reset
    end
end

function StateMenu.setup()
    -- 設置字體
    gfx.setFont(font)
    selected_index = 1
    print("LOG: StateMenu setup called - about to load cover image")
    -- 載入封面圖片 - 改用不帶副檔名的路徑
    local success, result = pcall(function()
        return gfx.image.new("images/cover")
    end)
    
    if success then
        cover_image = result
--        print("LOG: Cover image loaded successfully:", cover_image ~= nil)
    else
        print("ERROR: Failed to load cover image:", result)
    end

    -- [[ 標題背景 ]] 每次進標題都重新亂數組合一次，看起來才不會每次都一樣
    math.randomseed(playdate.getSecondsSinceEpoch and playdate.getSecondsSinceEpoch() or 0)
    buildTitleBackground()

    -- 播放標題/一般介面 BGM（循環）
    if _G.SoundManager and _G.SoundManager.playTitleBGM then
        _G.SoundManager.playTitleBGM()
    end
end

function StateMenu.update()
    -- [[ 標題背景 ]] 推進 4 排的捲動（refresh rate 固定 30fps，直接用每幀像素數，
    -- 與專案其他地方的 px/frame 慣例一致，不另外算 dt）
    for i = 1, #bg_strips do
        local sp = ROW_SPEEDS[i] or 0.6
        bg_offsets[i] = (bg_offsets[i] + sp) % STRIP_W
    end

    -- 處理方向鍵上下移動選單
    if playdate.buttonJustPressed(playdate.kButtonUp) then
        selected_index = selected_index - 1
        if selected_index < 1 then
            selected_index = #menu_options
        end
        -- 播放游標移動音效
        if _G.SoundManager and _G.SoundManager.playCursorMove then
            _G.SoundManager.playCursorMove()
        end
    elseif playdate.buttonJustPressed(playdate.kButtonDown) then
        selected_index = selected_index + 1
        if selected_index > #menu_options then
            selected_index = 1
        end
        -- 播放游標移動音效
        if _G.SoundManager and _G.SoundManager.playCursorMove then
            _G.SoundManager.playCursorMove()
        end
    end
    
    -- 處理 A 鍵確認
    if playdate.buttonJustPressed(playdate.kButtonA) then
        -- 播放選擇確認音效
        if _G.SoundManager and _G.SoundManager.playSelect then
            _G.SoundManager.playSelect()
        end
        
        local selection = menu_options[selected_index]
        if selection == "START GAME" then
            -- START GAME: 進入存檔選擇畫面
            if _G.StateSaveSelect then
                setState(_G.StateSaveSelect)
            else
                print("ERROR: StateSaveSelect not found")
            end
        elseif selection == "CREDITS" then
            if _G.StateCredits then
                setState(_G.StateCredits)
            else
                print("Action: Show Credits (StateCredits not found)")
            end
        end
    end
end

function StateMenu.draw()
    -- 首次初始化（用於 setup 沒有被呼叫的情況）
    if not setup_done then
        print("LOG: First draw - initializing")
        setup_done = true
        gfx.setFont(font)
        
        -- 嘗試載入封面圖片
        local success, result = pcall(function()
            return gfx.image.new("images/cover")
        end)
        
        if success then
            cover_image = result
            print("LOG: Cover image loaded in draw:", cover_image ~= nil)
        else
            print("ERROR: Failed to load cover image in draw:", result)
        end
        if #bg_strips == 0 then buildTitleBackground() end
    end

    gfx.clear(gfx.kColorWhite)

    -- [[ 標題背景 ]] 先鋪零件捲動層，cover 是透明底、疊在上面
    drawTitleBackground()

    -- 繪製封面圖片
    if cover_image then
        cover_image:draw(0, 0)
    end
    
    gfx.setColor(gfx.kColorBlack)
    -- 確保在 draw 週期中字體仍被設定 (雖然 setup 已經設過，但保留是好習慣)
    gfx.setFont(font)
    

    
    -- 繪製選單選項
    for i, option in ipairs(menu_options) do
        local y = menu_y_start + (i - 1) * line_height
            local text_width, text_height = gfx.getTextSize(option)
            local option_x = (400 - text_width) / 2  -- 水平置中
            if i == selected_index then
                -- 選中時使用黑底白字突出顯示（與任務選擇風格一致）
                local padding_x = 6
                local padding_y = 2
                gfx.setColor(gfx.kColorBlack)
                gfx.fillRect(option_x - padding_x, y - padding_y, text_width + padding_x * 2, text_height + padding_y * 2)
                gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
                gfx.drawText(option, option_x, y)
                gfx.setImageDrawMode(gfx.kDrawModeCopy)
                gfx.setColor(gfx.kColorBlack)
            else
                gfx.drawText(option, option_x, y)
        end
    end
end

return StateMenu