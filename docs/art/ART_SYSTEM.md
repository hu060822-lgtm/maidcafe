# 美術系統架構（Godot 4.3）

本文件說明 Maiden Parade 的美術資產系統：資料怎麼放、圖片怎麼命名、遊戲怎麼載入、缺圖時會怎樣，以及如何檢查整個素材庫。

相關文件：

- [新增角色教學](ADD_CHARACTER.md)
- [AI 圖片生成與後製流程](AI_WORKFLOW.md)
- [素材進度表](ASSET_STATUS.md)（由工具自動產生）

---

## 1. 設計原則

1. **資料驅動。** 角色、差分、NPC 原型、命名規則、尺寸規格全部寫在 JSON。新增 20 名角色只需要新增 20 份 bible，不需要改任何程式。
2. **Character Bible 是唯一依據。** AI 提示詞由 bible 自動產生；外觀未確認的角色只能產生「探索用」草圖，工具會擋下正式生成。外觀確認後會鎖定（hash），之後任何修改都會讓檢查失敗。
3. **不假裝完成。** 沒有圖的素材在 manifest 中標記為 `missing`；遊戲顯示的是灰色剪影加上 `[MISSING ART]` 標籤，不會出現看起來像完成品的佔位圖。佔位圖不能被標為 `approved`，全空白或單色圖片會被檢查工具判定為錯誤。
4. **永不因缺圖崩潰。** 找不到圖片、圖片損壞、角色 ID 不存在，都只會降級顯示並記錄警告。
5. **與遊戲內容解耦。** 美術系統只認「角色 ID」。遊戲邏輯（`godot/scripts/core/**`）不需要知道檔名或圖層。

## 2. 檔案位置

```
godot/
  art/                              ← 所有美術資料與圖片（res://art/）
    art_spec.json                   ← 全域規格：畫風、命名、尺寸、差分詞彙、Tier、備援規則
    manifest.json                   ← 素材清單：每張圖一筆（狀態 missing / draft / approved / deprecated）
    characters/
      index.json                    ← 角色索引
      <角色ID>/bible.json           ← Character Bible
      <角色ID>/reference/ref_*.png  ← 角色視覺參考圖（登記在 bible.references）
    portraits/<owner>/chr_*.png     ← 立繪圖層
    cg/cg_*.png                     ← 劇情 CG
    backgrounds/bg_*.png            ← 背景
    ui/ui_*.png                     ← UI 圖片
    npc/taxonomy.json               ← 顧客 NPC 美術分類與相容規則
    npc/archetypes.json             ← 共用素材的 NPC 原型與外觀組合
  scripts/art/
    art_catalog.gd                  ← ArtCatalog：讀取資料、解析檔名、決定要顯示哪些圖層
    portrait_textures.gd            ← PortraitTextures：安全載入貼圖、產生缺圖剪影
    portrait_slot.gd                ← PortraitSlot：單一角色（圖層、尺寸、淡入淡出、登場退場）
    portrait_stage.gd               ← PortraitStage：多角色立繪舞台（對外 API）
    npc_art_catalog.gd              ← NpcArtCatalog：NPC 外觀相容檢查與挑選
    art_validator.gd                ← ArtValidator：素材檢查
    art_prompt_builder.gd           ← ArtPromptBuilder：由 bible 產生 AI 提示詞
    tools/art_cli.gd                ← 命令列工具
    tests/run_art_tests.gd          ← 自動測試
    demo/portrait_demo.tscn         ← 立繪系統測試場景（可用鍵盤切換差分）
tools/art/art.sh, art.cmd           ← 命令列包裝（macOS/Linux、Windows）
docs/art/                           ← 本文件與進度表
```

## 3. 角色分級（Tier）

規格寫在 `art_spec.json → tiers`，檢查工具會依此驗證每份 bible。

| Tier | 用途 | 表情 | 姿勢 | 服裝 | 劇情 CG |
|---|---|---|---|---|---|
| S 核心角色 | 女僕 | ≥ 8 | ≥ 3 | ≥ 2 | ≥ 1 |
| A 次要固定角色 | 熟客、特殊客人、街區居民 | ≥ 4 | 1–2 | ≥ 1 | 視需要 |
| B 一般顧客 NPC | 一般客人 | ≥ 2 | 1 | 1 | – |

目前的分級是**提案**（每份 bible 的 `tier_confirmed: false`）：

- S：小春、凜、雫、雪乃、楓
- A：早瀨、高木爺爺、小林真由、遠藤、千鶴奶奶、雨宮、白石、山田大叔、砂原、月見、奏、鶴見
- B：佐倉、大塚、美咲、健太、橘太太、秋子阿姨、七海、森下、小陸、春日先生、春日太太

## 4. Character Bible

每位角色一份 `godot/art/characters/<id>/bible.json`。主要欄位：

| 欄位 | 說明 |
|---|---|
| `id` / `name` / `role` / `tier` | 角色 ID（與遊戲資料相同）、姓名、身分、分級 |
| `appearance` | 外貌：概要、年齡感、髮型與髮色、瞳色、身形比例、各套服裝設計、配件、代表色、表情特徵 |
| `appearance_status` | `unconfirmed` 或 `confirmed`。只有確認後才能正式生成 |
| `appearance_lock_hash` | 確認時自動寫入；外貌被改動時檢查會失敗 |
| `personality` | 個性（取自遊戲資料，非外貌） |
| `art` | 美術規格：`owner`（檔名用 ID）、表情／姿勢／服裝清單、預設差分、CG、顯示縮放 |
| `art.npc_tags` | 顧客的分類標籤（年齡感、顧客類型、個性），由遊戲中的文字描述推得 |
| `references` | 角色視覺參考圖（`characters/<id>/reference/ref_<owner>_<name>.png`） |
| `prototype_hints` | 3D 佔位模型的顏色，**僅供參考，不是美術設定** |
| `open_questions` | 尚待美術總監／你確認的事項 |
| `changelog` | 修訂紀錄 |

> 所有角色的外貌目前都是 `TBD`。系統不會自行猜測外觀；請依 [新增角色教學](ADD_CHARACTER.md) 第 3 步填寫並鎖定。

## 5. 命名規範

ID 片段只能用小寫英文、數字與連字號（`kasuga-m`），底線 `_` 保留作為檔名分隔符。遊戲 ID 若含底線（例如 `kasuga_m`），bible 中的 `art.owner` 會轉成 `kasuga-m`。

| 種類 | 檔名 | 資料夾 | 尺寸 |
|---|---|---|---|
| 立繪本體 | `chr_{owner}_body_{pose}_{outfit}.png` | `portraits/{owner}/` | 1024×1536，透明背景 |
| 表情差分 | `chr_{owner}_face_{pose}_{expression}.png` | `portraits/{owner}/` | 1024×1536，透明背景 |
| 完整單張 | `chr_{owner}_full_{pose}_{outfit}_{expression}.png` | `portraits/{owner}/` | 1024×1536，透明背景 |
| 劇情 CG | `cg_{event}_{variant}.png` | `cg/` | 1920×1080 |
| 背景 | `bg_{location}_{time}.png` | `backgrounds/` | 1920×1080 |
| UI | `ui_{group}_{name}.png` | `ui/` | 不限（可在 manifest 指定） |
| 參考圖 | `ref_{owner}_{name}.png` | `characters/{id}/reference/` | ≥ 512×512 |

Manifest 的 `id` 一律等於檔名（不含副檔名）。檔名、資料夾與欄位不一致時，檢查工具會報錯並給出正確路徑。

### 差分詞彙

`art_spec.json → vocab` 定義所有可用 ID，程式、提示詞與檔名共用同一套：

- 表情：`neutral` 平常、`smile` 微笑、`laugh` 開心大笑、`surprised` 驚訝、`embarrassed` 害羞、`sad` 難過、`angry` 生氣、`tired` 疲累、`troubled` 困擾、`thinking` 思考、`serious` 認真、`apologetic` 道歉
- 姿勢：`stand` 站姿、`greet` 迎賓、`serve` 端盤、`point` 指示、`sit` 坐姿
- 服裝：`maid` 女僕制服、`casual` 便服、`event` 活動服裝、`default` 預設服裝

可以新增 ID；已在使用的 ID 不要改名。

## 6. 立繪的圖層模型

所有立繪圖層使用**同一張畫布（1024×1536）**，因此直接疊合，不需要任何座標偏移。

- **body**（姿勢 × 服裝）：完整的半身立繪，臉部是預設的 `neutral` 表情。
- **face**（姿勢 × 表情）：只有臉部區域的補丁，其他區域透明，疊在 body 上。`neutral` 不需要 face 圖。
- **full**（姿勢 × 服裝 × 表情）：可選的整張圖，存在時優先使用（例如表情動作很大、無法只換臉的情況）。

S 級角色預設需求：3 姿勢 × 2 服裝 = 6 張 body，3 姿勢 × 7 表情 = 21 張 face，加 1 張 CG，共 28 張，而不是 3×2×8 = 48 張整圖。

## 7. 遊戲整合：PortraitStage

`PortraitStage` 是一個可重複使用的 Control，任何對話框、事件或選單都可以加入它，然後只用角色 ID 操作：

```gdscript
var stage := PortraitStage.new()
$UI.add_child(stage)                              # 會自動填滿父節點

stage.show_character("koharu", {"position": "left", "expression": "smile"})
stage.show_character("rin", {"position": "right", "enter": "slide_right"})
stage.set_speaker("koharu")                       # 說話者正常亮度，其他人變暗
stage.set_expression("rin", "surprised")          # 表情交叉淡入
stage.set_pose("koharu", "serve")
stage.set_outfit("koharu", "casual")
stage.move_character("rin", "center")
stage.hide_character("rin", {"exit": "fade"})
stage.clear()
```

| 需求 | 實作 |
|---|---|
| 依角色 ID 載入 | `show_character(id)`；ID 來自 bible，不需要知道檔名 |
| 依表情／姿勢／服裝 ID 切換 | `set_expression` / `set_pose` / `set_outfit` / `set_variant`，切換時交叉淡入 |
| 自動處理尺寸與位置 | 依畫布比例縮放到舞台高度 × `height_ratio`，底部對齊；bible 的 `display.scale` / `y_offset` 處理身高差；視窗大小改變時自動重新排版 |
| 淡入淡出、登場退場 | `enter` / `exit`：`fade`、`slide_left`、`slide_right`、`rise`、`none` |
| 多角色同時出現 | 具名位置（`far_left`、`left`、`center_left`、`center`、`center_right`、`right`、`far_right`）、0–1 的數值，或 `auto` 自動平均分配 |
| 同一素材出現多次 | `{"key": "crowd1"}`（例如多位共用原型的路人顧客） |
| 缺素材時使用預設圖片 | 依 `art_spec.fallback` 依序退回：預設表情 → 預設服裝 → 預設姿勢 → 灰色剪影 |
| 不因缺圖崩潰 | 找不到檔案、檔案損壞、未知角色 ID 都只顯示剪影並 `push_warning` |

另一個執行緒的夜間事件與日常小事件已帶有 `who` 角色 ID 陣列，之後可以直接把它們接到 `PortraitStage.show_character`。

`ArtCatalog.shared().allow_draft` 預設為 `true`（開發中也顯示草稿圖）；正式版可設為 `false`，只顯示 `approved` 素材。

### 貼圖載入

`PortraitTextures.load_texture()` 先走 Godot 匯入系統；如果是剛放進資料夾、編輯器還沒匯入的 PNG，會直接從檔案讀取。匯出正式版前請在編輯器打開一次專案，讓所有 PNG 被匯入。

## 8. 顧客 NPC 美術系統

具名顧客（佐倉、大塚……）各有自己的 bible。若之後要加入大量無名路人顧客，使用 NPC 原型系統：

- `npc/taxonomy.json` 定義分類維度：年齡感、體型、髮型、髮色、服裝、配件、個性、顧客類型。
- `npc/archetypes.json` 定義原型（例如 `npc-office-m`）。每個原型有一組共用的表情 face 補丁，以及多個 **look**（髮型＋髮色＋服裝＋配件的組合）。
- **每個 look 是一張事先畫好、檢查過的完整 body 圖**，在立繪系統中當作「服裝」使用：`chr_npc-office-m_body_stand_look-02.png`。

防止不相容與過度重複：

1. 遊戲運行時**不會**拼接頭和身體。唯一的疊圖是該原型自己的 face 補丁，且原型的 face 只畫眼、眉、口，確保適用於該原型所有 look。
2. 相容規則（例如「學生制服只限高中生年紀」「拐杖只限長者」）由檢查工具與 `NpcArtCatalog` 同時執行，不合規則的 look 永遠不會被選中。
3. 同一原型的兩個 look 至少要有 2 項可見特徵不同（髮型、髮色、服裝、配件），否則檢查工具會警告。
4. `NpcArtCatalog.pick_look()` 只從有圖可用的 look 中挑選，不會讓同一個 look 同時出現在畫面上，並避開最近使用過的 look。

目前 4 個原型（女高中生、男上班族、女大學生、長者）都是**提案**，尚未經過美術總監核准。

## 9. 素材檢查工具

```bash
tools/art/art.sh validate                 # 一般檢查（缺圖不算失敗）
tools/art/art.sh validate --show-missing  # 列出所有缺少的素材
tools/art/art.sh validate --strict        # 警告也算失敗
tools/art/art.sh validate --complete      # 發佈前：任何缺圖都算失敗
tools/art/art.sh validate --json=report.json
```

（Windows 用 `tools\art\art.cmd validate`。若 `godot` 不在 PATH，先設定環境變數 `GODOT` 為 Godot 4.3 執行檔路徑。）

| 檢查項目 | 代碼 |
|---|---|
| 圖片是否存在（`draft`/`approved` 但沒有檔案） | `E_FILE_MISSING` |
| 圖片格式（PNG 簽章、能否解碼、只允許 .png） | `E_FORMAT` |
| 圖片尺寸是否符合規格 | `E_SIZE` |
| 立繪是否有透明背景 | `E_ALPHA` |
| 全透明或單色圖片（佔位圖） | `E_BLANK` |
| 佔位圖被標成 approved | `E_PLACEHOLDER_APPROVED` |
| bible 需要但 manifest 沒有登記的素材 | `E_REQUIRED_UNREGISTERED` |
| 缺漏素材（已規劃、尚未製作） | `M_MISSING` |
| 重複 ID、重複路徑、內容完全相同的圖片 | `E_DUP_ID` / `E_DUP_PATH` / `E_DUP_CONTENT` |
| 錯誤路徑或不符命名規範 | `E_NAMING` / `E_BAD_PATH` |
| 資料夾中有未登記的圖片 | `E_UNREGISTERED_FILE` |
| Tier 最低數量、詞彙、預設差分 | `E_TIER_MIN` / `E_VOCAB` / `E_DEFAULT` |
| 已確認的外貌被修改 | `E_LOCK_CHANGED` |
| NPC look 違反相容規則／過於相似 | `E_NPC_RULE` / `W_NPC_SIMILAR` |

其他指令：

```bash
tools/art/art.sh sync                     # 把 bible 需要的素材補進 manifest（status: missing）
tools/art/art.sh sync --register-found    # 也把資料夾中命名正確的新圖登記為 draft
tools/art/art.sh status                   # 重新產生 docs/art/ASSET_STATUS.md
tools/art/art.sh prompt chr_koharu_body_stand_maid
tools/art/art.sh new-character <id> <S|A|B> <名字>
tools/art/art.sh lock <id>
tools/art/art.sh test                     # 執行自動測試
```

## 10. 待你確認的事項

1. 所有 28 位角色的外貌（髮型、髮色、瞳色、身形、服裝、配件、代表色、表情特徵）與參考圖。
2. 各角色的 Tier 分級（第 3 節）。
3. S 級的姿勢（站姿／迎賓／端盤）與服裝（女僕制服／便服）清單。
4. 4 個 NPC 原型與其 look 組合是否採用。
5. 使用哪一套 AI 生成工具（影響 [AI_WORKFLOW.md](AI_WORKFLOW.md) 第 2 節的一致性做法）。
