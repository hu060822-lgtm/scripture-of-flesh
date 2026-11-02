# 肉身聖典 THE SCRIPTURE OF FLESH

2.5D 日式黑暗奇幻 RPG。Godot **4.3** / GDScript，目標平台 PC。

> 目前階段：**M1 解剖核心（純資料層）**。尚無任何場景、模型或可遊玩內容。

## 執行測試

```bash
godot --headless --path . --editor --quit      # 第一次：建立 class_name 快取
godot --headless --path . -s tests/run_tests.gd
```

在 Godot 編輯器中也可以直接以 `tests/run_tests.gd` 執行（File → Run）。

## 架構

三層分離：**Resource（靜態資料）／RefCounted（戰鬥即時狀態）／Node（表現）**。

| 資料夾 | 內容 |
| --- | --- |
| `core/` | `EventBus` autoload（跨系統事件） |
| `anatomy/` | `BodyPartDef`、`AnatomyProfile`（Resource）；`AnatomyState`、`BodyPartState`、`CapabilitySet`（即時狀態） |
| `damage/` | `DamageTypes`（八種損傷與係數）、`DamagePacket`、`DamageResolver`、`DamageResult` |
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

- 沒有任何 3D 表現：斷肢的模型／骨架／碰撞／動畫／裝備更新屬於 M2（分段網格方案）。
- 整體 HP、ST、AP 資源池尚未實作；`AnatomyState.tick()` 回傳的失血量目前沒有被任何系統扣除。
- `COUNTDOWN` 類致命部位（肺）只發出 `vital_failed`，倒數死亡邏輯尚未實作。
- 所有平衡係數（`damage/damage_types.gd`）皆為初值，未經遊玩測試。
