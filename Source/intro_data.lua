-- intro_data.lua
-- [[ S9 開場過場 ]] 新遊戲開始播放的劇情頁面（形式同關卡開始前的劇情畫面：
-- 上方靜圖 + 下方打字機文字，A 前進、B 跳過）。
-- 2026-08-05：四頁插圖與文案全部定稿（檔名為 intro_01~04，非規格書上的 intro1~4）。
--
-- 敘事結構：過去式無人稱（世界）→ 過去式第一人稱（我）→ 現在式 → 祈使句（推玩家進遊戲）。
--
-- ⚠️ 改文字前先量寬度，不要只數字元：文字框可用寬度 = 384px
--    （滿版 box_w 400 − 左右 padding 16，見 state_intro.lua 的 drawTextInRect）。
--    字寬在 fonts/Assemble.fnt，tracking=1。40 個字元就可能超過而折行，
--    折行會讓打字機的節奏斷掉。目前八句最寬 328px。

local intro = {
    pages = {
        {
            -- 核爆：蘑菇雲 + 城市天際線
            image = "images/intro_01",
            lines = {
                "The fires burned for four days.",
                "Nothing that breathed survived.",
            }
        },
        {
            -- 廢墟街景：倒塌大樓與瓦礫
            image = "images/intro_02",
            lines = {
                "Then the war ended.",
                "Nobody told the machines.",
            }
        },
        {
            -- 主角核心特寫：躺在零件堆裡
            image = "images/intro_03",
            lines = {
                "I woke up as a single toy core.",
                "Everything else, I had to build.",
            }
        },
        {
            -- 對峙：左＝軍規（黑實心）／右＝玩具規格（白線稿）
            image = "images/intro_04",
            lines = {
                "Weapons tear the weak toys apart.",
                "We toys need to help each other.",
                "Bolt on every part you find.",
            }
        },
    }
}

return intro
