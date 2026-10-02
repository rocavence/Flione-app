# Finify

> Your Music. Your Server. Your Experience.

Finify 是 Jellyfin 的 macOS 原生音樂播放器。兩種平級的使用模式：

* **Standard**：完整的音樂 App，可瀏覽、搜尋、建立播放佇列。
* **Overflow**：把整個音樂庫變成封面牆，以封面為主的沉浸式體驗。

## 需求

* macOS 14 以上
* Xcode 26 以上
* [XcodeGen](https://github.com/yonaskolb/XcodeGen)：`brew install xcodegen`
* 一台 Jellyfin server（測試過 12.1）

## 開始

```sh
xcodegen generate          # 由 project.yml 產生 Finify.xcodeproj
open Finify.xcodeproj      # 選 Finify scheme 執行
```

第一次啟動會要求連線 Jellyfin。Server 欄位可以只填主機名稱（例如 `mediabox`），Finify 會自動嘗試 `http://mediabox:8096`。

`Finify.xcodeproj` 不進版控；修改專案設定請改 `project.yml`。

## 測試

```sh
xcodebuild -project Finify.xcodeproj -scheme Finify test
```

`RepositoryIntegrationTests` 會連真實 server。需要在 repo 根目錄建立 `.secrets/`（已排除在 git 之外）：

```text
.secrets/jellyfin.env   JELLYFIN_URL=、JELLYFIN_USER=、JELLYFIN_PASSWORD=
.secrets/session.env    JELLYFIN_TOKEN=、JELLYFIN_USER_ID=
```

沒有 `.secrets/` 時整合測試會自動略過。

## 專案結構

```text
Finify/
├── App/            進入點、AppEnvironment、選單快捷鍵
├── Core/
│   ├── Jellyfin/   API client、DTO、MusicRepository
│   ├── Cache/      ImagePipeline（記憶體＋磁碟）、BlurHash
│   ├── Persistence/ Keychain、音樂庫快照
│   └── Platform/   Now Playing、媒體鍵、鍵盤
├── DesignSystem/   色彩、字級、間距、圓角、動態、陰影、Reicon
├── Components/     ArtworkView、按鈕、曲目列、播放列、Toast…
├── Features/
│   ├── Onboarding/ 連線、mode 選擇
│   ├── Standard/   Home、Library、Album、Artist、Search
│   ├── Overflow/   Album Wall、Album Flow、Fullscreen
│   └── Settings/
└── Player/         PlayerManager（AVQueuePlayer）、PlayQueue
Spikes/             技術驗證程式（不隨 app 出貨）
scripts/            Reicon 與 app icon 產生腳本
docs/               規格、roadmap、決策紀錄、驗證報告
```

## Icon

UI icon 一律使用 [Reicon](https://github.com/dqev/reicon)。新增 icon：

1. 在 `scripts/reicon/icons.txt` 加一行 Reicon 名稱
2. 執行 `python3 scripts/reicon/generate.py`
3. 在程式中使用 `FinifyIcon(.名稱)`

## 開發用啟動參數（DEBUG）

| 參數 | 作用 |
| ---- | ---- |
| `-FinifySecrets <repo>/.secrets` | 從 `.secrets/` 讀登入資訊，不用 Keychain |
| `-FinifyStartMode standard\|overflow` | 直接進入指定 mode |
| `-FinifyMuted YES` | 播放音量 0 |
| `-FinifyDemoPlay "<專輯名>"` | 啟動後播放該專輯 |
| `-FinifyDemoOpen "<專輯名>"` | 啟動後打開該專輯 |
| `-FinifyDemoSearch "<關鍵字>"` | 啟動後打開搜尋 |
| `-FinifyDemoImmersive YES` | Overflow 進入 Fullscreen |
| `-FinifyBenchWall <輸出.json>` | Album Wall 捲動效能量測 |

## 文件

* [`docs/FINIFY.md`](docs/FINIFY.md)：產品願景
* [`docs/EXECUTION-SPEC.md`](docs/EXECUTION-SPEC.md)：實作規格（衝突時以此為準）
* [`docs/ROADMAP.md`](docs/ROADMAP.md)：分期
* [`docs/DECISIONS.md`](docs/DECISIONS.md)：規格未定義處的決策與修改方式
* [`docs/spikes/`](docs/spikes/)：技術驗證結果
