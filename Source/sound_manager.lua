-- sound_manager.lua - 音效管理模組

-- Playdate 音效不需要額外 import，直接使用 playdate.sound

SoundManager = {}

-- 音效合成器（使用模組變數而非 local）
SoundManager.synth_cursor = nil      -- 游標移動音效
SoundManager.synth_select = nil      -- 選擇音效
SoundManager.synth_hit = nil         -- 擊中音效

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
-- 播放選擇確認音效（0.6秒）
-- ==========================================
function SoundManager.playSelect()
    -- 延遲初始化：如果 synth 還沒創建，先初始化
    if not SoundManager.synth_select then
        print("SOUND: Lazy init - creating synth_select")
        SoundManager.synth_select = playdate.sound.synth.new(playdate.sound.kWaveSawtooth)
        if SoundManager.synth_select then
            -- 設定柔和但會停止的包絡線
            SoundManager.synth_select:setADSR(0.03, 0.07, 0.0, 0.12)  -- Sustain = 0 確保會停止
            SoundManager.synth_select:setVolume(0.6)
            print("SOUND: synth_select created successfully (lazy)")
        else
            print("SOUND ERROR: Failed to create synth_select (lazy)")
            return
        end
    end
    
    print("========== SOUND: Playing Select ==========")
    SoundManager.synth_select:playNote("E5", 0.6)
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
-- 停止所有音效
-- ==========================================
function SoundManager.stopAll()
    if SoundManager.synth_cursor then SoundManager.synth_cursor:stop() end
    if SoundManager.synth_select then SoundManager.synth_select:stop() end
    if SoundManager.synth_hit then SoundManager.synth_hit:stop() end
end

return SoundManager
