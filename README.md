# 肉身聖典 THE SCRIPTURE OF FLESH

2.5D 日式黑暗奇幻 RPG。Godot **4.3** / GDScript，目標平台 PC。

> 目前階段：**M3 戰鬥迴圈**。主場景暫定為戰鬥沙盒（測試用），敵人還不會動（AI 在 M4）。

## 執行測試

```bash
GODOT=/path/to/godot tests/run_tests.sh
```

`run_tests.sh` 會先匯入專案，再執行 `tests/run_tests.gd`，並在輸出出現 `SCRIPT ERROR` 時判定失敗
（GDScript 執行期錯誤只會中止單一函式，否則可能造成「假通過」）。
headless 模式下會出現大量 `Parameter "m" is null`（mesh_storage）訊息，這是 Godot 4.3 dummy 渲染器的已知雜訊，不影響結果。

## 戰鬥沙盒（主場景，F5）

WASD 移動、滑鼠瞄準、左鍵普通攻擊、右鍵特殊技（消耗 AP）、Space 閃避、Shift 防禦、
1/2/3 換武器（骨鋸斧／聖骸錘［雙手］／解剖刺劍）、E 撿起掉落的武器、F5 重置。

## 斷肢沙盒（目視確認）

在編輯器開啟 `scenes/sandbox/dismemberment_sandbox.tscn` 後按 F6 執行。
左邊是人形（縫屍者暫代），右邊是多手人。1／2／3 切換斧／錘／刺劍，左鍵攻擊點到的部位，Shift+左鍵必定斷肢，R 重置。

在 Godot 編輯器中也可以直接以 `tests/run_tests.gd` 執行（File → Run）。

## 架構

三層分離：**Resource（靜態資料）／RefCounted（戰鬥即時狀態）／Node（表現）**。

| 資料夾 | 內容 |
| --- | --- |
| `core/` | `EventBus`、`TimeScale`（戰鬥時間倍率，戰術介面用）autoload、`InputSetup` |
| `anatomy/` | `BodyPartDef`、`AnatomyProfile`（Resource）；`AnatomyState`、`BodyPartState`、`CapabilitySet`（即時狀態） |
| `damage/` | `DamageTypes`（八種損傷與係數）、`DamagePacket`、`DamageResolver`、`DamageResult` |
| `combat/` | `CombatComponent`（攻擊、防禦、閃避、硬直、出血、死亡）、`ResourcePools`（HP/ST/AP）、`AttackDefinition` |
| `player/` | `PlayerController`（輸入 → 指令）、`PlayerFactory` |
| `game/` | `CameraRig`（固定斜俯視）、`Greybox`【暫代】灰盒工具 |
| `ui/` | `CombatHud` |
| `content/weapons/`、`content/attacks/` | 三種武器、徒手攻擊（拳、踢、咬） |
| `creature/` | `AnatomyComponent`：把 AnatomyState 掛到場景，套用玩家斷肢倍率（D2） |
| `dismemberment/` | `DismembermentController`、`Hurtbox`、`SeveredPart`（殘肢）、`AnimationSet` |
| `equipment/` | `EquipmentComponent`：武器掛在手臂上（D4），斷臂時掉落 |
| `placeholder/` | 【暫代】`PlaceholderBodyBuilder`：程序生成膠囊體分段人形 |
| `scenes/sandbox/` | 斷肢沙盒測試場景 |
| `content/anatomy/` | 身體模板 `.tres`：`humanoid`（14 部位）、`multi_armed`（六臂） |
| `tests/` | headless 測試執行器與單元測試 |
| `tools/` | 一次性內容產生腳本 |

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

## 暫代與未實作（明確標示）

- 人形是程序生成的膠囊體（`placeholder/`），每段是用 BoneAttachment3D 掛在骨骼上的剛體網格，不是蒙皮網格。
  正式模型只要遵守 `PlaceholderBodyBuilder` 註解中的命名慣例即可直接替換。
- 還沒有 AnimationTree 與任何動畫：`AnimationSet` 只決定「該用哪一組動作」，沒有實際播放。
- 修復部位（`restore_part`）後只恢復資料、受擊區域與骨骼，**不會重建網格**（M6）。
- 敵人 AI 尚未實作（M4）：AI 會透過 `capabilities_changed` 重新評估攻擊。
- 武器外觀是暫代方塊。手臂「功能失效」（未斷）時武器仍握在手上，但雙手武器在可用的手不足時無法揮動。
- 沒有攻擊動畫：攻擊時序（前搖／判定／收招）由資料驅動，畫面上目前看不到揮擊動作。
- 命中判定是幾何扇形計算（不使用物理碰撞），方便戰術減速與測試；之後若需要精確武器軌跡再改。
- 所有平衡係數（`damage/damage_types.gd`）皆為初值，未經遊玩測試。
