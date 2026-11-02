# 音效資料夾

每個 cue 一個子資料夾：`res://audio/sfx/<cue_id>/`。資料夾裡的每個 `.wav`、`.ogg` 或 `.mp3` 都是一個隨機變體。
cue 列表與匯流排、音量、音高、發聲上限都在 `audio/sound_catalog.gd` 的 `TABLE`。
資料夾不存在或是空的時，該 cue 是【暫代】靜音：照常記錄，但不發聲。
