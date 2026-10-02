# S2：無縫播放（gapless）驗證

日期：2026-10-03
程式碼：`Spikes/Gapless/`（獨立 target `GaplessSpike`，不隨 app 出貨）

## 結論

**MVP 播放引擎採用 `AVQueuePlayer`，不引入 AudioStreaming，也不提前引入 libmpv。**

* 同格式換曲（AAC → AAC、MP3 → MP3）實測無縫：停頓 0–1.4 ms。
* 格式在專輯中途改變（MP3 → AAC）會有約 80 ms 停頓。
* 必須開啟 `AVURLAssetPreferPreciseDurationAndTimingKey`，否則 MP3 的長度與 seek 位置只是估算值。
* **不能**在 `AVPlayerItem` 上掛 `MTAudioProcessingTap`：掛上後每次換曲都會多出約 450 ms 停頓。

## 測試對象

Library 實際格式分布（17,180 首）：AAC / ALAC（m4a）64.3%、MP3 35.6%、WAV 5 首、**沒有 FLAC**。

| 換曲 | 格式 | 原始檔接縫處的靜音 |
| ---- | ---- | -----------------: |
| The Dark Side of the Moon 1→2 | MP3 → AAC | 0 ms |
| The Dark Side of the Moon 2→3 | AAC → AAC | 0 ms |
| The Dark Side of the Moon 6→7 | AAC → AAC | 0 ms |
| The Dark Side of the Moon 8→9 | AAC → AAC | 9.5 ms |
| Disco Kandi The Mix 1→2 | MP3 → MP3 | 0 ms |
| Disco Kandi The Mix 2→3 | MP3 → MP3 | 0 ms |
| Live aus Berlin 1→2 | MP3 → MP3 | 33.8 ms |
| Live aus Berlin 2→3 | MP3 → AAC | 0 ms |

「原始檔接縫處的靜音」＝下載原始檔後用 `AVAudioFile` 解碼，前一首結尾加下一首開頭的靜音長度，作為對照組。

## 測試方法

每次從前一首結尾前 3 秒開始播放，經過換曲後再播 3 秒，每個換曲測 3 次。播放全程音量 0，喇叭不出聲。

* **AVQueuePlayer（時鐘法）**：每 5 ms 記錄牆上時間與播放器回報的 media time。換曲若有停頓，牆上時間會比 media time 多走，差值即停頓長度。不需要掛 tap。
* **AVQueuePlayer + tap**：掛 `MTAudioProcessingTap` 收集 samples，計算接縫處最長靜音。
* **AudioStreaming 1.4.5**：在 main mixer 前插入 passthrough node 錄下連續輸出，計算接縫處最長靜音。

## 結果（ms，3 次）

| 換曲 | 格式 | AVQueuePlayer | AVQueuePlayer + tap | AudioStreaming |
| ---- | ---- | ------------: | ------------------: | -------------: |
| DSOTM 1→2 | MP3 → AAC | 130 / 82 / 79 | 277 / 462 / 462 | 48 / 48 / 48 |
| DSOTM 2→3 | AAC → AAC | 0 / **287** / 0 | 444 / 444 / 444 | 61 / 61 / 61 |
| DSOTM 6→7 | AAC → AAC | 0 / 0 / 0 | 470 / 470 / 470 | 50 / 50 / 50 |
| DSOTM 8→9 | AAC → AAC | 1 / 1 / 1 | 450 / 450 / 450 | 57 / 57 / 57 |
| Disco Kandi 1→2 | MP3 → MP3 | 0 / 0 / 0 | 505 / 505 / 505 | 11 / 11 / 11 |
| Disco Kandi 2→3 | MP3 → MP3 | 0 / 0 / 0 | 534 / 544 / 534 | 28 / 28 / 28 |
| Live aus Berlin 1→2 | MP3 → MP3 | 0 / 0 / 0 | 523 / 523 / 523 | 92 / 92 / 92 |
| Live aus Berlin 2→3 | MP3 → AAC | 82 / 85 / 85 | 504 / 504 / 504 | 73 / 73 / 73 |

人耳大約能察覺 10–20 ms 以上的停頓。

## 解讀

* **AVQueuePlayer**：同格式 21 次中 20 次無縫。DSOTM 2→3 有 1 次 287 ms，推測是下一首還沒緩衝好：測試時下一首只有約 3 秒可以緩衝，正常播放時會有整首歌的時間。正式實作仍需在換曲前確認下一首已就緒。
* **AudioStreaming**：每個換曲都有 11–92 ms 靜音，推測是沒有修剪 AAC / MP3 的 encoder padding。另外 1.4.5 有一個 bug：先 `queue` 再 `seek`，排隊的曲目不會播放。
* **MTAudioProcessingTap**：只要掛上就破壞無縫播放。未來若要做 audio visualizer 或 ReplayGain，不能用這個方法。

## 限制

* 時鐘法量的是「時間軸是否連續」，不是實際輸出的 samples。MP3 的 encoder padding 若沒被修剪，會被算進 media time，時鐘法看不出來。對照組顯示 Apple 解碼器對這幾個 MP3 沒有在邊界留下靜音，因此推論 AVQueuePlayer 輸出也沒有，但這是推論，不是直接量測。
* 要直接量測實際輸出，需要 Core Audio process tap，這需要使用者授權「系統錄音」，本次無人值守所以沒做。
* Library 沒有 FLAC，FLAC 未測。

## 對實作的影響

* `PlayerManager` 以 `AVQueuePlayer` 實作，`AVURLAsset` 一律帶 `AVURLAssetPreferPreciseDurationAndTimingKey: true`。
* 不在播放路徑上使用 `MTAudioProcessingTap`。
* 串流使用 Jellyfin 原始檔：`/Audio/{id}/stream.{container}?static=true`，不轉檔。
* Jellyfin 12 驗證需使用 `Authorization: MediaBrowser ...` header；`X-Emby-Authorization` 已無效。

## 正式 app 實測（2026-10-03）

在 Finify Release build 的 `PlayerManager` 上用同樣的時鐘法量測（`-FinifyGaplessProbe`），下一首已預載完成。播放全程靜音。

| 專輯 | 同格式換曲 | 跨格式換曲 |
| ---- | ---------- | ---------- |
| The Dark Side of the Moon（8 次） | 7 次，0–0.9 ms | MP3 → AAC：101 ms |
| Disco Kandi The Mix（8 次） | 8 次，0 ms | — |
| Live aus Berlin（8 次） | 6 次，0–0.6 ms | MP3 → AAC：85 ms、AAC → MP3：92 ms |

結論與 spike 一致：同格式無縫；格式改變時約 0.1 秒停頓，推測是 AVFoundation 重新設定解碼器。
**比預期常見**：你的 library 有 347 張專輯（24%）混用 MP3 與 AAC，專輯內 15,754 次換曲中有 1,443 次（9%）跨格式。
停頓只在曲目之間本來沒有空白的專輯（Live、DJ mix、概念專輯）聽得出來。

可能的解法（都還沒做，需要你決定）：

1. **接受現況**：大多數專輯曲目之間本來就有 1–2 秒空白，0.1 秒聽不出來。
2. **整理音樂庫**：把混用格式的專輯統一成同一格式（例如用 Lidarr 重新取得整張）。不用改程式。
3. **自行解碼的 AVAudioEngine 播放器**：可以做到跨格式無縫，但要自己處理 encoder delay / padding（S2 中 AudioStreaming 就是沒處理好，每次換曲都有 11–92 ms 靜音）。估計 2–3 天，且要重新驗證。
