# 肉身聖典 THE SCRIPTURE OF FLESH

2.5D 日式黑暗奇幻 RPG。Godot **4.3** / GDScript，目標平台 PC。

> 目前階段：**M7 序章（垂直切片）＋ 美術方向測試**。主場景是主選單：新遊戲／繼續／戰鬥沙盒／離開。
> 角色、敵人、Boss 與武器是程序生成的低多邊形模型（M10），動畫是程序生成的關鍵格（M9）。關卡仍是【暫代】灰盒。

## 美術測試場景（主選單 → 美術測試）

依美術指導（PS1 復古恐怖／低多邊形哥德身體恐怖）建立的方向確認場景，可實際遊玩，**確認方向前不量產正式資產**。

- 低解析度算圖：3D 畫在 360p（F2 可切 240p／480p）的 SubViewport，點取樣放大；UI 保持清晰。
- `art/ps1/ps1_spatial.gdshader`：頂點吸附（有限抖動）、點取樣低解析度貼圖、無鏡面反射、弱點自發光。
- `art/ps1/ps1_post.gdshader`：色階量化＋4×4 Bayer 抖色，只套在 3D 畫面。
- `PS1Style`：色盤（骨瓷白、乾涸紅、煤灰黑、陳舊金、奶油黃、灰粉色）、程序生成的 32–64px 測試貼圖、`stylize()` 把暫代生物低多邊形化（不改斷肢命名慣例）、組合式手臂（上臂／手肘／前臂／手掌／手指，斷臂時整隻飛出）、斷面（皮膚環＋肉＋突出的骨頭）。
- `GothicOperatingRoom`：奶油黃與灰粉色磁磚、骨瓷白石牆、尖拱彩繪玻璃、六角柱與肋拱、手術燈、標本櫃、燭台；只有排水溝與束帶是紅色（以反差製造恐怖）。
- `FixedCamera`：固定位置，只在 8° 內追蹤玩家。
- 按鍵：F1 效果開關（對照）、F2 解析度、F3 抖色、F4 頂點抖動、F5 重置、F6 敵人 AI、Esc 主選單。
- 截圖：`xvfb-run -s "-screen 0 1280x720x24" godot --rendering-driver opengl3 --path . -s tests/sim/art_shots.gd -- <資料夾>`

## 聲音（A1：架構）

- `AudioManager`（autoload）：匯流排 Master ← Music／Ambience／SFX／UI／Voice（SFX 與 Ambience 預留低通濾波，A4 低血量悶聲用；Master 有限幅器）。
  `play(cue_id, at)` 會隨機選變體與音高，並處理冷卻、同一 cue 的發聲上限，以及 3D 定位。
- `SoundCatalog`：cue 定義表。音檔放到 `audio/sfx/<cue_id>/` 就會自動載入，不需要改程式。**目前還沒有音檔**，所有 cue 都是【暫代】靜音。
- `AudioDirector`：監聽場景樹，自動接上戰鬥、解剖、Boss、縫合、移植、祭壇、拾取、門、按鈕的 signal，不必修改那些系統。腳步聲依移動距離觸發。
  音樂狀態依序判斷：結局 > 死亡 > Boss（boss_1／boss_2）> 戰鬥 > 緊張 > 探索 > 主選單。戰鬥結束後戰鬥音樂會再維持 4 秒。
- `MusicMixer`（A3）：10 個同長的 stem 同時循環，依音樂狀態淡入淡出（`MIXES` 表）。
  探索時是走音的八音盒搖籃曲；緊張時搖籃曲退遠，低鳴與倒放人聲浮上來；戰鬥時只剩心跳與悶擊。
  Boss 戰時母親哼同一首搖籃曲，跪伏後哼唱崩壞。死亡時音樂抽空，只留一聲低鳴；離院結局是同一首曲子的大調版本。
- `AmbiencePlayer`（A3）：房間環境音交叉淡變，依玩家離最近的區域觸發點決定（【暫代】近似）。
- `PsycheAudio`（A4，只作用在玩家身上）：
  - HP 降到 30% 以下時，音效與環境音逐漸變悶，5% 時最悶（低通 600 Hz）。
  - 自己的肢體被斷時會耳鳴，世界另外變悶 3 秒。
  - 異化 ≥ 25 時，身邊會出現聽不清楚的低語：異化 25 時約每 36 秒一次，100 時約每 8 秒一次，而且越來越大聲。
- 重新產生音樂：`python3 tools/music_synth/generate_music.py`（需要 numpy；有 ffmpeg 時輸出 .ogg）。
- 主選單 →「聲音設定」：六條音量滑桿，設定存在 `user://settings.cfg`。
- 素材來源與授權見 `audio/SOURCES.md`。

## 序章流程

白色產房醒來（赤手）→ 與助產修女阿格妮絲對話，以「手還記得什麼」選擇職業（取得職業武器與縫合包）
→ 縫合迴廊（縫屍者 ×2）→ 反足者庭院（反足者 ×2、縫屍者、骨鋸斧台座、祭壇）
→ 西：觀察者藏書室（無面觀察者 ×2、解剖刺劍台座）／東：多手人聖器室（多手人、聖骸錘台座、**臍帶鑰匙**）
→ 以鑰匙打開禮拜堂大門 → 前廳（祭壇）→ 母親的禮拜堂（Boss）→ 胎房（結局選擇）。

- **存檔**：在縫合祭壇休息時存檔（`user://save_0.json`，有版本號與遷移表）。存身體（含斷肢、移植器官）、資源、武器、等級、異化、物品、旗標、已擊殺敵人、已拿取物品、檢查點。
- **死亡**：3 秒後在最後休息的祭壇重生，世界回到存檔當時（存檔後擊殺的敵人與拿取的物品會復原；Boss 也會復原）。
- **Boss 行走的母親**：四根高蹺腿、三條臍帶、骨盆甲包覆的子宮、兩條抱臂、兩條長臂、覆面頭。
  - 第一階段：子宮護甲 10，只能先打腿與臍帶。
  - 高蹺腿剩 2 根以下 → **跪伏**：身體降低、骨盆甲剝落（子宮換成暴露定義，保留受損比例）、產聲、移動變慢。
  - 臍帶還連著時每 9 秒生出「未生者」（最多 2 隻）；三條臍帶全斷後不再召喚。
  - 攻擊依身體自動增減：踐踏需 2 根高蹺、懷抱擠壓需雙抱臂、鞭笞需長臂、產聲需頭部。
- **結局**（胎房對話，依異化度與旗標）：
  - 灰燼結局：燒掉胎房（永遠可選）。
  - 母親結局：異化 ≥ 50 才出現。
  - 離院結局：曾答應帶阿格妮絲離開、異化 < 75，且沒有在她面前保持沉默。
- 阿格妮絲的對話會依異化度（≥75 害怕你）、是否持有鑰匙、Boss 是否死亡而改變。
- Esc 按兩次回主選單；B 身體選單；其他操作同戰鬥沙盒。

## 執行測試

```bash
GODOT=/path/to/godot tests/run_tests.sh
```

`run_tests.sh` 會先匯入專案，再執行 `tests/run_tests.gd`，並在輸出出現 `SCRIPT ERROR` 時判定失敗
（GDScript 執行期錯誤只會中止單一函式，否則可能造成「假通過」）。
headless 模式下會出現大量 `Parameter "m" is null`（mesh_storage）訊息，這是 Godot 4.3 dummy 渲染器的已知雜訊，不影響結果。

## 戰鬥沙盒（主選單 → 戰鬥沙盒，F5 重置）

WASD 移動、滑鼠瞄準、左鍵普通攻擊、右鍵特殊技（消耗 AP）、Space 閃避、Shift 防禦、
1/2/3 換武器（骨鋸斧／聖骸錘［雙手］／解剖刺劍）、E 撿起掉落的武器、F5 重置、F6 敵人 AI 開關。

**身體成長**：E 在祭壇休息（完整修復含斷肢）／摘取屍體器官、T 在祭壇移植器官、F 緊急縫合（消耗縫合包，2.5 秒，被打中斷，異化 +6）、B 身體選單（屬性、技能、異化、部位、物品）。

| 系統 | 內容 |
| --- | --- |
| 職業（起點） | 解剖師、義體騎士、肉巫、刑體師、縫合者；只決定起始屬性／武器／技能，之後自由分配 |
| 屬性 | STR、DEX、VIT、PER、WIL、TEC，影響 HP/ST/AP、武器傷害、異化抗性、器官相容性 |
| 技能樹 | 8 個技能，含前置條件 |
| 武器熟練度 | 依武器類型累積，每級 +4% 傷害 |
| 異化 0–100 | 25 異樣感知（戰術介面看見內臟與敵人剩餘攻擊）／50 骨刺增生（新攻擊、體力，但祭壇治療會加速異化）／75 肉身自律（部位再生）；各階段設定劇情旗標 |
| 器官 | 縫屍者的手臂、反足（獲得飛踢）、觀察者之眼、多手人的心臟（出血減緩）、鐵製義肢（需 TEC 12，不排斥、不異化）。相容性擲骰失敗會排斥：部位壞死並額外異化 |

**戰術介面（Tab）**：戰鬥減速到 10%（P 切換完全暫停）。自動選最近的敵人，點擊部位或 Q／R 切換部位，
右側面板顯示每個部位的 HP、狀態、護甲，以及普通攻擊打在指定部位的預估傷害與斷肢機率。
指定部位的攻擊每次消耗 10 AP（AP 靠命中累積），AP 不足時自動改為依攻擊方向選部位。
關閉介面後鎖定仍保留，直到目標死亡或部位斷離。

| 敵人 | 解剖特徵 | 斷肢後的行為變化 |
| --- | --- | --- |
| 縫屍者 | 縫合人形，四肢易斷，胸口縫合皮甲 | 會走去撿自己的斷肢並花 2.5 秒縫回去，期間被打中就中斷 |
| 反足者 | 反折雙腿（leap 能力），腿硬 | 少一條腿就不能飛撲，雙腿都沒了改為爬行撲咬 |
| 無面觀察者 | 無頭，四根眼柄提供視覺，遠距凝視（灼傷＋異化） | 眼柄越少看得越近；全滅後失明，只能靠聽覺，改用長臂近戰 |
| 多手人 | 六臂 | 四臂以上用千手亂擊，剩兩臂用擒抓，剩一臂單手揮擊，沒有手就咬 |

## 斷肢沙盒（目視確認）

在編輯器開啟 `scenes/sandbox/dismemberment_sandbox.tscn` 後按 F6 執行。
左邊是人形（縫屍者暫代），右邊是多手人。1／2／3 切換斧／錘／刺劍，左鍵攻擊點到的部位，Shift+左鍵必定斷肢，R 重置。

在 Godot 編輯器中也可以直接以 `tests/run_tests.gd` 執行（File → Run）。

## 架構

三層分離：**Resource（靜態資料）／RefCounted（戰鬥即時狀態）／Node（表現）**。

| 資料夾 | 內容 |
| --- | --- |
| `core/` | `EventBus`、`TimeScale`（戰鬥時間倍率，戰術介面用）、`GameState`（旗標、擊殺、檢查點）autoload、`InputSetup` |
| `save/` | `SaveSystem`：版本化 JSON 存檔、遷移、讀檔時重放斷肢讓模型同步 |
| `dialogue/` | `DialogueRunner`：JSON 對話（`content/dialogue/`），條件（旗標、異化、職業、物品）、分支、動作 |
| `boss/` | `BossPhaseComponent`（階段、召喚）、`BossFactory` |
| `scenes/prologue/` | `prologue_level.tscn`（由 `tools/generate_prologue_level.gd` 產生，之後直接在編輯器修改）、`prologue.tscn` |
| `anatomy/` | `BodyPartDef`、`AnatomyProfile`（Resource）；`AnatomyState`、`BodyPartState`、`CapabilitySet`（即時狀態） |
| `damage/` | `DamageTypes`（八種損傷與係數）、`DamagePacket`、`DamageResolver`、`DamageResult` |
| `ai/` | `EnemyDefinition`、`EnemyRuntimeState`、`EnemyAI`（狀態機）、`ai/states/` 各狀態、`AttackSelector`、`EnemyFactory`、`AiNavigator`（尋路）、`ai/perception/NoiseEmitter`（聲響）、`ai/tactics/`（`Tactics` 戰術評分、`TargetHabits` 玩家習慣、`PartTargeting` 瞄準傷口）、`ai/squad/`（`AttackTokens` 攻擊令牌、`Squad` 包圍站位） |
| `content/enemies/` | 四種敵人資料 |
| `combat/` | `CombatComponent`（攻擊、防禦、閃避、硬直、出血、死亡）、`ResourcePools`（HP/ST/AP）、`AttackDefinition` |
| `player/` | `PlayerController`（輸入 → 指令）、`TacticalController`（戰術介面）、`PlayerFactory` |
| `game/` | `PrologueGame`（序章控制器）、`CameraRig`（固定斜俯視）、`Greybox`【暫代】灰盒工具 |
| `ui/` | `MainMenu`、`CombatHud`、`TacticalOverlay`、`TransplantScreen`、`BodyMenu`、`DialogueBox`、`BossBar`（含登場標題卡） |
| `progression/` | `CharacterStats`、`ClassDefinition`、`SkillDefinition`、`ProgressionComponent` |
| `mutation/` | `MutationStage`、`MutationComponent` |
| `organ/` | `OrganDefinition`、`TransplantService`、`OrganRegistry` |
| `inventory/` | `Inventory` |
| `world/` | `StitchingAltar`、`Interactable` 及子類別（銘文／NPC、武器台、物品、Boss 門）、`AreaTrigger`、`EnemySpawn` |
| `content/classes/`、`skills/`、`mutation/`、`organs/` | 職業、技能、異化階段、器官資料 |
| `content/weapons/`、`content/attacks/` | 三種武器、徒手攻擊（拳、踢、咬） |
| `creature/` | `AnatomyComponent`：把 AnatomyState 掛到場景，套用玩家斷肢倍率（D2） |
| `dismemberment/` | `DismembermentController`、`Hurtbox`、`SeveredPart`（殘肢）、`AnimationSet` |
| `equipment/` | `EquipmentComponent`：武器掛在手臂上（D4），斷臂時掉落 |
| `placeholder/` | `PlaceholderBodyBuilder`：分段骨架、受擊區域、斷面標記（外觀由 `CreatureModels` 套用） |
| `scenes/sandbox/` | 斷肢沙盒測試場景 |
| `content/anatomy/` | 身體模板 `.tres`：`humanoid`（14 部位）、`multi_armed`（六臂） |
| `tests/` | headless 測試執行器與單元測試 |
| `tools/` | 一次性內容產生腳本，執行順序：anatomy → combat → growth → enemy → boss → prologue_level |

### 解剖系統資料流

```
DamagePacket ─▶ DamageResolver.resolve()（不修改狀態）─▶ DamageResult
            ─▶ AnatomyState.apply_result() ─▶ signals:
               part_damaged / part_status_changed / part_disabled /
               part_severed / capabilities_changed / vital_failed / died
```

- 「功能失效」（`part_disabled`）與「斷離」（`part_severed`）是兩個不同事件。
- 戰鬥、AI、動畫只讀 `CapabilitySet`（例如 `grip×4`、`locomotion×2`），不直接檢查部位。
  攻擊以 `required_capabilities` 宣告需求，斷肢後自動篩掉不能用的攻擊。

## 動畫（M9）

- 骨骼原點在關節（肩、髖、頸…），動畫只寫骨骼旋轉與 Skeleton 節點的位移／旋轉，不寫縮放，所以斷肢後縮為零的骨骼不會被動畫蓋掉，受擊區域與網格跟著骨骼一起動。
- `CreatureAnimationLibrary`：依身體模板的部位功能產生片段（待機、行走、單腳跛行、爬行、防禦、受擊、僵直、斷肢反應、閃避、死亡倒地），以及 22 種攻擊風格的前搖／判定／收招。單臂風格每隻手臂各一組。
- `AttackStyles`：攻擊 → 風格對照；新攻擊可在 `AttackDefinition.anim_style` 指定，未指定時依標籤與能力需求推論。
- `CreatureAnimator`：每個生物自動加上。建立 AnimationTree（狀態機 → TimeScale），依戰鬥狀態、速度與 `AnimationSet` 切換；攻擊片段長度 1 秒，依資料的階段秒數縮放，出手姿勢與命中判定同一刻。以戰術時間倍率推進、12fps 逐格更新（PS1 低幀數）。
- 動作截圖：`tests/sim/anim_shots.gd`（需要 xvfb 與 opengl3）。

## 模型（M10）

- `MeshKit`：SurfaceTool 組合工具（車床體、盒、錐），產生圓柱 UV 與朝外法線。
- `CreatureModels`：每個分段換成具象低多邊形造型，包括有手指的手臂、腳掌、反關節腿、肋骨、衣物、兜帽、五官、牙齒、縫線、眼柄、臍帶、子宮、高蹺、抱嬰的搖籃臂。外觀主題有 player、stitcher、many_hands、reverse_legged、faceless_watcher、unborn、walking_mother，其他身體用通用人形。節點名稱、位置與受擊區域不變。弱點（眼柄、臍帶、移植的眼）以陳舊金或乾涸紅自發光標示。
- `ModelSkinner`：器官移植（鐵臂、縫合臂、反關節腿、觀察者之眼）與 Boss 第二階段（子宮裂開）會換掉該部位的外觀，斷肢修復後保留。
- 工廠自動套用：`build_creature` 用身體模板的通用外觀，`PlayerFactory` 與 `EnemyFactory` 再套專屬外觀。
- 截圖：`tests/sim/model_shots.gd`。

## 演出（M11）

- `TransplantCutscene`：移植過場。舊部位被移開，新器官（移植外觀）降到石台上接合，縫線一針一針出現，最後脈動。被排斥時新部位轉為壞死的暗色。可跳過。
- `BossIntro`：Boss 登場鏡頭。從高蹺腳邊往上搖到面具，Boss 從蜷伏中站起尖叫，同時顯示標題。演出期間戰鬥暫停，結束後才啟動 AI。
- Boss 跪伏改為 1 秒的沉降曲線加跪伏動作；產聲會擴散聲波環（`ScreamWave`）；未生者從子宮的位置落下。
- `DialogueBox`：打字機效果（標點會停頓，E 先顯示整句）、3D 即時渲染的半身立繪（`PortraitView`，阿格妮絲與行走的母親）。每顯示一個字會發出 `typed` 訊號，供音效掛接。
- `BossGate`：哥德式雙開門（石框尖拱、木門板、金鉚釘），開啟時門板推開。
- `export_presets.cfg`：Windows 與 Linux 匯出設定，包含 `*.json`，排除 `tests/`、`tools/`。已用 `--export-pack` 驗證 11 個對話檔都有打包進去。正式匯出需要先安裝 Godot 4.3 匯出範本。
- 截圖：`tests/sim/presentation_shots.gd`。

## 暫代與未實作（明確標示）

- 角色模型是程序生成的低多邊形（`art/models/`），不是手工建模；每段是用 BoneAttachment3D 掛在骨骼上的剛體網格（PS1 時代的做法），不是蒙皮網格。
  正式模型只要遵守 `PlaceholderBodyBuilder` 註解中的命名慣例即可直接替換。
- 動畫是【程序生成】的關鍵格（`CreatureAnimationLibrary`），不是手工動畫；手肘、手指、脊椎沒有獨立骨骼（每個部位一根骨骼）。
- 移植後的部位外觀會改變，但心臟等內部器官（多手人之心）沒有外觀。異化階段（骨刺等）還沒有外觀變化。
- 敵人尋路：序章載入時以 `LevelNavigation` 從灰盒碰撞體烘焙導航網格，敵人沿路徑跨房間追擊；沙盒沒有導航網格時退回直線移動。敵人間距用簡單的分離轉向，不是 RVO。
- 新手引導：遊戲中按 H 開啟操作說明（`ControlsScreen`，按鍵從 InputMap 讀取）；前幾個房間依情境顯示一次性提示（`TutorialHints`，記在存檔旗標 `hint_*`）。
- 新手難度曲線：`DifficultyCurve` 依生成點在序章中的進度（迴廊 0 → Boss 1）以指數曲線縮放敵人的傷害、血量與戰術係數；前段一次只有 1 隻出手、不呼叫同伴。Boss 維持完整強度。係數為【暫代】初值。
- 敵人 AI 除錯：遊戲中按 F9 顯示每隻敵人的狀態／意圖／攻擊令牌／Boss 階段與連段。
- 飛撲的位移仍由 AI 直接移動身體；動畫只提供蓄力與撲出的姿勢。
- 武器是程序生成的低多邊形模型（`WeaponModels`）。手臂「功能失效」（未斷）時武器仍握在手上，但雙手武器在可用的手不足時無法揮動。
- 命中判定是幾何扇形計算（不使用物理碰撞），方便戰術減速與測試；之後若需要精確武器軌跡再改。
- 所有平衡係數（`damage/damage_types.gd`）皆為初值，未經遊玩測試。
- **序章遊玩時間（目標 20–30 分鐘）尚未實測**：只有自動測試與 headless 模擬，沒有人實際玩過。
- 產聲沒有音效（音訊由另一個工作串負責）。
- 對話沒有語音；只有阿格妮絲與行走的母親有立繪；阿格妮絲在關卡中仍是暫代的互動物件（沒有角色模型）；結局是一段文字畫面。
- 關卡是灰盒，只有聖堂大門是正式的門（其他是牆上的開口）。敵人沒有尋路（房間之間靠直線追擊）。
- 沒有音效與音樂。
