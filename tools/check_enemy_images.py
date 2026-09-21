#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
列出「敵人 / BOSS ↔ 圖檔」的完整對照，並檢查有沒有缺圖或孤兒圖。

用法:
    python tools/check_enemy_images.py

★ 為什麼需要這支：改圖檔名時，某隻敵人默默指到不存在的檔案，
  **pdc 不會擋、開機也不會報錯** —— 只有實際進到那一關才看得到黑方塊。
  2026-08-20 就發生過兩次（enemy01 更名、enemy2.png 誤刪）。

輸出三段：
  1) 敵人對照表（型別 / 名稱 / 移動型別 / 圖檔 / 規格 / 格數 / 動畫欄位）
  2) BOSS 對照表
  3) 檢查結果：缺圖（引用了不存在的檔）與孤兒圖（畫了但沒人讀）

離開碼：有缺圖時回傳 1，其餘 0（可接進 CI 或當成 commit 前的檢查）。
"""
import io, os, re, sys, glob

try:
    sys.stdout.reconfigure(encoding="utf-8")
except Exception:
    pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IMG_DIR = os.path.join(ROOT, "Source", "images")


def read(rel):
    return io.open(os.path.join(ROOT, rel), encoding="utf-8").read()


FILES = [os.path.basename(f) for f in glob.glob(os.path.join(IMG_DIR, "*.png"))]


def size_of(fn):
    """回傳 (寬, 高)。沒有 PIL 就回 None —— 這支的主要價值是「有沒有缺圖」，
    尺寸只是附帶資訊，不該因為缺一個套件就整支不能跑。"""
    try:
        from PIL import Image
        return Image.open(os.path.join(IMG_DIR, fn)).size
    except Exception:
        return None


def resolve(ref):
    """把 `images/<ref>` 解析成實際檔案。
    ★ 與遊戲的載入順序一致：**先試 imagetable、失敗才退回單張圖**
      （見 entity_enemy.lua 的 Enemy:init）。"""
    if not ref:
        return None, "-", 0
    tbl = [f for f in FILES if f.startswith(ref + "-table-")]
    if tbl:
        fn = tbl[0]
        m = re.search(r"-table-(\d+)-(\d+)\.png$", fn)
        cell_w, cell_h = int(m.group(1)), int(m.group(2))
        sz = size_of(fn)
        frames = (sz[0] // cell_w) if sz else 0
        return fn, "%dx%d" % (cell_w, cell_h), frames
    if (ref + ".png") in FILES:
        fn = ref + ".png"
        sz = size_of(fn)
        return fn, ("%dx%d" % sz if sz else "?"), 1
    return None, "-", 0


def blocks(src, only_prefix=None):
    """把 `["ID"] = {` 切成一塊塊。
    ⚠️ 不要用「到 `\\n    },` 為止」的正則 —— **最後一筆沒有逗號**，會整個漏掉
    （2026-08-20 踩過：RAMMER 因此沒出現在清單裡）。"""
    ids = [(m.group(1), m.start()) for m in re.finditer(r'\["(\w+)"\] = \{', src)]
    if only_prefix:
        ids = [x for x in ids if x[0].startswith(only_prefix)]
    out = []
    for i, (tid, st) in enumerate(ids):
        en = ids[i + 1][1] if i + 1 < len(ids) else len(src)
        out.append((tid, src[st:en]))
    return out


def field(body, pat):
    m = re.search(pat, body, re.M)
    return m.group(1) if m else None


used_refs = set()
missing = []

# ---------------------------------------------------------------- 敵人
print("=" * 78)
print("敵人 ↔ 圖檔")
print("=" * 78)
print("%-16s %-22s %-16s %-30s %-8s %s" % ("型別", "名稱", "移動", "圖檔", "規格", "格數/動畫"))
print("-" * 78)
for tid, body in blocks(read("Source/enemy_data.lua")):
    name = field(body, r'name = "([^"]+)"') or "?"
    move = field(body, r'move_type = "([^"]+)"') or "?"
    # ⚠️ 必須錨在行首縮排 —— `shield_image = "images/shield"` 這行**包含**
    #    子字串 `image = "images/shield"`，不錨的話 SHIELD_ROBOT 會被抓成盾牌的圖
    #    （2026-09-21 發現：索引表一直把它記成 shield.png，實際是 enemy02）。
    ref = field(body, r'^\s*image = "images/(\w+)"')
    if ref:
        used_refs.add(ref)
    fn, spec, frames = resolve(ref)
    if ref and not fn:
        missing.append((tid, ref))
    anim = []
    if "anim_idle_move = true" in body:
        anim.append("idle/move")
    fps = field(body, r"anim_fps = (\d+)")
    if fps:
        anim.append("anim_fps=" + fps)
    if "walk_fps" in body:
        anim.append("walk")
    note = ("%d 格" % frames if frames else "") + (" · " + ",".join(anim) if anim else "")
    print("%-16s %-22s %-16s %-30s %-8s %s" % (tid, name, move, fn or ("缺圖→" + str(ref)), spec, note))
    # 附屬圖（劍 / 盾）
    for extra in re.finditer(r'(\w+_image) = "images/(\w+)"', body):
        used_refs.add(extra.group(2))
        efn, espec, _ = resolve(extra.group(2))
        if not efn:
            missing.append((tid + "." + extra.group(1), extra.group(2)))
        print("%-16s %-22s %-16s %-30s %-8s %s" % ("", "└ " + extra.group(1), "", efn or "缺圖", espec, ""))

# ---------------------------------------------------------------- BOSS
print()
print("=" * 78)
print("BOSS ↔ 圖檔")
print("=" * 78)
boss_src = read("Source/boss_data.lua")
for tid, body in blocks(boss_src, only_prefix="BOSS"):
    name = field(body, r'name = "([^"]+)"') or "?"
    # ★ 只認**欄位本身**，不要認註解 —— 下一隻的說明區塊會落在上一隻的切片裡
    mode = "序列制"
    if re.search(r'^\s*part_mode = "PARALLEL"', body, re.M):
        mode = "平行零件制"
    if re.search(r'^\s*move_mode = "FLIGHT"', body, re.M):
        mode = "序列制＋飛行"
    bw = field(body, r"body_w = (\d+)")
    bh = field(body, r"body_h = (\d+)")
    # ★ 本體與手臂都是 `sprite = ...`，只能靠名字分：手臂一律以 `_arm` 結尾。
    #   用縮排深度來分會很脆弱（資料排版一改就壞）。
    all_sprites = re.findall(r'sprite = "images/(\w+)"', body)
    body_ref = next((r for r in all_sprites if not r.endswith("_arm")), None)
    arm_ref = next((r for r in all_sprites if r.endswith("_arm")), None)
    for label, ref in (("本體", body_ref), ("手臂", arm_ref)):
        if not ref:
            continue
        used_refs.add(ref)
        fn, spec, frames = resolve(ref)
        state = ("%s (%s ×%d格)" % (fn, spec, frames)) if fn else "尚未製作 → 程式繪製佔位"
        print("%-8s %-12s %-14s %sx%s  %s: %s" % (tid, name, mode, bw, bh, label, state))

# ---------------------------------------------------------------- 檢查
print()
print("=" * 78)
orphans = []
for f in sorted(FILES):
    base = re.sub(r"-table-\d+-\d+$", "", f[:-4])
    if (base.startswith("enemy") or base.startswith("boss")) and base not in used_refs:
        orphans.append(f)

if missing:
    print("❌ 缺圖（引用了不存在的檔案，遊戲會退回黑方塊佔位）:")
    for who, ref in missing:
        print("   %s -> images/%s" % (who, ref))
else:
    print("OK 缺圖 0")

if orphans:
    print("⚠️ 孤兒圖（在 Source/images/ 但沒有任何程式讀它）:")
    for f in orphans:
        print("   ", f)
else:
    print("OK 孤兒圖 0")

sys.exit(1 if missing else 0)
