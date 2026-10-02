# Finify 決策紀錄

規格沒寫清楚、或需要取捨時所做的選擇。每一項都寫明理由與修改方式。

---

## D01　播放引擎：AVQueuePlayer

* **選擇**：MVP 用 `AVQueuePlayer`，不用 AudioStreaming，不提前引入 libmpv。
* **理由**：S2 實測同格式換曲無縫（0–1.4 ms）；AudioStreaming 每次換曲都有 11–92 ms 靜音。見 `docs/spikes/S2-gapless.md`。
* **代價**：專輯中途換格式（MP3 → AAC）有約 80 ms 停頓；不能在播放路徑上掛 `MTAudioProcessingTap`。
* **怎麼改**：播放邏輯集中在 `Finify/Player/PlayerManager.swift`，換引擎只需改這個檔案。

## D02　Album Wall：NSCollectionView

* **選擇**：Album Wall 以 `NSCollectionView` 實作，包進 SwiftUI。
* **理由**：S3 實測 SwiftUI `LazyVGrid` 捲動會掉 frame，`NSCollectionView` 不會。見 `docs/spikes/S3-album-wall.md`。
* **怎麼改**：只影響 `Features/Overflow/AlbumWall/`。

## D03　Jellyfin 驗證 header

* **選擇**：一律使用 `Authorization: MediaBrowser Client=..., Token=...`。
* **理由**：Jellyfin 12.1 已不接受 `X-Emby-Authorization`（實測）。串流 URL 因 `AVPlayer` 無法帶 header，改用 `ApiKey` query 參數。

## D04　Library 快取用 JSON 快照，不用 SwiftData

* **選擇**：專輯與藝人清單存成一個 JSON 檔（Application Support），啟動時先顯示快照，再向 server 更新。
* **理由**：MVP 只需要「離線時仍能瀏覽上次的音樂庫」與「啟動時立即有畫面」。1 萬張專輯的 JSON 約 2–3 MB，讀取不到 100 ms，SwiftData 的 schema、migration 在這個階段是額外成本。
* **與規格的差異**：規格寫 SwiftData。當需要查詢（例如離線搜尋、播放紀錄統計）時再換。
* **怎麼改**：只影響 `Finify/Core/Persistence/LibraryStore.swift`。

## D05　開發時的登入資訊來源

* **選擇**：DEBUG build 帶 `-FinifySecrets <repo>/.secrets` 啟動時，改讀 `.secrets/` 的登入資訊，不用 Keychain。
* **理由**：未簽章的 app 每次重新 build，Keychain 會跳出「允許存取」視窗，無人值守測試會卡住。Release build 沒有這段程式碼。
* **怎麼改**：`Finify/Core/Persistence/SessionStore.swift` 的 `DevelopmentSessionStore`。
