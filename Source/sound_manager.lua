-- sound_manager.lua - 音效管理模組

-- Playdate 音效不需要額外 import，直接使用 playdate.sound

SoundManager = {}

-- 音效合成器
local synth_cursor = nil      -- 游標移動音效
local synth_select = nil      -- 選擇音效
local synth_hit = nil         -- 擊中音效

-- ==========================================
-- 初始化音效系統
-- ==========================================
function SoundManager.init()
    -- 創建游標移動音效（高頻短促）
    synth_cursor = playdate.sound.synth.new(playdate.sound.kWaveSquare)
    
    -- 創建選擇音效（中頻較長）
    synth_select = playdate.sound.synth.new(playdate.sound.kWaveSawtooth)
    
    -- 創建擊中音效（低頻爆裂）
    synth_hit = playdate.sound.synth.new(playdate.sound.kWaveNoise)
    
    print("LOG: SoundManager initialized.")
end

-- ==========================================
-- 播放游標移動音效（0.3秒）
-- ==========================================
function SoundManager.playCursorMove()
    if synth_cursor then
        -- 高音短促的嗶聲
        local frequency = 800  -- 800 Hz
        local duration = 0.3   -- 0.3 秒
        
        -- 設置 ADSR 包絡（Attack, Decay, Sustain, Release）
        -- 快速上升，快速下降
        synth_cursor:setADSR(0.01, 0.1, 0.3, 0.1)
        
        -- 播放音效
        synth_cursor:playNote(frequency, 1.0, duration)
    end
end

-- ==========================================
-- 播放選擇確認音效（0.6秒）
-- ==========================================
function SoundManager.playSelect()
    if synth_select then
        -- 上升音調的確認聲
        local start_freq = 400  -- 起始頻率 400 Hz
        local end_freq = 800    -- 結束頻率 800 Hz
        local duration = 0.6    -- 0.6 秒
        
        -- 設置 ADSR 包絡（柔和的上升和下降）
        synth_select:setADSR(0.05, 0.2, 0.5, 0.2)
        
        -- 播放起始音符
        synth_select:playNote(start_freq, 1.0, duration * 0.5)
        
        -- 使用頻率調制創建上升效果
        synth_select:setFrequencyModulator(playdate.sound.synth.new(playdate.sound.kWaveSine))
        synth_select:playNote(end_freq, 1.0, duration * 0.5)
    end
end

-- ==========================================
-- 播放擊中音效（0.5秒）
-- ==========================================
function SoundManager.playHit()
    if synth_hit then
        -- 低頻爆裂聲
        local frequency = 150   -- 150 Hz（低音）
        local duration = 0.5    -- 0.5 秒
        
        -- 設置 ADSR 包絡（快速爆發，快速衰減）
        synth_hit:setADSR(0.01, 0.15, 0.2, 0.15)
        
        -- 使用噪音波形創建爆炸感
        synth_hit:setVolume(0.8)  -- 稍微降低音量避免過於刺耳
        synth_hit:playNote(frequency, 1.0, duration)
    end
end

-- ==========================================
-- 停止所有音效
-- ==========================================
function SoundManager.stopAll()
    if synth_cursor then synth_cursor:stop() end
    if synth_select then synth_select:stop() end
    if synth_hit then synth_hit:stop() end
end

return SoundManager
