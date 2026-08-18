#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
掃描 hq_bg.png，量出各個框的「內緣」座標，直接對應 state_hq.lua 的 HQ_LAYOUT。

用法:
    python tools/scan_hq_bg.py [圖片路徑]
    （預設 Source/images/hq_bg.png）

原理:
    底圖只有黑框線與白底。把「被框線圍起來的白色連通區域」找出來，
    它的 bounding box 就是該框的內緣 —— 那正是程式要對齊內容的位置。

★ 為什麼不用「找線條交點」：SHOP / START 那種方塊不是滿版線條，
  用線條交點會漏掉；白色連通區域對兩種都成立。
"""
import sys
from collections import deque

# Windows 主控台預設 cp950，強制 UTF-8 才不會在輸出中文時炸掉
try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

try:
    from PIL import Image
except ImportError:
    sys.exit("需要 Pillow：pip install pillow")

PATH = sys.argv[1] if len(sys.argv) > 1 else "Source/images/hq_bg.png"
MIN_AREA = 400          # 小於這個面積的白區當雜訊略過
THRESHOLD = 128         # 低於此值視為黑（框線）

im = Image.open(PATH).convert("L")
W, H = im.size
px = im.load()

print("圖片: %s  尺寸: %dx%d" % (PATH, W, H))
if (W, H) != (400, 240):
    print("[!] 尺寸不是 400x240 —— Playdate 螢幕是 400x240，請確認")

is_white = [[px[x, y] >= THRESHOLD for x in range(W)] for y in range(H)]
seen = [[False] * W for _ in range(H)]
boxes = []

for sy in range(H):
    for sx in range(W):
        if seen[sy][sx] or not is_white[sy][sx]:
            continue
        # BFS 找一塊白色連通區域（4 連通）
        q = deque([(sx, sy)])
        seen[sy][sx] = True
        minx = maxx = sx
        miny = maxy = sy
        area = 0
        touches_edge = False
        while q:
            x, y = q.popleft()
            area += 1
            if x < minx: minx = x
            if x > maxx: maxx = x
            if y < miny: miny = y
            if y > maxy: maxy = y
            if x == 0 or y == 0 or x == W - 1 or y == H - 1:
                touches_edge = True
            for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if 0 <= nx < W and 0 <= ny < H and not seen[ny][nx] and is_white[ny][nx]:
                    seen[ny][nx] = True
                    q.append((nx, ny))
        if area >= MIN_AREA:
            boxes.append({
                "x": minx, "y": miny,
                "w": maxx - minx + 1, "h": maxy - miny + 1,
                "area": area, "edge": touches_edge,
            })

# 由上而下、由左而右排序，方便對照畫面
boxes.sort(key=lambda b: (b["y"], b["x"]))

print("\n找到 %d 個框（面積 >= %d）：\n" % (len(boxes), MIN_AREA))
print("  %-4s %-5s %-5s %-5s %-5s %-8s %-6s %s" %
      ("#", "x", "y", "w", "h", "面積", "填充率", "備註"))
for i, b in enumerate(boxes, 1):
    fill = b["area"] / float(b["w"] * b["h"]) * 100
    note = []
    if b["edge"]:
        note.append("觸及畫面邊緣(可能是框外的背景)")
    if fill < 95:
        note.append("非矩形(填充率低)")
    print("  %-4d %-5d %-5d %-5d %-5d %-8d %5.1f%%  %s" %
          (i, b["x"], b["y"], b["w"], b["h"], b["area"], fill, " ".join(note)))

print("""
--- 貼進 state_hq.lua 的 HQ_LAYOUT 用 ---
（x/y = 內緣左上角，w/h = 內緣寬高；名稱要自己對照畫面填）""")
for i, b in enumerate(boxes, 1):
    if b["edge"]:
        continue
    print("    box%-2d = { x = %-3d, y = %-3d, w = %-3d, h = %-3d }," %
          (i, b["x"], b["y"], b["w"], b["h"]))

print("""
[!] 提醒
  1. 文字行高 16px（fonts/Assemble.fnt）→ 框內高度 ÷ 16 ＝ 放得下幾行
  2. 框內要放黑字就必須是白底（HANDOFF §3-4）
  3. 組裝格 96x64、操作面板 96x64、這兩個尺寸不可改
""")
