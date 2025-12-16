-- sound_manager.lua - 音效管理模組

-- Playdate 音效不需要額外 import，直接使用 playdate.sound

SoundManager = {}

-- 音效合成器（使用模組變數而非 local）
SoundManager.synth_cursor = nil      -- 游標移動音效
SoundManager.synth_select = nil      -- 選擇音效
SoundManager.synth_hit = nil         -- 擊中音效
SoundManager.synth_explode = nil     -- 爆炸音效
SoundManager.bgm_player = nil        -- 目前的 BGM 播放器
SoundManager.current_bgm = nil       -- 目前播放的 BGM 檔名

-- ==========================================
-- 初始化音效系統
-- ==========================================
function SoundManager.init()
    print("========== SOUND: Initializing SoundManager ==========")
    
    -- 創建游標移動音效（高頻短促）
    SoundManager.synth_cursor = playdate.sound.synth.new(playdate.sound.kWaveSquare)
    if SoundManager.synth_cursor then
        SoundManager.synth_cursor:setADSR(0.01, 0.1, 0.5, 0.05)
        SoundManager.synth_cursor:setVolume(0.5)
        print("SOUND: synth_cursor created successfully")
    else
        print("SOUND ERROR: Failed to create synth_cursor")
    end
    
    -- 創建選擇音效（中頻較長）
    SoundManager.synth_select = playdate.sound.synth.new(playdate.sound.kWaveSawtooth)
    if SoundManager.synth_select then
        SoundManager.synth_select:setADSR(0.02, 0.2, 0.6, 0.2)
        SoundManager.synth_select:setVolume(0.5)
        print("SOUND: synth_select created successfully")
    else
        print("SOUND ERROR: Failed to create synth_select")
    end
    
    -- 創建擊中音效（低頻爆裂）
    SoundManager.synth_hit = playdate.sound.synth.new(playdate.sound.kWaveNoise)
    if SoundManager.synth_hit then
        SoundManager.synth_hit:setADSR(0.01, 0.1, 0.3, 0.15)
        SoundManager.synth_hit:setVolume(0.6)
        print("SOUND: synth_hit created successfully")
    else
        print("SOUND ERROR: Failed to create synth_hit")
    end
    
    print("========== SOUND: SoundManager initialized ==========")
end

-- ==========================================
-- 播放游標移動音效（0.2秒）
-- ==========================================
function SoundManager.playCursorMove()
    -- 延遲初始化：如果 synth 還沒創建，先初始化
    if not SoundManager.synth_cursor then
        print("SOUND: Lazy init - creating synth_cursor")
        SoundManager.synth_cursor = playdate.sound.synth.new(playdate.sound.kWaveSquare)
        if SoundManager.synth_cursor then
            -- ADSR: Attack, Decay, Sustain, Release
            -- 設定短促的包絡線，確保聲音會停止
            SoundManager.synth_cursor:setADSR(0.01, 0.05, 0.0, 0.05)  -- Sustain = 0 確保會停止
            SoundManager.synth_cursor:setVolume(0.5)
            print("SOUND: synth_cursor created successfully (lazy)")
        else
            print("SOUND ERROR: Failed to create synth_cursor (lazy)")
            return
        end
    end
    
    print("========== SOUND: Playing Cursor Move ==========")
    SoundManager.synth_cursor:playNote("C4", 0.1)
end

-- ==========================================
-- 播放選擇確認音效（使用音檔）
-- ==========================================
function SoundManager.playSelect()
    print("========== SOUND: Playing Select ==========")
    -- 使用檔案播放器播放音檔
    local ok, player = pcall(function()
        return playdate.sound.fileplayer.new("audio/choose")
    end)
    if ok and player then
        player:setVolume(0.7)
        player:play()
        print("SOUND: choose.wav played successfully")
    else
        print("SOUND ERROR: Failed to play choose.wav")
    end
end

-- ==========================================
-- 播放擊中音效（0.5秒）
-- ==========================================
function SoundManager.playHit()
    -- 延遲初始化：如果 synth 還沒創建，先初始化
    if not SoundManager.synth_hit then
        print("SOUND: Lazy init - creating synth_hit")
        SoundManager.synth_hit = playdate.sound.synth.new(playdate.sound.kWaveNoise)
        if SoundManager.synth_hit then
            -- 設定爆裂聲的包絡線，快速衰減
            SoundManager.synth_hit:setADSR(0.01, 0.1, 0.0, 0.1)  -- Sustain = 0 確保會停止
            SoundManager.synth_hit:setVolume(0.6)
            print("SOUND: synth_hit created successfully (lazy)")
        else
            print("SOUND ERROR: Failed to create synth_hit (lazy)")
            return
        end
    end
    
    print("========== SOUND: Playing Hit ==========")
    SoundManager.synth_hit:playNote("C1", 0.5)
end


-- ==========================================
-- 播放爆炸音效（使用音檔）
-- ==========================================
function SoundManager.playExplode()
    print("========== SOUND: Playing Explode ==========")
    -- 使用檔案播放器播放音檔
    local ok, player = pcall(function()
        return playdate.sound.fileplayer.new("audio/explode")
    end)
    if ok and player then
        player:setVolume(0.8)
        player:play()
        print("SOUND: explode.wav played successfully")
    else
        print("SOUND ERROR: Failed to play explode.wav")
    end
end

-- ==========================================
-- 播放玩家砲台發射音效（使用爆炸音檔）
-- ==========================================
function SoundManager.playCanonFire()
    print("========== SOUND: Playing Canon Fire ==========")
    -- 使用檔案播放器播放音檔
    local ok, player = pcall(function()
        return playdate.sound.fileplayer.new("audio/explode")
    end)
    if ok and player then
        player:setVolume(0.6)  -- 砲台發射音量稍小
        player:play()
        print("SOUND: canon fire explode.wav played successfully")
    else
        print("SOUND ERROR: Failed to play canon fire explode.wav")
    end
end





-- ==========================================
-- 停止所有音效
-- ==========================================
function SoundManager.stopAll()
    if SoundManager.synth_cursor then SoundManager.synth_cursor:stop() end
    if SoundManager.synth_select then SoundManager.synth_select:stop() end
    if SoundManager.synth_hit then SoundManager.synth_hit:stop() end
    if SoundManager.synth_explode then SoundManager.synth_explode:stop() end
    if SoundManager.bgm_player then SoundManager.bgm_player:stop() end
end

-- ==========================================
-- BGM 控制：播放/停止背景音樂（循環）
-- ==========================================
function SoundManager.playBGM(path)
    -- 如果已在播放相同檔案，忽略
    if SoundManager.current_bgm == path and SoundManager.bgm_player then
        print("SOUND: Already playing BGM -> " .. tostring(path))
        return
    end
    -- 停止舊的 BGM
    if SoundManager.bgm_player then
        print("SOUND: Stopping previous BGM")
        SoundManager.bgm_player:stop()
        SoundManager.bgm_player = nil
    end
    -- 建立新的檔案播放器（不使用 pcall 以便看到錯誤訊息）
    print("SOUND: Loading BGM file -> " .. tostring(path))
    local player = playdate.sound.fileplayer.new(path)
    if player then
        SoundManager.bgm_player = player
        SoundManager.current_bgm = path
        -- 設定循環播放
        player:setVolume(0.7)
        player:play(0)  -- 0 = 無限循環
        print("SOUND: BGM started playing -> " .. tostring(path))
    else
        print("SOUND ERROR: Failed to create fileplayer for: " .. tostring(path))
    end
end

function SoundManager.stopBGM()
    if SoundManager.bgm_player then
        SoundManager.bgm_player:stop()
        SoundManager.bgm_player = nil
        SoundManager.current_bgm = nil
    end
end

function SoundManager.playTitleBGM()
    SoundManager.playBGM("audio/bgm_title")
end

function SoundManager.playMissionBGM()
    SoundManager.playBGM("audio/bgm1")
end

return SoundManager
