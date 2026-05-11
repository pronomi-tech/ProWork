# ProWork

## English

**ProWork** is a native **macOS time tracking, todo management, reporting, and billing app** built for freelancers, consultants, software teams, agencies, and technical service businesses. It combines a **Kanban task board**, **work session timer**, **manual time entry**, **customer and project management**, **billing automation**, and **exportable service statements** in one local-first desktop app.

If you are looking for a **macOS billable hours tracker**, **client work tracking software**, **project-based time tracker**, or a **SwiftUI productivity app** for professional service work, ProWork is designed for that workflow.

### What ProWork Covers

ProWork connects daily work tracking with operational and financial reporting:

- Manage **customers**, **projects**, and customer-linked project structures
- Organize tasks on a **Kanban-style todo board**
- Track time with **start/stop timers** or **manual work session entries**
- Separate **billable**, **administrative**, **manual**, and **automatic** work
- Generate **customer, project, and task reports**
- Build **billing runs** from tracked work
- Apply **price lists**, **VAT rules**, **billing windows**, and **exchange rates**
- Export service statements to **PDF, CSV, Excel, and JSON**

### Feature Overview

#### Work Management

- Customer management with pricing-related defaults
- Project management under customers
- Task categories and workflow statuses
- Quick task capture and detailed task forms
- Kanban board with drag-and-drop status changes
- Estimated duration, planned date, due date, notes, and billable/admin flags

#### Time Tracking

- Start and stop work directly from todo cards
- Single active timer protection to avoid parallel session errors
- Manual work session entry for missed tracking
- Work session history per task and across the whole app
- Notes, customer context, project context, and status context on sessions
- Menu bar quick timer for faster desktop usage
- Idle auto-stop / pause workflow for unattended timers

#### Billing and Financial Controls

- Draft and finalized billing runs
- Payment tracking and balance visibility
- Global, customer-level, and project-level price lists
- Minimum billing window logic
- Business hours, after-hours, weekend, and holiday-aware billing rules
- VAT rule management
- Exchange rate management with **TCMB**, **global**, and **manual** sources
- Company profile, logo, payment terms, and service document settings
- Customizable PDF template for exported service statements

#### Reports and Administration

- Reporting dashboard with date, customer, and project filters
- Customer reports with time and amount breakdowns
- Project reports for period-based totals
- Task reports with manual-entry visibility
- Organization members, roles, and customer-based access control
- User-selectable SQLite data file for local storage and backup-friendly workflows
- Launch-at-login, menu bar, language, date, time, and font size settings

### Typical Workflow

1. Add a customer and create one or more projects.
2. Create todos, assign categories and statuses, and start working from the board.
3. Track time automatically or add manual sessions later.
4. Review reports, generate a billing run, record payments, and export the final document.

### Built For

- Freelancers
- Consultants
- Software developers
- IT support teams
- Agencies
- Technical service providers
- Small businesses that bill by time, project, or service window

### Tech Stack

- **Swift**
- **SwiftUI**
- **SQLite3**
- Native **macOS** desktop UI and menu bar integration
- Local-first architecture with user-selected database files

### Download / Installation

- Download the latest release from the GitHub Releases page.
- Current public preview builds are distributed **without Apple code signing and without notarization**.
- On first launch, macOS may block the app with a security warning.

If macOS blocks the app:

1. Open the downloaded app with **Right Click > Open**.
2. If needed, go to **System Settings > Privacy & Security** and choose **Open Anyway**.
3. Launch the app again after confirming the warning.

### Run Locally

```bash
git clone https://github.com/pronomi-tech/ProWork.git
cd ProWork
open ProWork.xcodeproj
```

Open the `ProWork` scheme in Xcode and run it on macOS. Billing-related XCTest files are included under [`ProWorkTests`](ProWorkTests).

### Project Status

ProWork is under active development. The current codebase already includes the core workflow for **task management, time tracking, reporting, billing preparation, pricing, exchange rates, PDF exports, and operational settings**.

### License

This project is licensed under **GNU GPLv3**.

You can:

- Use the project
- Modify the source code
- Share the original or your modified version
- Use it in personal or commercial work

You must:

- Keep the project under **GPLv3** if you redistribute it
- Share the **source code** if you distribute the app or a modified version
- Keep copyright and license notices
- Clearly state if you changed the code

You cannot:

- Redistribute this project or a derived version as **closed-source / proprietary**

There is **no warranty**. See [LICENSE](LICENSE) for details.

## Türkçe

**ProWork**, serbest çalışanlar, danışmanlar, yazılım ekipleri, ajanslar ve teknik hizmet şirketleri için geliştirilmiş yerel bir **macOS zaman takibi, yapılacak iş yönetimi, raporlama ve faturalandırma uygulaması**dır. Uygulama; **Kanban görev panosu**, **çalışma zamanlayıcısı**, **manuel süre girişi**, **müşteri ve proje yönetimi**, **faturalandırma akışları** ve **dışa aktarılabilir hizmet dökümleri**ni tek bir masaüstü uygulamasında birleştirir.

Bir **macOS faturalandırılabilir saat takip uygulaması**, **müşteri bazlı zaman takip uygulaması**, **proje bazlı çalışma kaydı aracı** veya profesyonel hizmet ekipleri için bir **SwiftUI tabanlı verimlilik uygulaması** arıyorsanız, ProWork bu kullanım senaryosuna odaklanır.

### ProWork Neleri Çözer

ProWork günlük operasyon ile finansal çıktıyı aynı akışta buluşturur:

- **Müşteri** ve **proje** yönetimi yapar
- İşleri **Kanban tipi yapılacaklar panosunda** toplar
- **Başlat/durdur zamanlayıcı** ve **manuel çalışma kaydı** sunar
- **Faturalandırılan**, **idari**, **manuel** ve **otomatik** süreleri ayırır
- **Müşteri**, **proje** ve **iş** raporları üretir
- Takip edilen sürelerden **hizmet dökümü / faturalandırma kaydı** oluşturur
- **Fiyat listeleri**, **KDV kuralları**, **minimum pencere** ve **döviz kurları** uygular
- Çıktıları **PDF, CSV, Excel ve JSON** olarak dışa aktarır

### Özellikler

#### İş ve Görev Yönetimi

- Ücretlendirme varsayımlarıyla birlikte müşteri kayıtları
- Müşteriye bağlı proje kartları
- Görev kategorileri ve iş akışı statüleri
- Hızlı görev ekleme ve detaylı görev formları
- Sürükle-bırak destekli Kanban panosu
- Tahmini süre, plan tarihi, termin tarihi, not ve faturalanabilir/idari alanları

#### Zaman Takibi

- Görev kartları üzerinden doğrudan başlat/durdur
- Paralel aktif süre açılmasını engelleyen tek aktif zamanlayıcı koruması
- Unutulan kayıtlar için manuel süre girişi
- Görev bazlı ve uygulama genelinde çalışma geçmişi
- Oturumlarda not, müşteri, proje ve statü bağlamı
- Hızlı erişim için menü çubuğu zamanlayıcısı
- Bilgisayar boşta kaldığında otomatik durdurma / duraklatma akışı

#### Faturalandırma ve Finans

- Taslak ve kesinleşmiş hizmet dökümleri
- Ödeme takibi ve bakiye görünümü
- Genel, müşteri bazlı ve proje bazlı fiyat listeleri
- Minimum faturalandırma penceresi kuralları
- Mesai içi, mesai dışı, hafta sonu ve resmî tatil duyarlılığına sahip ücretlendirme
- KDV kural yönetimi
- **TCMB**, **küresel** ve **manuel** kaynaklı döviz kuru yönetimi
- Şirket profili, logo, ödeme vadesi ve hizmet dökümü ayarları
- PDF çıktıları için özelleştirilebilir doküman şablonu

#### Raporlama ve Operasyon

- Tarih, müşteri ve proje filtrelerine sahip rapor paneli
- Süre ve tutar kırılımlı müşteri raporları
- Dönem bazlı proje raporları
- Manuel kayıt vurgulu iş raporları
- Organizasyon üyeleri, roller ve müşteri bazlı erişim yetkileri
- Yerel saklama için kullanıcı seçimli SQLite veri dosyası
- Açılışta çalışma, menü çubuğu, dil, tarih, saat ve yazı boyutu ayarları

### Tipik Kullanım Akışı

1. Müşteri ekleyin ve ilgili projeleri oluşturun.
2. Görevleri açın, kategori ve statü atayın, panodan çalışmayı başlatın.
3. Süreyi otomatik takip edin veya gerekirse manuel oturum ekleyin.
4. Raporları inceleyin, faturalandırma kaydı oluşturun, ödemeyi kaydedin ve çıktıyı dışa aktarın.

### Kimler İçin Uygun

- Serbest çalışanlar
- Danışmanlar
- Yazılım geliştiriciler
- BT destek ekipleri
- Ajanslar
- Teknik hizmet sağlayıcıları
- Zamana, projeye veya hizmet penceresine göre ücret kesen küçük işletmeler

### Teknoloji

- **Swift**
- **SwiftUI**
- **SQLite3**
- Yerel **macOS** masaüstü arayüzü ve menü çubuğu entegrasyonu
- Kullanıcı tarafında seçilen veri dosyalarıyla yerel öncelikli yapı

### İndirme / Kurulum

- En güncel sürümü GitHub Releases sayfasından indirebilirsiniz.
- Mevcut herkese açık önizleme sürümleri **Apple kod imzası olmadan ve notarization olmadan** dağıtılmaktadır.
- İlk açılışta macOS uygulamayı güvenlik uyarısıyla engelleyebilir.

macOS uygulamayı engellerse:

1. İndirilen uygulamayı **sağ tık > Aç** ile çalıştırın.
2. Gerekirse **Sistem Ayarları > Gizlilik ve Güvenlik** bölümüne gidip **Yine de Aç** seçeneğini kullanın.
3. Uyarıyı onayladıktan sonra uygulamayı tekrar başlatın.

### Yerelde Çalıştırma

```bash
git clone https://github.com/pronomi-tech/ProWork.git
cd ProWork
open ProWork.xcodeproj
```

Projeyi Xcode'da `ProWork` şeması ile macOS üzerinde çalıştırabilirsiniz. Faturalandırma odaklı XCTest dosyaları [`ProWorkTests`](ProWorkTests) klasöründe yer alır.

### Proje Durumu

ProWork aktif olarak geliştirilmektedir. Mevcut kod tabanı; **görev yönetimi, zaman takibi, raporlama, faturalandırma hazırlığı, fiyatlandırma, döviz kurları, PDF çıktıları ve operasyonel ayarlar** tarafında çalışan bir çekirdek akış sunar.

### Lisans

Bu proje **GNU GPLv3** ile lisanslanmıştır.

Yapabilecekleriniz:

- Projeyi kullanabilirsiniz
- Kaynak kodunu değiştirebilirsiniz
- Orijinal sürümü veya değiştirdiğiniz sürümü paylaşabilirsiniz
- Kişisel veya ticari işlerde kullanabilirsiniz

Yapmanız gerekenler:

- Projeyi yeniden dağıtırsanız aynı çalışmayı **GPLv3** altında tutmanız gerekir
- Uygulamayı veya değiştirilmiş bir sürümü dağıtırsanız **kaynak kodunu** da paylaşmanız gerekir
- Telif ve lisans bildirimlerini korumanız gerekir
- Kodu değiştirdiyseniz bunu açıkça belirtmeniz gerekir

Yapamayacaklarınız:

- Bu projeyi veya türetilmiş bir sürümünü **kapalı kaynak / özel mülk** olarak yeniden dağıtamazsınız

Proje **garantisiz** sunulur. Ayrıntılar için [LICENSE](LICENSE) dosyasına bakın.
