#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
比對「遊戲的資料表」與「關卡編輯器」是否同步。

用法:
    python tools/check_editor_sync.py <level_editor.html 的路徑>

★ 為什麼需要這支：編輯器不在 Source/ 底下，grep 搜不到，
  所以新增敵人／BOSS 時最容易忘記它（HANDOFF §3-5 的第一條）。
  這支把「肉眼比對」變成一行指令。
"""
import io, re, sys, os

if len(sys.argv) < 2:
    sys.exit("用法: python tools/check_editor_sync.py <level_editor.html>")
ed_path = sys.argv[1]
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

def read(p):
    return io.open(os.path.join(root, p), encoding="utf-8").read()

ed = io.open(ed_path, encoding="utf-8").read()

fail = 0

# --- 敵人型別 ---
game_enemies = set(re.findall(r'^\s*\["([A-Z_]+)"\]\s*=\s*\{', read("Source/enemy_data.lua"), re.M))
ed_defs = set(re.findall(r'^\s{2}([A-Z_]+):\s*\{\s*w:', ed, re.M))
ed_tools = set(re.findall(r'enemy:([A-Z_]+)', ed))

missing_def = sorted(game_enemies - ed_defs)
missing_tool = sorted(game_enemies - ed_tools)
extra = sorted(ed_defs - game_enemies - {"BOSS"})

print("遊戲敵人型別 %d 種" % len(game_enemies))
if missing_def:
    print("  [!] 編輯器 ENEMY_DEF 缺少:", ", ".join(missing_def)); fail += 1
if missing_tool:
    print("  [!] 編輯器工具列缺少:", ", ".join(missing_tool)); fail += 1
if extra:
    print("  [!] 編輯器有、但遊戲沒有:", ", ".join(extra)); fail += 1
if not (missing_def or missing_tool or extra):
    print("  OK — ENEMY_DEF 與工具列都齊全")

# --- BOSS ---
game_bosses = set(re.findall(r'^\s*\["(BOSS\d+)"\]', read("Source/boss_data.lua"), re.M))
m = re.search(r'BOSS_IDS\s*=\s*\[(.*?)\]', ed)
ed_bosses = set(x.strip().strip('"\'') for x in m.group(1).split(",") if x.strip()) if m else set()
print("遊戲 BOSS %d 隻" % len(game_bosses))
if game_bosses - ed_bosses:
    print("  [!] 編輯器 BOSS_IDS 缺少:", ", ".join(sorted(game_bosses - ed_bosses))); fail += 1
else:
    print("  OK")

# --- 地形型別 ---
game_terrain = set(re.findall(r'terrain\.type == "(\w+)"', read("Source/entity_controller.lua")))
game_terrain |= set(re.findall(r'terrain_type == "(\w+)"', read("Source/entity_controller.lua")))
# 只抓工具列 id（terrain:xxx 出現在 {id:"terrain:pit"...}），
# 不要抓到 `terrain:Array(n).fill("flat")` 這種物件字面量
ed_terrain = set(re.findall(r'id:"terrain:(\w+)"', ed))
unknown = sorted(ed_terrain - game_terrain - {"flat"})
print("編輯器地形型別:", ", ".join(sorted(ed_terrain)))
if unknown:
    print("  [!] 編輯器提供、但遊戲不認得:", ", ".join(unknown)); fail += 1
else:
    print("  OK")

sys.exit(1 if fail else 0)
