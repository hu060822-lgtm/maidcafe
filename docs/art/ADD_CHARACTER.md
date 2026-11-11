# 新增角色教學

以新增一位女僕「美月」（ID：`mizuki`，Tier S）為例。整個流程不需要修改任何程式碼。

指令以 macOS/Linux 為例；Windows 把 `tools/art/art.sh` 換成 `tools\art\art.cmd`。若 `godot` 不在 PATH，先設定 `GODOT` 環境變數指向 Godot 4.3。

> 不想用指令？[創作者工作坊](CREATOR_WORKSHOP.md) 可以用按鈕完成第 2、3、5、6、7 步（新增角色、填寫與鎖定外觀、畫出或匯入圖片、標為完成）。

---

## 第 1 步：決定角色 ID 與分級

- 角色 ID 必須和遊戲資料（`godot/scripts/core/data.gd`）中的 ID 相同，只用小寫英文、數字、底線。
- 分級：S（核心）、A（次要固定）、B（一般顧客），規格見 [ART_SYSTEM.md 第 3 節](ART_SYSTEM.md#3-角色分級tier)。

## 第 2 步：建立空白 bible

```bash
tools/art/art.sh new-character mizuki S 美月 --role=maid
```

這會建立 `godot/art/characters/mizuki/bible.json`（外貌全部是 `TBD`），並登記到 `characters/index.json`。

接著把個性資料填進 `personality`（可直接從遊戲資料複製 intro、traits、台詞）。

## 第 3 步：確認外觀並鎖定

1. 和美術總監確認外貌，填寫 `appearance` 的每一個欄位，不可留下 `TBD`：
   - `summary` 一句話描述、`age_look`、`hair.style` / `hair.color`、`eyes.color`
   - `body.height_cm` / `body.build` / `body.proportion_note`
   - `outfits.<服裝ID>.design`（每套服裝一段描述）
   - `accessories`、`signature_colors`（2–4 個色碼或顏色名稱）、`expression_traits`
2. 準備至少一張角色視覺參考圖（例如角色設定稿），存成 `godot/art/characters/mizuki/reference/ref_mizuki_sheet.png`，並登記：
   ```json
   "references": [ { "path": "characters/mizuki/reference/ref_mizuki_sheet.png", "note": "正面設定稿 v1" } ]
   ```
3. 鎖定：
   ```bash
   tools/art/art.sh lock mizuki --note="外觀第一版確認"
   ```
   之後若有人修改 `appearance`，`validate` 會出現 `E_LOCK_CHANGED`。真的要改外觀時，必須取得確認、修改、再執行一次 `lock`（修訂號會加一，並寫入 changelog）。

## 第 4 步：調整差分清單（可選）

`art` 區塊預設帶入該 Tier 的表情、姿勢、服裝。需要時可以修改：

```json
"art": {
  "owner": "mizuki",
  "expressions": ["neutral", "smile", "laugh", "surprised", "embarrassed", "sad", "angry", "tired", "thinking"],
  "poses": ["stand", "greet", "serve"],
  "outfits": ["maid", "casual", "event"],
  "default": { "pose": "stand", "outfit": "maid", "expression": "neutral" },
  "cg": ["mizuki-story-01"],
  "display": { "scale": 1.0, "y_offset": 0.0 }
}
```

- 只能使用 `art_spec.json → vocab` 中的 ID；需要新的表情或姿勢時，先在 vocab 新增並寫好 `prompt`。
- `display.scale` 用來微調顯示大小（例如 0.95），`y_offset` 是舞台高度的比例。

## 第 5 步：把需要的素材登記到 manifest

```bash
tools/art/art.sh sync
tools/art/art.sh validate
```

`sync` 會依 bible 自動加入所有需要的圖片（狀態 `missing`）。`validate` 應該是 0 錯誤，並列出 mizuki 缺少的素材。此時遊戲已經可以使用這位角色，只是畫面上顯示的是帶有 `[MISSING ART]` 標籤的剪影。

## 第 6 步：產生圖片

依 [AI_WORKFLOW.md](AI_WORKFLOW.md) 產生並後製。每張圖的提示詞用工具產生：

```bash
tools/art/art.sh prompt chr_mizuki_body_stand_maid
tools/art/art.sh prompt chr_mizuki_face_stand_smile
```

輸出的檔案直接存到 manifest 指定的路徑，例如 `godot/art/portraits/mizuki/chr_mizuki_body_stand_maid.png`。

## 第 7 步：登記、檢查、審核

1. 把 manifest 中該圖片的 `status` 從 `missing` 改成 `draft`（或執行 `tools/art/art.sh sync --register-found`）。
2. `tools/art/art.sh validate`，修正所有錯誤（尺寸、透明背景、命名……）。
3. 打開 `godot/scripts/art/demo/portrait_demo.tscn` 實際看效果（1–8 切表情、P 切姿勢、O 切服裝、Tab 換人）。
4. 依 [AI_WORKFLOW.md 第 5 節](AI_WORKFLOW.md#5-審核清單) 對照 bible 審核，通過後把 `status` 改成 `approved`。
5. `tools/art/art.sh status` 更新進度表。

## 第 8 步：在遊戲中使用

```gdscript
stage.show_character("mizuki", {"position": "center", "expression": "smile"})
```

---

## 新增路人 NPC 外觀

1. 在 `godot/art/npc/archetypes.json` 的原型中加入一個 look，或新增原型（ID 以 `npc-` 開頭）：
   ```json
   { "id": "look-04", "hair_style": "braid", "hair_color": "brown", "outfit": "cardigan", "accessories": ["glasses"] }
   ```
   所有值必須來自 `npc/taxonomy.json`。
2. `tools/art/art.sh validate`：檢查相容規則與相似度。
3. `tools/art/art.sh sync`，接著照第 6–7 步製作 `chr_<原型>_body_stand_look-04.png`。
4. 具名顧客也可以改用原型素材：在 bible 中設定 `"art": { "owner": "npc-office-m", "default": { "outfit": "look-02" } }`。

## 新增背景、CG、UI

- 背景：在 `art_spec.json → backgrounds_required` 加入地點與時段，執行 `sync`。
- CG：在角色 bible 的 `art.cg` 加入事件 ID（例如 `mizuki-story-02`），執行 `sync`。
- UI：在 `manifest.json` 手動加入一筆，例如：
  ```json
  { "id": "ui_icon_heart", "kind": "ui", "group": "icon", "name": "heart", "path": "ui/ui_icon_heart.png", "status": "missing", "width": 64, "height": 64 }
  ```
