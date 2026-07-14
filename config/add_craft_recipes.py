#!/usr/bin/env python3
"""Add 飞剑/阵法/符箓 recipes and type=4 items."""
import json, re
from pathlib import Path

BASE = Path(__file__).parent
recipes = json.load(open(BASE / "json_output" / "recipes.json", encoding="utf-8"))
items = json.load(open(BASE / "json_output" / "items.json", encoding="utf-8"))

name_map = {}
for it in items["regular"]:
    name_map[it["name"]] = it["id"]

def parse_ing(text):
    if not text or text == "—": return None
    # Name（code）×count
    m = re.match(r"(.+?)（(.+?)）\s*[×xX]\s*(\d+)", text)
    if m:
        return {"recipe_code": m.group(2).strip(), "count": int(m.group(3))}
    # Name Lv.N × Count
    m = re.match(r"(.+?)Lv\.(\d+)\s*[×xX]\s*(\d+)", text)
    if m:
        raw = m.group(1).strip()
        lv = int(m.group(2))
        count = int(m.group(3))
        if raw in name_map:
            return {"id": name_map[raw], "count": count}
        # Aliases
        if raw == "粗兽血": return {"id": 8001, "count": count}
        if raw == "兽皮": return {"id": 7000 + lv, "count": count}
        if raw == "阵法图": return {"id": 13100 + lv, "count": count}
        return {"name": raw, "level": lv, "count": count}
    return None

# ── Data ──
sword_recipes = [
    ("剑01","铁木剑",["黑铁矿Lv.2×3","山泉水Lv.1×2"]),
    ("剑02","铜锋剑",["秘银矿Lv.3×3","溪流液Lv.2×2","铜砂粒Lv.1×3"]),
    ("剑03","银光剑",["秘银矿Lv.3×4","玄金母Lv.4×2","银光尘Lv.3×2","潭心水Lv.3×2"]),
    ("剑04","玄金短剑",["玄金母Lv.4×4","金母碎Lv.4×3","玉瓶露Lv.4×2"]),
    ("剑05","寒渊冰剑",["寒渊铁Lv.5×4","寒铁屑Lv.5×3","冰泉液Lv.5×2","铁石芯Lv.2×3"]),
    ("剑06","赤炎火剑",["赤炎晶Lv.6×4","炎晶核Lv.6×3","温汤泉Lv.6×2"]),
    ("剑07","青灵木剑",["青灵玉Lv.7×4","青玉髓Lv.7×3","青岩液Lv.7×2","青灵浆Lv.7×2"]),
    ("剑08","金雷斩邪剑",["金雷砂Lv.8×4","雷砂金Lv.8×3","雷池水Lv.8×2","雷纹液Lv.8×2"]),
    ("剑09","地脉重剑",["地脉髓晶Lv.9×4","地脉珠Lv.9×3","地脉髓泉Lv.9×2","地脉乳Lv.9×2"]),
    ("剑10","星陨长剑",["天陨星核Lv.10×4","星核粉Lv.10×3","星辉液Lv.10×2","星辉露Lv.10×2"]),
    ("剑11","虚空影剑",["虚空碧玉Lv.11×4","虚空晶片Lv.11×3","紫府灵泉Lv.11×2","紫府琼浆Lv.11×2"]),
    ("剑12","九幽玄冥剑",["九幽玄铁Lv.12×4","九幽玄砂Lv.12×3","九窍玉液Lv.12×2","九窍玲珑果Lv.12×2"]),
    ("剑13","太阳真光剑",["太阳真金Lv.13×4","太阳精金Lv.13×3","涅槃泉Lv.13×2","涅槃涎Lv.13×2"]),
    ("剑14","太阴寒月剑",["太阴寒玉Lv.14×4","太阴寒核Lv.14×3","龙涎泉Lv.14×2","龙涎髓Lv.14×2"]),
    ("剑15","星河无极剑",["星河神砂Lv.15×4","星河砂砾Lv.15×3","凤羽灵泉Lv.15×2","凤羽凝露Lv.15×2"]),
    ("剑16","鸿蒙开天剑",["鸿蒙仙晶Lv.16×4","鸿蒙金气Lv.16×3","混沌灵液Lv.16×2","混沌元液Lv.16×2"]),
]

array_recipes = [
    ("阵01","清风阵",["阵法图Lv.1×2","阵旗Lv.1×3","山泉水Lv.1×2"]),
    ("阵02","聚灵阵",["阵法图Lv.2×2","阵旗Lv.2×3","溪流液Lv.2×2","铜砂粒Lv.1×3"]),
    ("阵03","铁壁阵",["阵法图Lv.3×2","阵旗Lv.3×3","铁石芯Lv.2×3","潭心水Lv.3×2"]),
    ("阵04","三才锁灵阵",["阵法图Lv.4×2","阵旗Lv.4×3","金母碎Lv.4×3","玉瓶露Lv.4×2"]),
    ("阵05","四象寒冰阵",["阵法图Lv.5×2","阵旗Lv.5×3","寒铁屑Lv.5×3","冰雪露Lv.5×2"]),
    ("阵06","烈焰困阵",["阵法图Lv.6×2","阵旗Lv.6×3","炎晶核Lv.6×3","赤阳涎Lv.6×2"]),
    ("阵07","厚土御阵",["阵法图Lv.7×2","阵旗Lv.7×3","青玉髓Lv.7×3","青灵浆Lv.7×2"]),
    ("阵08","五雷诛邪阵",["阵法图Lv.8×2","阵旗Lv.8×3","雷砂金Lv.8×3","雷纹液Lv.8×2"]),
    ("阵09","地脉龙吟阵",["阵法图Lv.9×2","阵旗Lv.9×3","地脉珠Lv.9×3","地脉乳Lv.9×2"]),
    ("阵10","星罗迷阵",["阵法图Lv.10×2","阵旗Lv.10×3","星核粉Lv.10×3","星辉露Lv.10×2"]),
    ("阵11","九幻迷心阵",["阵法图Lv.11×2","阵旗Lv.11×3","虚空晶片Lv.11×3","紫府琼浆Lv.11×2"]),
    ("阵12","九命续生阵",["阵法图Lv.12×2","阵旗Lv.12×3","九幽玄砂Lv.12×3","九窍玉液Lv.12×2"]),
    ("阵13","瑞兽祥云阵",["阵法图Lv.13×2","阵旗Lv.13×3","太阳精金Lv.13×3","涅槃涎Lv.13×2"]),
    ("阵14","真龙御天阵",["阵法图Lv.14×2","阵旗Lv.14×3","太阴寒核Lv.14×3","龙涎髓Lv.14×2"]),
    ("阵15","凤舞涅槃阵",["阵法图Lv.15×2","阵旗Lv.15×3","星河砂砾Lv.15×3","凤羽凝露Lv.15×2"]),
    ("阵16","混沌归一阵",["阵法图Lv.16×2","阵旗Lv.16×3","鸿蒙金气Lv.16×3","混沌元液Lv.16×2"]),
]

talisman_recipes = [
    ("符01","驱兽符",["兽皮Lv.1×3","粗兽血Lv.1×2","符笔Lv.1×1"]),
    ("符02","避尘符",["兽皮Lv.2×3","灵鹿血Lv.2×2","符笔Lv.1×1"]),
    ("符03","火弹符",["兽皮Lv.3×3","赤狐血Lv.3×2","符笔Lv.2×1","花蜜浆Lv.2×2"]),
    ("符04","金甲符",["兽皮Lv.4×3","金蟾血Lv.4×2","符笔Lv.2×1","根须汁Lv.4×2"]),
    ("符05","冰锥符",["兽皮Lv.5×3","冰蛇血Lv.5×2","符笔Lv.3×1","冰雪露Lv.5×2"]),
    ("符06","炎爆符",["兽皮Lv.6×3","火鸦血Lv.6×2","符笔Lv.3×1","赤阳涎Lv.6×2"]),
    ("符07","青藤符",["兽皮Lv.7×3","青鸾血Lv.7×2","符笔Lv.4×1","青灵浆Lv.7×2"]),
    ("符08","五雷符",["兽皮Lv.8×3","雷鹏血Lv.8×2","符笔Lv.4×1","雷纹液Lv.8×2"]),
    ("符09","地裂符",["兽皮Lv.9×3","地龙血Lv.9×2","符笔Lv.5×1","地脉乳Lv.9×2"]),
    ("符10","星遁符",["兽皮Lv.10×3","星狼血Lv.10×2","符笔Lv.5×1","星辉露Lv.10×2"]),
    ("符11","幻身符",["兽皮Lv.11×3","紫蟾血Lv.11×2","符笔Lv.6×1","紫府琼浆Lv.11×2"]),
    ("符12","续命符",["兽皮Lv.12×3","九命猫血Lv.12×2","符笔Lv.6×1","九窍玉液Lv.12×2"]),
    ("符13","祥瑞符",["兽皮Lv.13×3","麒麟真血Lv.13×2","符笔Lv.7×1","涅槃涎Lv.13×2"]),
    ("符14","龙威符",["兽皮Lv.14×3","龙血Lv.14×2","符笔Lv.7×1","龙涎髓Lv.14×2"]),
    ("符15","涅槃符",["兽皮Lv.15×3","凤血Lv.15×2","符笔Lv.8×1","凤羽凝露Lv.15×2"]),
    ("符16","混沌符",["兽皮Lv.16×3","混沌真血Lv.16×2","符笔Lv.8×1","混沌元液Lv.16×2"]),
]

def build(cat, data):
    result = []
    for code, name, ings in data:
        parsed = []
        for ing in ings:
            p = parse_ing(ing)
            if p: parsed.append(p)
        result.append({
            "id": len(recipes["recipes"]) + len(result) + 1,
            "code": code, "name": name,
            "category": cat, "ingredients": parsed, "extra": "",
        })
    return result

all_new = []
all_new.extend(build("sword", sword_recipes))
all_new.extend(build("array", array_recipes))
all_new.extend(build("talisman", talisman_recipes))

recipes["recipes"].extend(all_new)
for i, r in enumerate(recipes["recipes"]):
    r["id"] = i + 1

with open(BASE / "json_output" / "recipes.json", "w", encoding="utf-8") as f:
    json.dump(recipes, f, ensure_ascii=False, indent=2)

# Report
unresolved = []
for r in all_new:
    for ing in r["ingredients"]:
        if "name" in ing and "id" not in ing and "recipe_code" not in ing:
            unresolved.append(f'{ing["name"]} Lv.{ing.get("level","?")}×{ing["count"]}')

print(f"Added {len(all_new)} recipes")
print(f"Total: {len(recipes['recipes'])}")
if unresolved:
    print(f"Unresolved ({len(unresolved)}):")
    for u in unresolved: print(f"  {u}")
else:
    print("All ingredients resolved!")
