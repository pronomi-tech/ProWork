# ProWorkTests

Bu klasör fiyatlandırma servislerinin XCTest testlerini içerir.

## UI bileşeni testleri — durum (code review LOW)

- `ProWorkNumberFieldSanitizeTests` — sayısal input sanitizer için pure
  unit testler (locale ayrımı, fraction clamp, thousands separator
  düşürme, çoklu separator). Sanitize fonksiyonu `ProWorkNumberField`
  içinde static helper olarak yeniden yapılandırıldı.
- `ProWorkToastStoreTests` — toast queue için unit testler (trim, boş
  mesaj atma, append sırası, dismiss, style ayrımı).
- **`ProWorkTextField`, `ProWorkCheckbox`, `ProWorkDateField`** — bu
  bileşenler saf SwiftUI view yapıları; mantık taşımıyor. Anlamlı bir
  birim test üretmek için ya snapshot testing (pointfree-st/SnapshotTesting)
  ya da ViewInspector eklenmesi gerekiyor. Her ikisi de eksternal
  dependency gerektiriyor; ayrı bir test infrastructure görevi olarak
  takip edilmeli.

> **Code review D40 — açık:** Xcode projesinde `ProWorkTests` adında bir
> target oluşturuldu (build config'leri mevcut) ancak bu klasördeki test
> dosyaları henüz target üyeliğine eklenmedi. Yeni eklenen
> `EdgeCaseTests.swift` ve `ExchangeRateOperationalRateTests.swift` da
> dahil tüm dosyalar için Xcode tarafından bir kez **Add Files to
> ProWorkTests** + target membership tikinin atılması gerekir. Aksi halde
> `xcodebuild test` komutu hiçbir dosyayı koşturmaz.

## Test target'ı bağlama

Henüz Xcode projesinde test target yok. Eklemek için:

1. Xcode'da `ProWork.xcodeproj` aç
2. Proje navigatorde **ProWork**'a tıkla → sağda **+** ile **New Target**
3. **Unit Testing Bundle** seç
4. **Product Name**: `ProWorkTests`
5. **Target to be Tested**: `ProWork`
6. Yarat
7. Yeni oluşan `ProWorkTests` grubuna sağ tıkla → **Add Files to "ProWork"** → bu klasördeki `.swift` dosyalarını ekle (file system synchronized değilse)

Alternatif: Xcode 16+ filesystem-synchronized hedef olarak kurulduğu için klasör otomatik tanınır.

## Çalıştırma

```bash
xcodebuild test \
  -project ProWork.xcodeproj \
  -scheme ProWork \
  -destination 'platform=macOS'
```

Veya Xcode'da `⌘U`.

## Kapsam

| Dosya | Servis | Test sayısı |
|---|---|---|
| `MinimumWindowApplierTests.swift` | §4 ceil hesabı | 7 |
| `TimeWindowSplitterTests.swift` | §5 segment bölme | 6 |
| `PriceListResolverTests.swift` | §3 öncelik sırası | 5 |
| `VATCalculatorTests.swift` | 4 katman çözümleme | 4 |
| `BillingCalculatorTests.swift` | uçtan uca | 3 |
