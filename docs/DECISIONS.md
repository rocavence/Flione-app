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

## D09　色彩系統：Flione（deep-ocean／bioluminescent）

* **來源**：使用者提供的 Flione Color System（取代先前的 Finity 配色）。
* **底色層級**：Abyss `#061426`（App 背景）→ Surface 1 `#0A1D3C`（側欄）→ Surface 2 `#10264B`（卡片）→ Surface 3 `#14305A`（浮起）→ Surface Active `#183D78`（選取）。文字 `#FFFFFF`／`#AFC0DF`／`#7185AA`／`#4D6085`。邊框 `#FFFFFF12`、hover `#FFFFFF0A`。
* **藍色**：Flione Blue `#2F6BFF` 用在按鈕、選取、音量與大小滑軌、focus；Ice Blue `#6AA8FF` 次要 accent。
* **橘色**：Bright Coral Orange `#FF8A3D` 只用在播放進度、正在播放的標示（曲目列、專輯面板、Cover Flow、Library 網格）與選單列「播放中」圖示。不可成為主要 UI 色。
* **橘色微光**：所有橘色元素都帶柔和光暈（`finifyGlow()`：貼近的 55% 橘＋外圈 Orange Glow 24%），像深海裡的發光體；Library 網格的標題用 NSShadow 做同樣效果。
* **紫色**：Aurora Violet `#A78BFF` 只當氛圍（漸層），不用在按鈕與導覽。
* **漸層**：Flione Aurora（藍 → 冰藍 → 紫 → 橘，橘色只在尾端焦點），只用在首頁 Hero。
* **語意色**：Success `#55D6A6`、Warning `#FFB84D`（Toast 圖示）、Error `#FF5F6D`、Info `#6AA8FF`。
* **淺色模式**：文件沒有定義，沿用原本的淺色底色，只換品牌色。
* **命名**：設計文件寫的是「Flione」，程式與 App 名稱仍是「Finify」，沒有改名。
* **怎麼改**：全部集中在 `DesignSystem/Colors/FinifyColor.swift`（深色固定值在 `FinifyColor.Ocean`）。

## D10　App icon 與選單列 icon（Finity）

* **App icon**：設計稿 `scripts/icon/finity-icon-source.png`（深藍底、發光的半透明鳥形）依 macOS icon 格線標準化：824×824 圓角方形置中於 1024 畫布，加上標準陰影與細亮邊，再縮成 `AppIcon.appiconset` 的各尺寸。設計稿若四周有白底會自動裁掉。
* **選單列**：設計稿 `scripts/icon/menubar-source.png` 的剪影以 potrace 描成向量（`scripts/icon/menubar-glyph.svg`），重畫成 18pt 畫布、字形 16pt。平常是 template（淺色選單列黑、深色白）；播放中換成 Bright Coral Orange（#FF8A3D），右下加一個小點。
* **怎麼改**：換設計稿後重跑 `scripts/icon/make-icon.swift app …` 與 `menubar …`（用法寫在檔案開頭）。

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

## D17　Liquid Glass 用在浮在內容上的元件與頂部控制

* **選擇**：macOS 26 以上使用系統的 Liquid Glass（`.glassEffect`）；macOS 14～15 退回原本的半透明底色加細邊。
  * Infinity／Cover Flow：浮動播放列、頂部搜尋框、三段模式切換、全螢幕按鈕、封面大小 −／+、排序、Cover Flow 大小滑桿、回到正在播放、專輯面板、佇列浮層。帶深藍色調，維持 Finity 的深色氣氛。
  * Standard：頂部的上一頁／下一頁、搜尋框、三段模式切換、全螢幕按鈕，像系統工具列按鈕；帶目前主題的表面色，淺色模式也自然。首頁 Hero 的 Shuffle。
  * 共用：⌘K 搜尋面板、Toast、Now Playing view 的控制列與離開按鈕。
* **文字面板加底**：⌘K 面板與 Toast 在玻璃上墊一層 75% 的表面色，否則後面的畫面透出來，結果難以閱讀（實測）。
* **不用玻璃**：側欄、清單列、專輯卡片、Standard 底部播放列、Up Next／Lyrics 分頁。它們貼在實色底上，玻璃沒有效果，也符合設計文件「不要每張卡片都像玻璃」。
* **怎麼改**：`DesignSystem/Materials/Glass.swift` 的 `finifyGlass`、頂部控制的 `TopBarSurface`（`StandardRootView.swift`）。

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
* **位置固定**：三段切換＋全螢幕（`ViewControls`）在三種模式都固定在視窗右上角，頂部列高度同為 52pt、右邊距 16pt。Standard 的 Now Playing 面板打開時也不會把它往左推；面板的關閉鈕因此移到面板左上角。
* **全螢幕**：按鈕讓整個視窗照目前的畫面進入 macOS 全螢幕（等同 ⌃⌘F）。原本「只顯示一首歌的全螢幕」（Immersive／Now Playing view）依使用者要求整個移除，連同播放列上的入口、Esc 處理與「全螢幕時隱藏控制項」設定。
* **移除**：Overflow 原本的 Wall／Flow／Recent 分段控制、側欄的 Overflow 項目、設定裡的 Layout 選項。Recent（最近播放專輯牆）不在三種模式內，先移除；首頁的 Recently Played 仍在。
* **程式**：內部仍是 `AppMode.standard／overflow` 加 `OverflowLayout.wall／flow`，使用者看到的是 `ViewMode`（`AppEnvironment.viewMode`）。
* **怎麼改**：`ModeSwitch`、`FullscreenButton`（`StandardRootView.swift`）、`ViewMode`（`AppEnvironment.swift`）。

## D21　用固定的開發者憑證簽章

* **問題**：原本用 ad-hoc 簽章（`CODE_SIGN_IDENTITY: "-"`），每次建置簽章都不同；鑰匙圈依簽章判斷是不是同一個 app，所以每次重建後打開都會跳「要使用鑰匙圈中的機密資訊」並要求系統密碼。
* **選擇**：Finify 與測試 target 改用 `Apple Development: you@example.com`（Team `XXXXXXXXXX`）手動簽章。簽章的身分固定為「app.finify.Finify＋這張憑證」，在提示中按一次「永遠允許」後，之後重建也不會再問。
* **限制**：仍未經 Apple 公證；給其他人用時第一次打開仍要在 Finder 按右鍵 → 打開。換電腦建置時，該電腦要有這張憑證，或改回 `"-"`。
* **怎麼改**：`project.yml` 的 `CODE_SIGN_IDENTITY`、`DEVELOPMENT_TEAM`。

## D22　佇列與歌詞共用浮層；Infinity／Cover Flow 的控制移到左上角

* **浮層**：三種模式的佇列與歌詞都用同一個浮在右側的 Liquid Glass 面板（`PlayerSidePanel`），頂部是「Up Next｜Lyrics」分頁、Clear（佇列分頁）與關閉。播放列上的歌詞、佇列按鈕切換分頁；切換模式時面板保持開啟。
* **移除**：Standard 原本的右側 Now Playing 欄（大封面、曲名、愛心）。封面與曲名在播放列上已有，佇列與歌詞改由浮層顯示。
* **左上角**：Infinity 與 Cover Flow 的左上角依序是「Sort by」、「Size」滑軌（Infinity 是封面牆 5 段密度，Cover Flow 是 6 段封面大小）、「Now Playing」（捲到正在播放的專輯）。原本右下角的大小滑桿與定位按鈕、Infinity 的 −／+ 移除。
* **大小與 Auto**：Infinity 的 5 段以列數定義（8／6／5／4／3 列），封面永遠剛好填滿上下。兩種模式預設是 Auto（依目前視窗尺寸計算、縮放視窗時即時更新）：Infinity 挑封面邊長最接近 200pt 的列數；Cover Flow 取視窗放得下的最大封面的 8 成，限制在 260～560pt。拖過大小滑軌後記住使用者的選擇；設定 → Appearance 可改回 Auto。
* **滑軌**：hover／拖曳時軌道 1.5 倍（3 → 4.5pt）、圓點 160%（11 → 18pt）。
* **怎麼改**：`Components/PlayerSidePanel.swift`、`OverflowRootView.topBar`、`SizeSlider`、`ProgressBar`。

## D23　Standard 改名為 Modern

* **選擇**：使用者看到的模式名稱由「Standard」改為「Modern」（右上角切換的提示、選單 ⌘1、設定「Open Finify in」、首次的模式選擇畫面）。程式內部仍叫 `standard`（`AppMode.standard`、`ViewMode.standard`、`StandardRootView`），避免大範圍改檔；先前決策紀錄中的「Standard」即指 Modern。

## D24　Infinity／Cover Flow 細節與 Magic sort

* **Cover Flow 換張**：位置與明暗一起用 0.9 秒、無回彈的曲線過渡（`Motion.flow`），標題淡入淡出 0.7 秒，營造沉靜感。
* **Infinity hover**：hover 不再顯示專輯資訊（資訊一律點了在專輯面板看），放大由 1.04 提高到 1.12。捲動或漂移時可能漏掉 mouseExited，造成一整排停在 hover 狀態；現在進入新的一張時會先清掉其他張。
* **播放列內距**：Modern 底部播放列與 Infinity／Cover Flow 浮動播放列的左右內距加大（16 → 24／32pt）。
* **封面牆與播放列的距離**：等於播放列到視窗底的距離（24pt），依播放列實際高度計算；沒在播放時只留 24pt。
* **大小滑軌**：兩端加 −／＋，一次一段。
* **Magic sort**：排序旁一顆「Magic」，條件有 Shuffle（隨機，再選一次重洗）、Rainbow（依封面平均色的色相排成彩虹，黑白灰放最後）、Light to Dark（依封面亮度）、By Genre（依曲風分群）、Time Travel（由最舊到最新）。封面顏色取自 BlurHash，不需下載圖片；曲風來自 Jellyfin 專輯的 Genres（舊快取在下次重新整理音樂庫後才有）。選了 Magic 會暫時取代一般排序，改一般排序時自動關閉。
* **怎麼改**：`Models/MagicSort.swift`（測試在 `MagicSortTests`）、`OverflowRootView` 的 `MagicSortMenu`、`SizeSlider`。

## D25　App 改名 Flione；測試版自動登入

* **名稱**：對外名稱改為 Flione（Flione.app、Dock、選單、登入畫面、設定、User-Agent、`flione://` 網址；舊的 `finify://` 仍可用）。模式選擇畫面的說明依《Flione Three Browsing Modes》改為 Presence／Depth／Visual。
* **保留**：bundle id `app.finify.Finify`、UserDefaults 鍵名與鑰匙圈 service 不變。改這些會讓所有設定、音樂庫快取與登入資訊遺失。
* **自動登入**：Debug 版與 `scripts/build-release.sh` 建出的測試版（`DEV_LOGIN`），啟動時若找得到這份原始碼 repo 的 `.secrets/`，就直接用它登入，不顯示登入畫面。只記路徑，不把登入資訊打包進 app；其他電腦上沒有這個路徑，照常顯示登入畫面。要建給別人的版本用 `FINIFY_PUBLIC=1 scripts/build-release.sh`。

## D26　按下播放立刻有反應（樂觀播放）

* **背景**：跨格式換曲的 0.1 秒停頓不處理（`docs/spikes/S2-gapless.md` 的「接受現況」）。改為縮短「按下播放到有反應」的等待：以前播放專輯要先等 server 回傳曲目（實測 0.3–1.7 秒），這段時間畫面完全沒變化。
* **做法**：`PlayerManager.play(album:)` 一按下就暫停目前的歌、用專輯資訊暫代目前曲目（`pending`），播放列、封面牆的「正在播放」、Now Playing 立刻換成這張專輯，按鈕顯示暫停；曲目取回後才真正開始播。緩衝中也算「播放中」，按鈕不會跳回「播放」。
* **出問題時才提示**：取不到曲目時顯示「Couldn't play …」並恢復成暫停；已開始播但緩衝超過 8 秒時提示檢查連線（不跳歌，連線恢復會自己播）。
* **暫代曲目**：id 以 `pending:` 開頭（`Track.isPlaceholder`），不能加愛心、不查歌詞；這段時間按暫停會取消這次播放，上一首／下一首不動作。
* **實測**（`-FinifyLatencyProbe`，隨機 5 張專輯）：畫面進入播放狀態 0–2 ms；取回曲目 0.3–1.7 秒；出聲 1.4–2.8 秒。
* **範圍**：專輯的播放按鈕（Home、Library、藝人頁、Infinity／Cover Flow）。藝人「全部播放」、曲風與音樂庫隨機播放、`flione://` 仍是取回後才播。

## D27　Modern 的背景光暈與側欄帳號區（參考 Kaset）

* **光暈**：主要內容後面依封面上色，做法參考 Kaset 的 `AccentBackground`。深色模式頂端是封面主色往下淡出，左上角再疊一層放射光；淺色模式只在頂端淡淡上色。顏色從 BlurHash 解成 2×1 取左右兩色，不額外下載圖片。
* **顏色來源**：只有專輯頁、playlist 頁，用該頁封面（與 Kaset 相同）。其他頁不上色：曾試過用正在播放的歌，封面偏灰時首頁整片變髒，也和首頁 Hero 衝突。光暈鋪在側欄與內容底下，側欄是半透明材質（ultraThinMaterial ＋ 30% 面板色），底色跟著內容頁的光暈變（與 Kaset 相同）；播放列維持原本的面板色。
* **開關**：沿用設定的「Ambient background」，Modern 與 Infinity／Cover Flow 共用。
* **側欄底部**：登入者頭像（Jellyfin 使用者圖片，沒有時顯示名字第一個字）、名稱、server 名稱；點一下打開帳號選單（重新整理音樂庫、設定、登出）。設定入口只放在選單裡，側欄不另放齒輪。
* **怎麼改**：`Features/Standard/ContentGlow.swift`、`StandardSidebar.swift` 的 `SidebarProfile`。

## D28　設定改成主視窗裡的卡片

* **選擇**：依使用者提供的參考圖，設定不再是獨立的 macOS 設定視窗，改成浮在主視窗上的卡片：標題、分頁膠囊（General／Appearance／Jellyfin）、關閉鈕；每列左邊是名稱與說明，右邊是開關、選單或膠囊按鈕。
* **打開方式**：⌘,、選單「Settings…」、Modern 側欄的帳號選單；Esc 或點卡片外面關閉。三種模式都能開。
* **開關**：自己畫，不用系統的 switch。系統的在視窗不在前景時會變灰，看不出開或關。
* **怎麼改**：`Features/Settings/SettingsView.swift`（`SettingsCard`）。

## D29　Infinity／Cover Flow 的底色與 Modern 一致

* **選擇**：Infinity／Cover Flow 的背景保留模糊封面的光暈，但壓暗用的漸層從黑色改成 Abyss（`#061426`，Modern 深色模式的底色）。原本壓上黑色後底色偏黑棕，現在和 Modern 一樣是深海藍。
* **怎麼改**：`Features/Overflow/AmbientBackground.swift`。

## D30　shuffle／repeat 用橘色；搜尋改成畫面正中央

* **橘色的範圍**：橘色只代表「正在播放」這件事（播放進度、正在播放的曲名與專輯）。shuffle、repeat 開啟時也用橘色，因為它們是播放模式；其他 active 狀態（側欄選取、開關、分頁）維持 Flione Blue。依品牌規範，橘色約占畫面 3%，不當成主要 UI 色。
* **播放列**：shuffle、repeat 與主要控制（上一首、播放／暫停、下一首）多拉開 16pt。
* **搜尋**：⌘K 時整個視窗暗下來（55% 黑），放大的搜尋框（72pt 高、24pt 字）固定在畫面正中央，結果往下展開，高度跟著結果數量變；游標自動放在輸入框。Modern 與 Infinity／Cover Flow 共用 `SearchOverlay`。
* **側欄框線**：選取外框、側欄右緣與帳號區上方的分隔線、頭像外框都壓淡。
* **Magic 排序**：原本把透明的 Menu 疊在膠囊上，選單位置偏掉，點選項會穿過去打到封面牆。改成 Menu 直接包住膠囊。

## D31　Infinity hover 動畫放慢、放柔

* **選擇**：放大倍率維持 1.12（D24）。原本是 0.35 秒 easeOut，起步太急；改成慢起步、長收尾的曲線（0.33, 0, 0.15, 1），進入 0.55 秒、離開 0.7 秒，讓退場比進場更從容。
* **前後層**：浮起時立刻置頂；降下時等縮回原尺寸才放回原層。原本一離開就降層，還在縮小的封面會被旁邊的封面突然蓋住，看起來很突兀。
* **怎麼改**：`AlbumWallView.swift` 的 `WallItem.applyState`。

## D32　Infinity hover 改用白光，不放大

* **選擇**：依使用者要求，hover 不再放大（取代 D24 的 1.12 倍）。改成封面四周泛出白色外光暈（半徑 18、85%）加一道 85% 白、1.5pt 的細邊，用 D31 的柔和曲線淡入（0.55 秒）淡出（0.7 秒）。hover 時仍會浮到上層，光暈才會蓋在相鄰封面上。
* **不變**：正在播放的專輯仍放大 1.08 倍加黑色陰影；鍵盤焦點的藍框不變。
* **怎麼改**：`AlbumWallView.swift` 的 `WallItem`（`glowLayer`、`edgeLayer`、`applyState`）。

## D33　中英雙語（String Catalog），保留多語系接口

* **做法**：介面文字用 String Catalog（`Resources/Localizable.xcstrings`），英文是原文，另有繁體中文（台灣用語）。建置時由 `SWIFT_EMIT_LOC_STRINGS` 抽出字串。自訂元件（按鈕、設定列、提示、選單項目）的文字參數改成 `LocalizedStringResource`，字面字串自動可翻譯；歌名、專輯名這類資料照原樣顯示。英文的單複數用 catalog 的 plural variation。
* **不翻譯**：Modern、Infinity、Cover Flow、Magic、Jellyfin、LRCLIB 等名稱，以及語言名稱本身（English、繁體中文）。
* **切換**：設定 → 一般 → 語言（跟隨系統／English／繁體中文）。選擇存在 `FinifyLanguage`，並寫進 app 自己的 `AppleLanguages`，所以會記住；macOS 在啟動時套用語言，因此切換後出現「重新啟動」按鈕。
* **新增語言**：在 catalog 補上該語言的翻譯，再在 `AppLanguage`（`Core/Localization/AppLanguage.swift`）加一個 case。

## D34　設定依模式分頁；設定卡片固定大小

* **分頁**：設定分成一般、Modern（主題、背景光暈）、Infinity（封面圓角、專輯大小、漂移、背景光暈）、Cover Flow（封面圓角、封面大小、光暈亮度、兩側封面變暗）、伺服器（英文 Server）。分頁放在標題下方一整列。深淺色只影響 Modern；Modern 與 Infinity 的背景光暈是兩個獨立開關（迷你播放器跟著 Modern）。
* **Infinity 圓角**：關掉時封面是直角，封面之間沒有間距。**漂移**：關閉／慢（0.5×）／一般／快（2×）。
* **Cover Flow 變暗**：中間的封面永遠最亮，兩側封面依離中間的距離變暗，程度可選關閉／輕微／中等／強（0／0.15／0.25／0.45），中等就是原本的效果。**光暈亮度**：移動時背景光暈最亮；停下約 0.8 秒後只有背景光暈慢慢變暗（1.4 秒，封面與文字不變），一移動 0.3 秒亮回來。程度可選不變暗／輕微／中等／強（光暈剩 100%／70%／50%／10%），預設不變暗（見 D35）。
* **設定卡片**：固定 640×600，切換分頁時位置不變。

## D35　Cover Flow 背景光暈一律用 BlurHash

* **問題**：連續換張時背景光暈較亮，停下來後變暗。
* **原因**：背景的模糊封面依視窗大小要 1600px 大圖，幾乎不在快取裡。下載完成前先顯示 BlurHash；連續換張時每張都在大圖到之前被換掉，所以移動中看到的都是 BlurHash，停下來後大圖載完才淡入取代。BlurHash 在線性光空間平均顏色、沒有暗部細節，比真的封面模糊後亮：用 7 張真實封面離線模擬，平均亮度 104 對 90，最多差 36。
* **選擇**：背景一律用 BlurHash（32×32 解碼後放大），不再下載大圖，換張也不用每次下載 1600px 圖；模糊 110 之後看不出解析度差別。停下來後要不要變暗、暗多少改由「光暈亮度」設定控制。
* **沒改**：Infinity 的模糊封面背景（`AmbientBackground`）仍用真的封面，只在換歌時才變，沒有這個問題。

## D36　Infinity 頂部的「自動捲動」開關

* **選擇**：「正在播放」右邊多一顆開關。打開時封面牆一直自動捲動，滑鼠在牆上、移動滑鼠都不停；手動拖曳或捲動時暫停，之後緩緩加速接上。速度沿用設定裡的漂移速度；就算漂移設為關閉，打開開關也會捲動。關閉時維持原本行為（游標離開封面牆才漂移）。狀態會記住（`FinifyWallAutoScroll`）。
* **樣式**：與「正在播放」相同的膠囊；開啟時圖示實心並用 Flione Blue（一般的開啟狀態，不用代表播放的橘色）。
