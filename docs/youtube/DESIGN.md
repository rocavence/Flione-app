# Flione for YouTube Music：設計

分支：`youtube-music`。main 不受影響，驗證可行後再決定是否合併。

## 目標

Flione 除了 Jellyfin，也可以用 Google 帳號登入 YouTube Music，用同樣的三種模式（Modern、Infinity、Cover Flow）瀏覽與播放。

## 不限制 Premium

原本規劃只開放 YouTube Premium 帳號，後來依使用者決定取消（2026-10-03）：登入成功就能使用。

非 Premium 帳號可能遇到的限制（第二階段做播放時確認實際行為）：

- 網頁播放器插播廣告；Flione 的播放列不處理廣告
- 不能背景播放，可能與 Flione「關掉視窗也繼續播」的行為衝突

## 登入

1. 登入畫面的主要按鈕是「用 Google 帳號登入 YouTube Music」；「改用 Jellyfin 伺服器」是次要選項，點了才展開原本的表單。
2. 按下主要按鈕，開一個獨立的瀏覽器視窗（WKWebView），載入 Google 正式登入頁：
   `accounts.google.com/ServiceLogin?service=youtube…&continue=…music.youtube.com`
   兩步驟驗證由 Google 的頁面處理；通行金鑰無法使用（見下一點）。
3. 視窗使用 Safari 的 User-Agent，避免 Google 判定為「不安全的瀏覽器」而拒絕登入。
   頁面載入前先藏起通行金鑰（WebAuthn）API：一般 app 的 WKWebView 沒有 Apple 只發給瀏覽器的通行金鑰權限，Google 偵測到支援就會走通行金鑰，系統在背景拒絕後頁面停在「請稍候片刻」（實測）。藏起來後 Google 改走密碼與兩步驟驗證。
4. 頁面導到 `music.youtube.com`，且 cookie 中有 `SAPISID` 時，視為登入成功，視窗自動關閉。
5. 登入資訊就是這些 cookie，存在 app 自己的 WebKit 資料（`WKWebsiteDataStore.default()`），不另外保存密碼。登出時清除 Google 與 YouTube 的 cookie。

不使用 Safari：Safari 的 cookie 只屬於 Safari，Flione 讀不到，無法代表使用者呼叫 YouTube Music。

## 登入後的帳號資訊

登入後呼叫 InnerTube 的帳號選單（`youtubei/v1/account/account_menu`，client `WEB_REMIX`）取得帳號名稱，同時確認 cookie 有效。呼叫失敗時顯示錯誤與重試。Debug 版會把回應存到 `/tmp/flione-youtube-account-account_menu.json` 供分析。

## 呼叫 YouTube Music

- InnerTube API：`https://music.youtube.com/youtubei/v1/<endpoint>?prettyPrint=false`
- 標頭：`Cookie`、`Authorization: SAPISIDHASH <時間>_<sha1(時間 SAPISID 來源)>`、`Origin` 與 `X-Origin: https://music.youtube.com`、`X-Goog-AuthUser: 0`
- 做法參考 Kaset（MIT，見 `docs/ACKNOWLEDGEMENTS.md`）

## 播放（第二階段）

YouTube Music 的音訊有加密與簽章保護，AVQueuePlayer 無法直接播放。做法與 Kaset 相同：在隱藏的 WKWebView 裡跑 YouTube Music 網頁播放器，Flione 的播放列透過 JavaScript 控制播放、取得進度。

因此 `PlayerManager` 要拆出播放引擎介面，Jellyfin 用 AVQueuePlayer、YouTube Music 用網頁播放器。佇列、「按下立刻播」、媒體鍵、Now Playing 兩邊都要能用。

## 資料對應（第二階段）

| Flione | YouTube Music |
| ---- | ---- |
| 音樂庫專輯 | 音樂庫中收藏的專輯 |
| 藝人 | 訂閱的藝人 |
| 播放清單 | 音樂庫的播放清單 |
| 最愛 | 喜歡的歌曲 |
| 首頁的最近播放、推薦 | 首頁的對應區塊 |
| 搜尋 | 搜尋 |

YouTube Music 使用者的收藏專輯通常比 Jellyfin 音樂庫少，Infinity 的封面牆可能不夠滿，需要另外設計（例如混入推薦專輯）。

## 風險

- **條款**：YouTube 條款不允許非官方用戶端，自用為主，**不能上架 App Store**。
- **會壞**：InnerTube 沒有公開，Google 改版就可能失效，需要持續維護。
- **帳號**：理論上有被限制的風險，目前沒有已知案例，但無法保證。

## 分階段

| 階段 | 內容 | 狀態 |
| ---- | ---- | ---- |
| 1 | 登入畫面、瀏覽器登入視窗、登入判斷、帳號資訊 | 完成（2026-10-03 實測登入成功） |
| 2 | 網頁播放器引擎，在 Flione 播出一首歌 | 未開始 |
| 3 | 音樂庫、搜尋、播放清單接上 Modern／Infinity／Cover Flow | 未開始 |
