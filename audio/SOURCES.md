# 聲音素材來源與授權

依 luz 的決定（2026-11-02），所有音效與音樂都由 repo 內的工具**程序合成**，全部是原創，沒有第三方素材。
產生器的程式碼與參數都在 repo 裡，可以重新產生。

## SFX（res://audio/sfx/<cue_id>/）

（A2 加入：列出每個 cue 的產生器與參數。）

## Music / Ambience（res://audio/music/）

全部由 `tools/music_synth/generate_music.py` 程序合成（Python 3 + numpy，用 ffmpeg/libvorbis 輸出 .ogg）。
亂數種子固定為 732，重新執行會得到相同的結果。旋律〈搖籃曲〉是原創，沒有引用任何既有的曲子。

| 檔案 | 內容 |
| --- | --- |
| `stems/lullaby.ogg` | 原創 A 小調搖籃曲，3/4 拍、72 BPM、16 小節（40 秒）。八音盒加法合成，音準隨機偏移與磁帶顫音。第 9 小節靜默，第 14 小節有一個錯音 D# |
| `stems/lullaby_major.ogg` | 同一首曲子的 A 大調版本，沒有顫音（離院結局） |
| `stems/pad.ogg` | 「啊」母音的共振峰合成和聲 |
| `stems/drone.ogg` | A1／B♭1 小二度拍頻低鳴，加上帶通噪音 |
| `stems/breath.ogg` | 倒放式漸強的「嗚」聲加上呼吸噪音 |
| `stems/heartbeat.ogg` | 每拍一次的心跳（下滑正弦波） |
| `stems/perc.ogg` | 低通噪音的悶擊，以及不和諧泛音的金屬刮擦聲 |
| `stems/hum.ogg`、`stems/hum_broken.ogg` | 母親以「嗯」母音哼唱搖籃曲。broken 版本會下滑、走音、吞音，並疊上三全音 |
| `stems/boss_low.ogg` | E1／F1 不協和低音群，每小節一次脈動 |
| `stingers/death.ogg` | 死亡時的下沉低鳴（7 秒，不循環） |
| `ambience/*.ogg` | 30 秒循環：產房（日光燈嗡鳴、滴水）、迴廊（風、木頭吱嘎）、庭院（風、遠方的鐘）、藏書室（時鐘、紙頁）、聖器室（滴水、鎖鏈）、禮拜堂（管風琴持續音、牆在呼吸） |

所有濾波都用 FFT 循環運算，LFO 都取整數圈數，所以每個循環的頭尾無縫。
