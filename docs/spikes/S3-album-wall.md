# S3：Album Wall 萬張專輯驗證

日期：2026-10-02
程式碼：`Spikes/AlbumWall/`（獨立 target `AlbumWallSpike`，不隨 app 出貨）

## 結論

**Album Wall 採用 `NSCollectionView`，以 `NSViewRepresentable` 包進 SwiftUI。**

* AppKit 版在 1 萬張與 1,700 張下捲動都沒有掉 frame；SwiftUI `LazyVGrid` 版兩種規模都會掉 frame。
* 記憶體有上限，上限由 artwork memory cache 的 byte budget 決定，不會隨捲動時間或專輯數增加。
* 建議 memory cache budget 先設 **100 MB**，正式實作後再依實機調整。

## 測試方法

* 假資料：300 張 600×600 JPEG（每張約 125 KB），1 萬張專輯循環使用；cache key 用 album id，所以視為不同圖片。
* 模擬 Jellyfin 回應時間：30–150 ms。
* 解碼：ImageIO downsample，依 density 請求 240 / 360 / 520 px（2x）。
* 視窗 1440×900，以 display link 自動捲動並記錄每一 frame：
  * 2–22 秒：從頂端捲到底
  * 22–31 秒：切換 density（medium → large → small → medium）
  * 31–41 秒：捲回頂端
* 1 萬張在 20 秒內捲完，約每秒 13,000 pt，比實際手勢快，屬於壓力測試；1,700 張的速度較接近實際使用。
* 測試螢幕為 60 Hz，120 Hz ProMotion 尚未測。

## 結果

掉 frame 以 hitch time 計算（每秒累計超出 frame 時間的毫秒數）。Apple 的參考標準：< 5 ms/s 不易察覺，> 10 ms/s 明顯卡頓。

| 方案 | 專輯數 | 往下捲 hitch | 往上捲 hitch | 切換 density 最長 frame | 記憶體 peak |
| ---- | -----: | -----------: | -----------: | ----------------------: | ----------: |
| AppKit | 10,000 | 0 ms/s | 0 ms/s | 37 ms | 367 MB |
| SwiftUI | 10,000 | 11.7 ms/s | 22.7 ms/s | 46 ms | 379 MB |
| AppKit | 1,700 | 0 ms/s | 0 ms/s | 17 ms | 364 MB |
| SwiftUI | 1,700 | 9.7 ms/s | 1.2 ms/s | 41 ms | 456 MB |

以上 cache budget 皆為 150 MB。

SwiftUI 版在 1 萬張時有 72% 的圖片請求在完成前被取消，快速捲動時使用者大多只會看到 placeholder。

## 記憶體上限

AppKit 版，1 萬張，不同 cache budget：

| Budget | 捲動中穩定值 | Peak |
| -----: | -----------: | ---: |
| 150 MB | 約 325 MB | 387 MB |
| 30 MB | 約 95 MB | 216 MB |

* 捲動中的記憶體維持穩定，不會持續增加。
* Peak 出現在切換到 large density 時，因為大尺寸縮圖每張約 1 MB。
* 未啟動捲動時的基準約 60 MB。

## 對實作的影響

* `ArtworkView` 仍是唯一的 artwork 元件；Album Wall 的 cell 由 AppKit 管理，但 artwork 載入與 cache 共用同一個 pipeline。
* Cell 離開畫面時取消圖片請求（`prepareForReuse`）。
* 待正式實作時補上：依捲動方向預載、BlurHash placeholder、disk cache。
