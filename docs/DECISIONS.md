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

## D07　Standard 改用左側 sidebar＋右側 Now Playing 面板（取代原本的頂部導覽列）

* **選擇**：依使用者提供的 Finity 參考圖重做版面：左側導覽（Home、Search、Music、Smart、Playlists）、中間內容、右側 Now Playing 面板（封面、控制、Up Next／Lyrics）、底部播放列。頂部列只留上一頁／下一頁、搜尋、mode 切換。
* **理由**：原本選頂部列是因為 MVP 只有兩個分頁；V1 加入 Playlists、Favorites 後項目變多，且使用者指定了參考設計。
* **省略的項目**：參考圖中的 Sources（Jellyfin／Spotify）、All／Jellyfin／Spotify 篩選、Well、Related 分頁。Finify 沒有 Spotify 整合，Well 與 Related 也還沒有對應的資料，放了只會是空殼。
* **補充**：Hero 標語用「Your music, your server.」而不是參考圖的「Music Without Limits.」，副標寫的是真實資料（最新加入的專輯、server 名稱），Play 播放該專輯，Shuffle 從整個音樂庫隨機挑 200 首。
* **面板開關**：記在 `FinifyNowPlayingPanel`，只在 Standard 裡記錄。
* **怎麼改**：`Features/Standard/StandardSidebar.swift`、`NowPlayingPanel.swift`、`StandardRootView.swift`、`Home/HomeView.swift` 的 `HomeHero`。

## D08　⌘K 搜尋面板在兩個 mode 共用

* **選擇**：同一個 `SearchPalette`。Standard 選到專輯會開專輯頁；Overflow 沒有藝人頁，選到藝人時開他最新的專輯。
* **理由**：規格要求 Overflow 能獨立搜尋，但沒有定義 UI。共用面板讓兩邊行為一致，也不必維護兩套。
* **補充**：Jellyfin 的專輯搜尋只比對專輯名，所以搜尋藝人名時會補上該藝人的專輯（搜「Radiohead」才會出現 OK Computer）。

## D09　品牌色改為 Finity Blue（#2F6BFF）與深藍中性色

* **選擇**：依使用者提供的 Finity Visual Design System：accent 用 Finity Blue（深色模式用 Electric #3E7CF6），底色是 Navy #0D1633、面板 Deep Navy #111D40、卡片 Blue Glass #182956；Aurora 漸層（#1D4ED8 → #2F6BFF → #6A8DFF → #A78BFA）只用在 Hero。淺色模式用帶藍調的淺灰白（#F4F6FC）。
* **取代**：原本的 Ember 橘與暖色中性色。
* **命名**：設計文件寫的是「Finity」，程式與 App 名稱仍是「Finify」，沒有改名。
* **Overflow**：背景改為 Ink #080D20，浮動控制也帶藍調，但仍維持「封面是主角」。
* **怎麼改**：全部集中在 `DesignSystem/Colors/FinifyColor.swift`。

## D10　App icon 與選單列 icon（Finity）

* **App icon**：直接使用設計稿 `scripts/icon/finity-icon-source.png`（藍紫漸層底、半透明玻璃緞帶「F」），裁出圓角方形、放大一點讓設計稿四角的白底落在遮罩外，再加上 macOS icon 的陰影。
* **選單列**：設計稿裡兩個水滴的實心輪廓（上方水滴圓頭在右上，下方水滴圓頭在左下、尾巴成為中橫），座標是對著設計稿描的。18pt 畫布、字形 16pt。平常是 template（淺色選單列黑、深色白）；播放中換成 Electric Blue（#3E7CF6），右下 F 的空白處加一個小點。
* **怎麼改**：`scripts/icon/make-icon.swift`。換設計稿就重跑 `app`；字形在 `drops`。app icon 用 `sips` 縮成 `AppIcon.appiconset` 的各尺寸；選單列直接寫入 `MenuBarIcon`／`MenuBarIconPlaying` imageset。

## D11　Album Wall 的點擊行為

* **選擇**：單擊打開專輯面板，雙擊或 Return 直接播放，方向鍵只移動焦點框。
* **理由**：與 Finder、Photos 的慣例一致。單擊會等系統的雙擊間隔過去才執行，否則雙擊的第一下會先打開面板。
* **代價**：單擊打開面板有約 0.3–0.5 秒延遲（系統雙擊間隔）。若覺得太慢，可改成單擊只選取、空白鍵或 Return 打開。

## D12　MVP 完成後提前做部分 V1 項目

* **選擇**：MVP 的 vertical slice 與驗收項目完成後，依價值排序提前實作部分 V1：Wall 的 Tiny / Huge、啟動時恢復播放佇列、Favorites、選單列控制器、Album Flip。
* **理由**：規格只限制「vertical slice 完成前不做 AI、Lidarr、Offline、Mobile」，這些 V1 項目不在禁止範圍，且都是日常使用會直接感受到的功能。
* **怎麼改**：每個項目都是獨立 commit（訊息開頭標 `V1`），不要的話可以單獨 `git revert`。

## D13　Playlist 一律以完整狀態更新

* **選擇**：改名、加入、移除、排序都用 `POST /Playlists/{id}`，一次送出名稱與完整曲目清單；不使用 Jellyfin 個別的 Items / Move API。
* **理由**：Jellyfin 12.1 實測，改名後再用 Items API 加歌，名稱會被還原（間隔 2 秒也一樣）。完整狀態更新在改名、加入、排序、移除、重複曲目上都正確。
* **代價**：每次編輯要先知道完整清單；playlist 很長（上千首）時請求較大，目前最大的 playlist 是 636 首，沒有問題。
* **怎麼改**：`JellyfinRepository.updatePlaylist`。若 Jellyfin 修正此問題，可改回個別 API。
* **測試安全**：整合測試只在名為「Finify Test…」的暫存 playlist 上寫入，開始時會清掉殘留、結束時刪除；不碰既有 playlist。
* **補充**：新建立的 playlist 在 1.5 秒內再寫入會被 Jellyfin 背景存檔蓋掉（實測），`PlaylistStore` 會等到建立滿 1.5 秒才送出後續編輯。

## D14　串流網址帶 access token（已知取捨）

* **現況**：`AVPlayer` 無法替串流請求加 header，所以 token 放在網址的 `ApiKey` 參數（D03）。Jellyfin 官方網頁版也是這樣做。
* **風險**：網址只送往你自己的 Jellyfin server（目前經 Tailscale），但 token 可能出現在 server 的存取紀錄或 proxy 紀錄中。這個 token 是你帳號的長期 token，外流等於帳號外流。
* **為什麼暫時不改**：
  * `AVURLAssetHTTPHeaderFieldsKey` 可以加 header，但它是未公開 API，上架 App Store 有被拒風險。
  * `AVAssetResourceLoaderDelegate` 可以完全自己處理請求，但要重做 range request 與緩衝，可能影響 S2 驗證過的無縫播放。
* **建議後續**：上架前改用 resource loader，並重跑 S2 無縫播放驗證；或在 Jellyfin 為 Finify 建立權限較小的專用帳號。
* **怎麼改**：`JellyfinRepository.streamURL(for:)` 與 `PlayerManager.makeItem`。

## D15　換歌通知

* **選擇**：只在 Finify 不在前景時發，內容是曲名、藝人、專輯，附封面；新通知取代上一則，不會堆一長串。啟動時就請求通知權限，因為 app 在背景時才請求會被系統直接拒絕（實測）。設定 → General 可關閉。
* **分享**：曾經加入（右鍵選單與 Now Playing 面板），依使用者要求移除。
* **怎麼改**：`Core/Platform/TrackNotifier.swift`。

## D16　歌詞備援 LRCLIB（預設關閉）

* **選擇**：Jellyfin 沒有歌詞時，若使用者同意，再查 lrclib.net（免費、公開的歌詞資料庫），在結果中挑長度最接近這首歌的版本，優先使用同步歌詞。
* **為什麼預設關閉**：查詢會把歌名、藝人送到外部網站。開關在設定 → General；歌詞面板沒有歌詞時也有「Search LRCLIB」按鈕，按下等於開啟。
* **顯示**：來自 LRCLIB 的歌詞底部標示「Lyrics from LRCLIB」。外部查詢失敗時視為沒有歌詞，不顯示錯誤。
* **怎麼改**：`Core/Lyrics/LRCLib.swift`（含 LRC 解析，測試在 `LRCLibTests`）、`LyricsPanel.load`。

## D17　Liquid Glass 只用在浮在封面上的元件

* **選擇**：macOS 26 以上，Overflow 的浮動播放列、頂部分段控制、Flow 大小滑桿、回到正在播放按鈕、專輯面板，以及 Standard Hero 上的 Shuffle，改用系統的 Liquid Glass（`.glassEffect`），並帶一點深藍色調，維持 Finity 的深色氣氛。macOS 14～15 退回原本的半透明深藍底加細邊。
* **理由**：Finity 設計文件寫「玻璃是材質，不是裝飾」，且要避免每張卡片都像玻璃。這些元件都浮在封面上，玻璃能透出底下的顏色；一般頁面、側欄、清單維持實色。
* **怎麼改**：`DesignSystem/Materials/Glass.swift` 的 `finifyGlass(in:tint:interactive:fallback:)`。

## D18　Smart Shuffle 用 Jellyfin Instant Mix

* **選擇**：隨機播放按鈕依序切換「關 → 隨機 → Smart Shuffle」。Smart Shuffle 會用目前這首歌向 Jellyfin 要 Instant Mix（相似曲目），在「接下來」每 3 首插入 1 首，接下來不夠時再接 3 首在最後，讓音樂不會停；推薦少於 2 首時自動再補。推薦曲目在佇列中以藍色 shuffle 小圖示標示。
* **理由**：Kaset 的 Smart Shuffle 是穿插 YouTube 的推薦；Jellyfin 有現成的 Instant Mix，不用自己算相似度。
* **規則**：推薦只放在播放順序，不進原始順序，所以關掉隨機播放就會消失（若正在播推薦曲目，會保留這一首）。播放新的專輯或清單時，Smart Shuffle 會關閉。
* **怎麼改**：`PlayQueue.blendSuggestions`（測試在 `PlayQueueTests`）、`PlayerManager.toggleShuffle`／`refillSuggestions`，每幾首插一首在 `suggestEvery`。

## D19　Dock 選單、觸覺回饋、finify:// 網址

* **Dock 選單**：在 Dock 圖示按右鍵，顯示目前播放的歌，以及播放／暫停、下一首、上一首。沒有播放時不加項目。
* **觸覺回饋**：只在 Force Touch 觸控板上有感覺。用在播放控制、喜愛、隨機／重複，以及 Flow 大小滑桿換段；一般按鈕不加，避免太吵。
* **網址**：`finify://play`、`pause`、`toggle`、`next`、`previous`；`finify://album/<id>` 打開專輯（Standard 開專輯頁、Overflow 開專輯面板）；`finify://play?album=<id>`、`finify://play?playlist=<id>` 直接播放。讓 Raycast、Alfred、捷徑可以控制 Finify。未登入時忽略。
* **Info.plist**：網址註冊需要 `CFBundleURLTypes`，所以 `project.yml` 改為產生 `Finify/Info.plist`（版本號仍引用 `MARKETING_VERSION`），其餘欄位照舊由 `GENERATE_INFOPLIST_FILE` 產生。
* **怎麼改**：`App/AppDelegate.swift`、`Core/Platform/Haptics.swift`、`App/URLCommands.swift`。

## D20　三種模式：Standard、Infinity、Cover Flow

* **選擇**：模式收斂成三種，所有模式的右上角都是同一組三段切換（膠囊外形，與搜尋框一致），旁邊一顆全螢幕按鈕。快捷鍵 ⌘1／⌘2／⌘3。
  * Standard：原本的 Standard。
  * Infinity：原本 Overflow 的封面牆（Wall）。
  * Cover Flow：原本 Overflow 的 Flow。
* **全螢幕**：按鈕讓整個視窗照目前的畫面進入 macOS 全螢幕（等同 ⌃⌘F），不再是只顯示一首歌的畫面。只顯示一首歌的大畫面仍保留，改名「Now Playing view」，入口在播放列（圖示與全螢幕不同）。
* **移除**：Overflow 原本的 Wall／Flow／Recent 分段控制、側欄的 Overflow 項目、設定裡的 Layout 選項。Recent（最近播放專輯牆）不在三種模式內，先移除；首頁的 Recently Played 仍在。
* **程式**：內部仍是 `AppMode.standard／overflow` 加 `OverflowLayout.wall／flow`，使用者看到的是 `ViewMode`（`AppEnvironment.viewMode`）。
* **怎麼改**：`ModeSwitch`、`FullscreenButton`（`StandardRootView.swift`）、`ViewMode`（`AppEnvironment.swift`）。
