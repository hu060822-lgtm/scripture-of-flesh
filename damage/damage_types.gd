class_name DamageTypes
extends RefCounted
## 八種損傷類型與每種類型的規則係數。
## 所有係數集中在這裡，之後平衡調整只需改這個檔案（或日後改成 Resource）。

enum Type {
	CUT,         ## 切割傷：高出血、高斷肢
	LACERATION,  ## 撕裂傷：持續出血
	FRACTURE,    ## 骨折：累積到門檻會讓部位功能失效，但不斷離
	CRUSH,       ## 粉碎傷：大量部位 HP 傷害
	PIERCE,      ## 穿刺傷：可貫穿到內部器官
	BURN,        ## 灼傷：止血，但累積壞死
	NECROSIS,    ## 壞死：隨時間持續扣部位 HP
	MUTATION,    ## 異化：不扣 HP，累積部位異化值
}

const ALL: Array[int] = [
	Type.CUT, Type.LACERATION, Type.FRACTURE, Type.CRUSH,
	Type.PIERCE, Type.BURN, Type.NECROSIS, Type.MUTATION,
]

## 每點傷害轉換成部位 HP 損失的倍率。
const HP_FACTOR := {
	Type.CUT: 1.0, Type.LACERATION: 0.8, Type.FRACTURE: 0.7, Type.CRUSH: 1.3,
	Type.PIERCE: 0.6, Type.BURN: 0.9, Type.NECROSIS: 1.0, Type.MUTATION: 0.0,
}

## 每點傷害增加的出血速率（部位 HP / 秒）。灼傷為負值，代表止血。
const BLEED_FACTOR := {
	Type.CUT: 0.10, Type.LACERATION: 0.15, Type.FRACTURE: 0.0, Type.CRUSH: 0.03,
	Type.PIERCE: 0.08, Type.BURN: -0.10, Type.NECROSIS: 0.0, Type.MUTATION: 0.0,
}

## 每點傷害對斷肢分數的貢獻。
const SEVER_FACTOR := {
	Type.CUT: 1.0, Type.LACERATION: 0.4, Type.FRACTURE: 0.2, Type.CRUSH: 0.5,
	Type.PIERCE: 0.0, Type.BURN: 0.0, Type.NECROSIS: 0.0, Type.MUTATION: 0.0,
}

## 穿刺傷貫穿到內部器官的比例。
const PIERCE_PASS_THROUGH := 0.5
## 灼傷轉為壞死累積的比例。
const BURN_TO_NECROSIS := 0.2
## 骨折累積量達到部位最大 HP 的此比例時，部位功能失效（骨頭斷了）。
const FRACTURE_DISABLE_RATIO := 0.5
## 每點壞死累積量每秒扣除的部位 HP。
const NECROSIS_HP_PER_SEC := 0.05

static func name_of(t: int) -> String:
	return Type.keys()[t]
