-- intro_data.lua
-- [[ S9 開場過場 ]] 新遊戲開始播放的劇情頁面（形式同關卡開始前的劇情畫面：
-- 上方靜圖 + 下方打字機文字，A 前進、B 跳過）。
-- 圖片先沿用 dialog_bg 當暫代；日後每頁換成專屬插圖即可（image 欄位改路徑）。

local intro = {
    pages = {
        {
            image = "images/dialog_bg",
            lines = {
                "The war machines came, and our cities fell silent.",
                "What we had left were scraps... and each other.",
            }
        },
        {
            image = "images/dialog_bg",
            lines = {
                "From those scraps we built a machine of our own.",
                "No two pilots ever assemble it the same way.",
            }
        },
        {
            image = "images/dialog_bg",
            lines = {
                "Today it is yours, Pilot.",
                "Bolt on your parts, and take our world back.",
            }
        },
    }
}

return intro
