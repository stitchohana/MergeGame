# Recipe subset cleanup implementation plan

**Goal:** Remove ingredient containment between recipes and ambiguous identical combinations on the same crafting table.

**Architecture:** Replace one ordinary ingredient per affected recipe with an ordinary item at the same level, using only existing material production families. Preserve products, ingredient counts, product levels and craft times. Validate strict subsets across the complete recipe table; allow identical combinations only on different crafting tables.

**Tech Stack:** JSON, XLSX, Artifact Tool, Python configuration converters, TypeScript game engine.

1. Audit all 259 recipes, generate a replacement plan, and add shared validation to both conversion directions. Cover subset ordering, cross-table subsets, and same-table identical combinations in validation checks.
2. Author targeted ingredient cells in recipes.xlsx and synchronize recipes.json. Preserve unrelated workbook cells/styles and all other recipe fields. Verify the XLSX-to-JSON conversion in a disposable copy.
3. Exercise all recipes through actual server material insertion and recipe matching, including reversed material insertion order. Confirm no recipe matches before its final ingredient, all expected products match, and existing recipe/order smoke checks pass.
