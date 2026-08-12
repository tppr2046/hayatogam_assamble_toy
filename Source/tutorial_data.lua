-- tutorial_data.lua
-- [[ S10 操作教學 ]] 首次遊玩的教學文案（三段：組裝介面 / 商店 / 關卡內操作）。
-- 每段首次進入該畫面時觸發一次，完成狀態存進存檔的 tutorial 表，不會重複出現。
-- 文字可直接在此編修；長句會在提示框內自動斷行。

local tutorial = {
    hq = {
        title = "ASSEMBLY",
        lines = {
            "This is your assembly bay. The mech is built from parts on a 3x2 grid.",
            "Up/Down picks a part from the list, Left/Right picks the column, A installs it.",
            "Top row takes weapons and arms; bottom row takes wheels and legs.",
            "An X means the part cannot go there. Pick REMOVE PART to take one off.",
            "When you are ready, press Right to reach START and begin the mission.",
        }
    },
    shop = {
        title = "SHOP",
        lines = {
            "Missions pay you in steel, copper and rubber. Spend them here.",
            "Up/Down browses parts; the panel shows the cost and where it mounts.",
            "Press A to buy. Owned parts are marked OWNED and appear in the assembly bay.",
        }
    },
    mission = {
        title = "CONTROLS",
        lines = {
            "You operate one part at a time. Up/Down switches which part has focus.",
            "The focused part is highlighted, and the panel below shows its controls.",
            "Left/Right drives the mech. The crank aims cannons and swings arms; A fires or grabs.",
            "Switching fast is the whole job -- drive, aim, grab, repeat.",
        }
    },
}

return tutorial
