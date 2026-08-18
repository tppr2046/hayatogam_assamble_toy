-- core_data.lua
-- [[ CORE ]] 核心資料表。設計見 GDD §8.05：主角＝一顆核心，撿零件把自己的身體拼起來。
--
-- 2026-08-06 全部接線完成：
--   * `base_hp`   → HP ＝ 核心基礎 HP + 已裝零件 hp 總和（state_hq.lua 的 recalcMechStats）
--   * `weight_cap`→ 裝上去會超過上限時**擋在安裝階段**（不做「可裝但變慢」）
--   * 尚未做：核心的取得時機與更換介面（需要進程系統），目前固定 CORE1。
--
-- 圖：images/core-table-32-16.png（3 格 32×16），frame 對應下表。
--     2026-08-06 由 16×16 加大為 32×16；HQ 的繪製位置與大小都從圖尺寸自動算，換圖不必改程式。
-- 核心**不佔組裝格**、**關卡中不顯示**，只出現在組裝畫面
-- （畫在**格線之上、零件之下**：蓋掉格線，但被裝上去的零件蓋住）。

local CoreData = {}

CoreData.default_id = "CORE1"
CoreData.order = { "CORE1", "CORE2", "CORE3" }

-- jump_mult：跳躍**高度**的倍率（不是初速度倍率）。
--   0   = 完全不能跳，且操作面板不顯示跳躍鈕
--   1.0 = 零件的原始跳躍高度
-- 實際高度 = 零件的 jump_height × 這個倍率（見 entity_mech.lua 的 getJumpHeight）。
--
-- jump_label：給玩家看的跳躍等級。**UI 一律顯示這個，不顯示倍率數字**——
-- 玩家不需要知道 ×1.3 是什麼意思，只需要知道「跳得更高了」。
-- 改倍率時記得一併確認等級名稱還說得通。
CoreData.list = {
    -- [[ 2026-08-13 ]] `button_sprite` ＝ HQ 右下角出擊按鈕用的 imagetable（3 格 64×64：
    --   1 底座 / 2 按鈕未按 / 3 按鈕按下）。**那顆按鈕就是核心本體**，所以核心升級時整張換掉。
    -- ★ 寫成資料欄位而不是在 state_hq 裡用 id 拼字串 —— 日後改名或改路徑只要動這一行。
    -- ⚠️ core2 / core3 的圖尚未繪製；state_hq 載不到時會自動退回 CORE1 的圖，不會壞掉。
    CORE1 = { id = "CORE1", name = "SALVAGE", frame = 1, base_hp = 30,  weight_cap = 16, jump_mult = 0,   jump_label = "NONE",   button_sprite = "images/core1" },
    CORE2 = { id = "CORE2", name = "FIELD",   frame = 2, base_hp = 60,  weight_cap = 24, jump_mult = 1.0, jump_label = "MEDIUM", button_sprite = "images/core2" },
    CORE3 = { id = "CORE3", name = "COMMAND", frame = 3, base_hp = 100, weight_cap = 34, jump_mult = 1.3, jump_label = "HIGH",   button_sprite = "images/core3" },
}

-- 取得核心資料；id 無效或未設定時回退到預設核心（永不回傳 nil）
function CoreData.get(id)
    return CoreData.list[id] or CoreData.list[CoreData.default_id]
end

-- 取得目前裝備中的核心（讀 GameState.core_id）
function CoreData.current()
    local id = _G.GameState and _G.GameState.core_id
    return CoreData.get(id)
end

-- 在 order 中的名次（1=最初階）。未知 id 回 0。
function CoreData.rank(id)
    for i, cid in ipairs(CoreData.order) do
        if cid == id then return i end
    end
    return 0
end

-- [[ 取得 ]] 給予一顆核心。核心是**純階梯升級**（每一階全面優於前一階），
-- 所以取得後直接自動裝上，不需要選擇介面（GDD §8.05a）。
-- 回傳 true 代表這次真的有升級（新拿到、且比目前這顆好）。
function CoreData.grant(id)
    if not CoreData.list[id] then return false end
    _G.GameState = _G.GameState or {}
    _G.GameState.owned_cores = _G.GameState.owned_cores or {}
    local already = _G.GameState.owned_cores[id]
    _G.GameState.owned_cores[id] = true
    -- 只在「比目前這顆高階」時才換上，避免重打舊關卡把核心降級
    if CoreData.rank(id) > CoreData.rank(_G.GameState.core_id) then
        _G.GameState.core_id = id
        return true
    end
    return (not already)
end

return CoreData
