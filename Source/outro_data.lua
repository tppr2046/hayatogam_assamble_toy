-- outro_data.lua
-- [[ S11 結局過場 ]] 打倒最終 BOSS（COMMAND CORE）後播放的結局頁面。
-- 結構與 intro_data.lua 完全相同：每頁一張圖 + 數句打字機文字。
--
-- 圖片：★ 2026-08-07 定案——**一般關卡共用 dialog_bg，但結局有專屬圖 cut_ending**。
-- 理由：結局是全遊戲唯一的收尾，用跟第一關一樣的圖會削掉「終於結束了」的份量。
-- 三頁共用這一張（換文字不換圖，與關卡同慣例）。
-- ⬜ cut_ending.png 尚未產出 —— state_outro 會自動退回 images/dialog_bg，
--    圖檔放進 Source/images/ 重新編譯即生效，本檔不必改。
--
-- 文案規則（GDD §1.5）：每句 ≤ 40 字元、每頁最多 2 句、主角不說話（全旁白）。

local outro = {
    pages = {
        {
            image = "images/cut_ending",
            lines = {
                "The transmission stopped.",
                "The last order died with the core.",
            }
        },
        {
            image = "images/cut_ending",
            lines = {
                "Across the wastes, the guns went quiet.",
                "No one told them. Now no one has to.",
            }
        },
        {
            image = "images/cut_ending",
            lines = {
                "The carriers came out to rebuild.",
                "The machines are quiet now. Finally.",
            }
        },
    }
}

return outro
