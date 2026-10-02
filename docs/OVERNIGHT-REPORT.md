# 夜間進度報告（2026-10-03 00:00–）

## 一句話

MVP 的 26 個 Task 中 24 個完成，另外提前做了 9 項 V1 功能。
每項都用你的 Jellyfin（MediaBox，1,426 張專輯、17,180 首）實際操作並截圖驗證過；
38 個自動測試全部通過。

## 早上先做這 3 件事（約 10 分鐘）

1. 打開 app：`open dist/Finify.app`（或在 Xcode 開 `Finify.xcodeproj` 執行）。
2. 登入：Server 已預填 `http://mediabox:8096`，輸入帳號密碼。
3. 看截圖：`docs/screenshots/` 有 8 張主要畫面。

接著讀本文件的「需要你決定的事」。

## 完成項目

### MVP（規格 §30 的 Task Queue）

| 範圍 | 內容 |
| ---- | ---- |
| 連線 | 只輸入主機名稱就能連線（自動嘗試 8096 port）；登入資訊存 Keychain；登入過期時回到登入畫面並說明原因 |
| Standard | Home（最近播放、最近加入、Quick Picks）、Library（專輯、藝人、歌曲）、專輯頁、藝人頁 |
| 搜尋 | ⌘K，兩個 mode 共用；藝人、專輯、playlist、歌曲分組；方向鍵與 Return 操作 |
| 播放 | 無縫換曲、佇列（插播、加入、移除、拖曳排序、清除）、shuffle、repeat、音量 |
| macOS | 媒體鍵、Now Playing（含封面）、Space／⌘←→／⌘K／⌘1⌘2 等快捷鍵、選單 |
| Overflow | Album Wall（NSCollectionView、pinch 縮放、正在播放的專輯浮起）、Album Flow、Fullscreen、ambient 背景 |
| 品質 | 每個非同步畫面都有 loading、空、錯誤與重試；VoiceOver 標籤；Reduce Motion；增加對比；鍵盤操作 |

未完成：TASK-026 Release（需要開發者帳號簽章與公證）；TASK-024 無障礙沒有做完整的 VoiceOver 實機走查。

### 提前做的 V1（D12）

Favorites、Playlists、歌詞、Genres、Album Flip、浮動迷你播放器（Always on Top）、選單列迷你播放器、
Overflow 最近播放牆、Wall 的 Tiny／Huge 尺寸、重新開啟時恢復播放佇列、設定視窗、
Overflow 專輯面板的「同藝人其他專輯」。

每項都是獨立 commit（訊息開頭 `V1：`），不要的話可以單獨 `git revert`。

## 實測數據

| 項目 | 結果 | 目標 |
| ---- | ---- | ---- |
| 啟動到出現視窗 | 0.22–0.30 秒 | < 2 秒 |
| 啟動到首頁資料載入完成 | 0.83–1.03 秒 | — |
| Album Wall 捲動（1,426 張，Medium／Large） | 0 掉 frame | 60 fps |
| Library 專輯格線捲動 | 往下 0–8 ms/s、往上 11–27 ms/s（每次量測不同；改用 NSCollectionView 前是 240 ms/s） | 60 fps |
| 歌曲清單捲動（17,180 首） | 2.5–4.2 ms/s | 60 fps |
| 同格式換曲 | 0–0.9 ms（24 次中 21 次） | 無縫 |
| MP3 與 AAC 互換 | 85–101 ms | 無縫 |

掉 frame 的單位是每秒累積卡住的毫秒數；> 5 ms/s 開始感覺得到，> 10 ms/s 明顯卡頓。
Library 格線往上捲仍有輕微卡頓，見「已知問題」。

## 我替你做的決定

完整理由與修改方式在 `docs/DECISIONS.md`。重點：

| # | 決定 | 不同意時 |
| -- | ---- | -------- |
| D01 | 播放引擎用 AVQueuePlayer | 改 `Player/PlayerManager.swift` |
| D02 | Album Wall 用 NSCollectionView | — |
| D04 | 音樂庫快取用 JSON 快照，不用規格寫的 SwiftData | 改 `LibraryStore.swift` |
| D06 | 藝人圓形、專輯方形；藝人沒照片時用專輯封面 | 改 `LibraryCards.swift` |
| D07 | Standard 用頂部導覽列，不用 sidebar | 改 `StandardRootView.swift` |
| D09 | 品牌色 Ember `#FF6A3D`、暖色中性色 | 改 `FinifyColor.swift` |
| D10 | 暫定 app icon：3×3 專輯格組成「F」 | 換掉 `AppIcon.appiconset` 的 PNG |
| D11 | Wall 單擊開面板、雙擊播放 | 單擊有約 0.4 秒延遲，可改成單擊只選取 |
| D13 | Playlist 一律以完整狀態寫入 | Jellyfin 12.1 改名會被覆蓋，所以這樣做 |

## 需要你決定的事

1. **跨格式換曲有 0.1 秒停頓。** 你的 library 有 24% 的專輯混用 MP3 與 AAC，專輯內 9% 的換曲是跨格式。
   選項：接受現況、整理音樂庫統一格式，或花 2–3 天改用自行解碼的播放器。見 `docs/spikes/S2-gapless.md`。
2. **串流網址帶 access token（D14）。** 自用沒問題；上架 App Store 前要改。
3. **App icon 與品牌色都是暫定版。** 要正式設計時直接替換即可。
4. **你的密碼曾出現在對話紀錄中**，建議改一組，並把新密碼更新到 `.secrets/jellyfin.env`。

## 已知問題與沒做的事

* Library 專輯格線：視窗 1360 寬時往上快速捲動有輕微卡頓（11–27 ms/s）；視窗 1040 寬時除了封面第一次載入，其他都在 0–3 ms/s。
  試過拿掉陰影、只在 hover 時建立播放鈕，都沒有可量測的改善，所以沒有保留。要根治可能得把卡片改成純 AppKit（像 Album Wall 那樣）。
* 歌詞：你的 server 目前沒有歌詞檔，同步歌詞的畫面只用單元測試驗證，沒有實際看過。
* 規格 V1 中沒做：系統通知（會跳權限詢問視窗，無人值守時不能做）、拖放、分享、Expanded Player。
* 120 Hz ProMotion 螢幕沒測（這台外接螢幕是 60 Hz）。
* 02:40 左右外接螢幕解析度改變（變成 1920×1080）之後，模擬按鍵無法送進 app，所以「Fullscreen 中按 Esc 先關歌詞」沒有再用自動化驗證；邏輯與先前驗證過的 Esc 離開全螢幕相同。
* 很多最近加入的專輯在 Jellyfin 沒有封面（顯示成文字方塊），是音樂庫的 metadata 問題，可在 Jellyfin 重新抓取 metadata。
* Release build 只有本機簽章；給別人用需要開發者帳號簽章與公證。

## 對你的 Jellyfin 做了什麼

* **都已還原。** Playlist 與喜愛的測試只在名為「Finify Test…」的暫存資料上寫入，結束時刪除；喜愛的狀態測試後切回原狀。目前 server 有原本的 5 個 playlist、0 個喜愛項目。
* **播放紀錄有變動，沒有自動還原。** 01:50 之後的播放都是我的測試：The Dark Side of the Moon、Disco Kandi The Mix、Live aus Berlin（無縫播放量測各 8–17 首）、OK Computer、In Rainbows、Moon Safari、Discovery、Addison Road。
  23:17–23:28 與 00:55 的播放（不想放手、I Like Chopin、Easy Tempo、Rise、21）是你自己的。
  沒有自動清除，因為「標為未播放」會一併清掉這些曲目原本的播放次數。要清除的話，在 Jellyfin 網頁版對這幾張專輯按「標為未播放」。
* 有一次測試失敗留下暫存 playlist，我發現後已刪除，之後在測試開頭加了清除殘留的步驟。

## 過程中發現並修正的重要問題

* Now Playing 封面在背景 queue 被呼叫，Swift 6 執行期檢查導致 crash。
* Ambient 背景撐大 Overflow 版面，頂部列與播放列被推出畫面。
* 兩輪獨立 code review 共找到 31 個問題，已修正，包括：開始播放新專輯時 repeat 被重設、
  repeat 開啟時遇到失敗會無限跳歌、playlist 連續編輯時較早的請求蓋掉新的、
  同一首歌加入佇列兩次時 shuffle 錯亂、佇列最後一列「下移」會 crash。

## 怎麼繼續開發

* 規格與目前狀態：`docs/EXECUTION-SPEC.md` §34–35
* 執行測試：`xcodebuild -project Finify.xcodeproj -scheme Finify test`
* 打包：`scripts/build-release.sh`
* 開發用啟動參數（直接進入指定畫面、靜音播放、效能量測）：`README.md`
