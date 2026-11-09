# AI 圖片生成與後製流程

這份流程適用於任何 AI 繪圖工具（Stable Diffusion／ComfyUI、Midjourney、NovelAI 等）。目標是讓不同角色、不同批次的圖片看起來像同一位畫師畫的，而且每張圖都能追溯到 Character Bible。

---

## 0. 總覽

```
Bible 確認並鎖定 → 參考設定稿 → 本體立繪(body) → 表情補丁(face) → 後製 → 登記為 draft → validate → 審核 → approved
```

| 階段 | 產出 | 狀態 |
|---|---|---|
| 規劃 | manifest 中的 `missing` 項目（`art.sh sync`） | missing |
| 生成＋後製 | 符合規格的 PNG | draft |
| 審核通過 | 同一張 PNG | approved |
| 被取代 | 舊圖保留紀錄 | deprecated |

外觀未確認（`appearance_status: unconfirmed`）的角色，只能做探索草圖（`art.sh prompt <id> --allow-unconfirmed`），草圖**不得**放進 `godot/art/portraits/`，也不得標為 approved。

## 1. 固定的畫風設定

全專案共用 `art_spec.json → style_guide`：

- 日系動畫插畫、高品質視覺小說立繪風格
- 精緻、粗細一致的線稿；柔和賽璐璐上色、左上方暖色主光
- 色彩鮮明但不過度飽和
- 半身（頭頂到大腿上方）、面向鏡頭，可微側
- 透明背景

生成時一律使用工具輸出的 `PROMPT` 與 `NEGATIVE`，不要手打。需要調整畫風時，修改 `style_guide` 後重新產生提示詞，讓所有角色一起變。

同一個專案請固定：

- 同一個模型／checkpoint 與版本（記錄在 manifest 的 `source` 欄位）
- 同一組畫風 LoRA 或風格參考圖與權重
- 同一組取樣器、步數、CFG、解析度

換模型等於換畫師：必須重新檢查所有已完成角色，並在 changelog 記錄。

## 2. 角色一致性

每位角色依序：

1. **參考設定稿**（`ref_<owner>_sheet.png`）：正面全身／半身、服裝細節、配色標記。設定稿確認後登記到 bible 的 `references`，並執行 `art.sh lock <id>`。
2. **一致性輸入**（依工具選擇其一或併用）：
   - 用設定稿訓練角色 LoRA（建議 S 級角色）；
   - 以設定稿作為 IP-Adapter／Reference-only／圖片提示詞輸入；
   - Midjourney 類工具使用 character reference 與固定 seed。
3. **先做 `stand` + 預設服裝的 body**，審核通過後，其他姿勢與服裝都以它為參考（img2img 或 ControlNet 姿勢控制），維持臉型、髮型與比例。

## 3. 生成步驟

### 3.1 本體立繪（body）

```bash
tools/art/art.sh prompt chr_koharu_body_stand_maid
```

- 生成尺寸以 2:3 比例為準（例如 832×1248 或 1024×1536），之後統一放大／裁切到 1024×1536。
- 臉部使用 `neutral` 表情：本體圖本身就是「平常」表情。
- 每個姿勢 × 服裝一張。

### 3.2 表情補丁（face）

```bash
tools/art/art.sh prompt chr_koharu_face_stand_smile
```

- 以**已核准的同姿勢 body** 為底圖，只對臉部區域 inpaint（遮罩涵蓋眉、眼、口、臉頰；瀏海若會因表情改變也要包含）。
- 其他區域不得改變，線條、髮色、膚色要和底圖完全一致。
- 輸出時保留完整畫布 1024×1536，臉部區域以外全部透明（見 4.4）。

### 3.3 整張差分（full，可選）

表情牽動整個身體（例如大笑時聳肩、哭泣時用手擦眼淚）時，改做整張 `chr_<owner>_full_<pose>_<outfit>_<expression>.png`，系統會優先使用它。

### 3.4 CG 與背景

- 背景：1920×1080，不得出現人物（提示詞已自動加入負面詞）。
- CG：依事件劇本構圖，畫面中每位角色都要貼上其 bible 的角色描述與參考圖。

## 4. 後製

### 4.1 去背

- 使用去背工具（例如 rembg／BiRefNet）或在生成時直接輸出透明背景。
- 手動檢查頭髮邊緣、手指縫隙；去除白邊（edge defringe 1–2 px）。
- 半透明物件（蕾絲、眼鏡）保留適當透明度。

### 4.2 對齊畫布

畫布 1024×1536，參考線（`art_spec.json → canvases.portrait.guides`，比例為畫布高度）：

| 參考線 | 位置 |
|---|---|
| 中心線 | x = 0.5 |
| 標準身高角色的頭頂 | y ≈ 0.06 |
| 標準身高角色的眼睛 | y ≈ 0.20 |
| 標準身高角色的下巴 | y ≈ 0.29 |
| 畫布底部 | 大腿上方 |
| 左右最小留白 | 0.06 |

所有角色使用**同一個像素比例**：較高的角色頭頂比參考線高，較矮的角色比參考線低，不要把每個人都縮放到一樣高。同一角色所有 body 的頭部位置必須一致，表情補丁才能直接疊上。

### 4.3 色彩檢查

- 用取色器對照 bible 的 `signature_colors`、髮色、瞳色。
- 飽和度過高時整體降低，避免螢光色。
- 同一角色的所有圖片髮色與膚色必須一致（可用調整圖層統一後再輸出）。

### 4.4 製作 face 補丁

1. 在影像軟體中把 inpaint 後的整張圖疊在 body 上。
2. 建立只包含臉部變化區域的遮罩，邊緣羽化 2–4 px。
3. 隱藏 body，只輸出遮罩內容，畫布維持 1024×1536，其餘全透明。
4. 疊回 body 檢查邊緣沒有接縫。

### 4.5 輸出

- PNG、RGBA、8 bit、sRGB。
- 檔名與資料夾完全依照 manifest 的 `path`。
- 不要把 JPEG 改副檔名成 .png（工具會檢查檔案簽章）。

## 5. 審核清單

登記為 `draft` 並執行 `tools/art/art.sh validate` 無錯誤後，逐項對照：

- [ ] 外貌與 bible 完全一致：髮型、髮色、瞳色、身形、服裝、配件、代表色
- [ ] 與參考設定稿是同一個人（臉型、眼型、比例）
- [ ] 與其他已核准角色並排時畫風一致（線條粗細、上色方式、光源方向）
- [ ] 手指、飾品、服裝結構沒有 AI 常見錯誤
- [ ] 去背乾淨，沒有白邊、殘留背景、多餘透明洞
- [ ] 對齊參考線；同角色不同 body 疊在一起時頭部位置相同
- [ ] face 補丁疊上 body 沒有接縫或色差
- [ ] 在 `portrait_demo.tscn` 中實際顯示正常（大小、位置、淡入淡出）
- [ ] manifest 已填寫 `source`（工具、模型、日期），必要時填寫 `prompt` 或 seed

全部通過才把 `status` 改為 `approved`，然後執行 `tools/art/art.sh status` 更新進度表。

## 6. 修改已核准的圖片

- 小修（去背、色偏）：直接覆蓋檔案，重新跑審核清單。
- 外觀變更：必須先修改 bible、取得確認並重新 `lock`，再重新生成所有受影響的圖片；舊圖可標記為 `deprecated` 保留紀錄。

## 7. 紀錄與來源

建議在 manifest 項目中加入：

```json
{ "id": "chr_koharu_body_stand_maid", "...": "...", "status": "approved",
  "source": "ComfyUI / <checkpoint 名稱與版本> / koharu-lora-v2 / 2026-11-20",
  "note": "審核：luz 2026-11-21" }
```

這些欄位不影響遊戲，但能在日後換模型、追查授權或重做時找回每張圖的來源。請確認所使用的模型與素材授權允許商業使用。
