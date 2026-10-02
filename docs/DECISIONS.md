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

## D06　藝人用圓形、專輯用方形；藝人沒有照片時用其專輯封面

* **選擇**：藝人圖片裁成圓形，專輯維持方形（圓角 4pt）。藝人沒有照片時，用他任一張有封面的專輯代替。
* **理由**：形狀一眼區分「人」與「作品」。實測你的 Jellyfin 幾乎所有藝人都沒有照片，整頁都是佔位圖，看起來像壞掉。
* **怎麼改**：形狀在 `Components/LibraryCards.swift` 的 `ArtistCard`；替代圖邏輯在 `LibraryStore.artwork(for:)`。

## D07　Standard 用頂部導覽列，不用 sidebar

* **選擇**：Home / Library 兩個分頁放在頂部，中間是搜尋入口，右側是 Standard ↔ Overflow 切換。
* **理由**：規格的 Anti-patterns 明列「Generic sidebar」。MVP 只有兩個主要分頁，sidebar 會留下大片空白；頂部列讓內容寬度最大，封面更大。
* **代價**：V1 加入 Playlists、Favorites 後分頁變多，屆時需要重新評估（可能改成可收合的窄欄）。
* **怎麼改**：`Features/Standard/StandardRootView.swift` 的 `StandardTopBar`。

## D08　⌘K 搜尋面板在兩個 mode 共用

* **選擇**：同一個 `SearchPalette`。Standard 選到專輯會開專輯頁；Overflow 沒有藝人頁，選到藝人時開他最新的專輯。
* **理由**：規格要求 Overflow 能獨立搜尋，但沒有定義 UI。共用面板讓兩邊行為一致，也不必維護兩套。
* **補充**：Jellyfin 的專輯搜尋只比對專輯名，所以搜尋藝人名時會補上該藝人的專輯（搜「Radiohead」才會出現 OK Computer）。

## D09　品牌色 Ember（#FF6A3D）與暖色中性色

* **選擇**：accent 用偏紅的橘色 Ember；底色是帶暖調的近黑（#0E0D0C）與米白（#F7F5F1），不是純黑白。
* **理由**：規格要求不用 Spotify 綠，且品牌色要與封面 ambient 色分離。暖色中性色讓封面成為畫面主角，Ember 只用在「正在播放」與主要狀態。
* **怎麼改**：全部集中在 `DesignSystem/Colors/FinifyColor.swift`。

## D10　App icon（暫定）

* **選擇**：3×3 專輯格，亮起的 6 格組成「F」，Ember 漸層。
* **理由**：呼應 Album Wall，16px 也辨識得出。這是暫定版，正式品牌設計時可直接替換。
* **怎麼改**：`scripts/icon/make-icon.swift` 產生 1024px 原圖，再輸出到 `Assets.xcassets/AppIcon.appiconset`；或直接把設計好的 PNG 放進該資料夾。

## D11　Album Wall 的點擊行為

* **選擇**：單擊打開專輯面板，雙擊或 Return 直接播放，方向鍵只移動焦點框。
* **理由**：與 Finder、Photos 的慣例一致。單擊會等系統的雙擊間隔過去才執行，否則雙擊的第一下會先打開面板。
* **代價**：單擊打開面板有約 0.3–0.5 秒延遲（系統雙擊間隔）。若覺得太慢，可改成單擊只選取、空白鍵或 Return 打開。

## D12　MVP 完成後提前做部分 V1 項目

* **選擇**：MVP 的 vertical slice 與驗收項目完成後，依價值排序提前實作部分 V1：Wall 的 Tiny / Huge、啟動時恢復播放佇列、Favorites、選單列控制器、Album Flip。
* **理由**：規格只限制「vertical slice 完成前不做 AI、Lidarr、Offline、Mobile」，這些 V1 項目不在禁止範圍，且都是日常使用會直接感受到的功能。
* **怎麼改**：每個項目都是獨立 commit（訊息開頭標 `V1`），不要的話可以單獨 `git revert`。
