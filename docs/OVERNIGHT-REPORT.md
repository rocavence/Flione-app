# 夜間進度報告（2026-10-03）

> 這份是進行中的紀錄，結束時會整理成最終版。

## 目前狀態

第一條 vertical slice 已完整跑通，並以真實 Jellyfin（MediaBox，1,426 張專輯）逐步截圖驗證：

```text
Launch → Connect → Home → Album → Play → Mini Player
→ Overflow → Album Wall → 單擊打開專輯 → 雙擊播放 → Fullscreen
```

## 完成項目

* S1 Reicon、S2 無縫播放、S3 萬張 Album Wall 三個技術驗證
* Design System token、共用元件
* Jellyfin 資料層、Keychain、播放、佇列、媒體鍵、Now Playing
* Standard：Home、Library、Album、Artist、⌘K 搜尋、mini player、queue
* Overflow：Album Wall、Album Flow、Fullscreen、ambient 背景

## 過程中發現並修正的問題

* Now Playing 封面在背景 queue 被呼叫，Swift 6 執行期檢查導致 crash
* Ambient 背景撐大 Overflow 版面，頂部列與播放列被推出畫面
* Album Wall 用方向鍵移動時每格都會打開專輯；雙擊的第一下會先打開專輯
