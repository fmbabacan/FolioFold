# FolioFold v1 Ürün ve Teknik Mimari Planı

## Özet

FolioFold, serbest çalışanlar ve küçük işletmeler için geliştirilen, tamamen çevrimdışı çalışan, açık kaynak ve hafif bir macOS PDF çalışma alanı olacak. Uygulama Notion’a yakın sakinlik ve bilgi yoğunluğunu, macOS’a özgü yerel davranışlarla birleştirecek.

İlk sürüm macOS 15 ve sonrasını destekleyecek. Apple Silicon ve Intel için ayrı paketler üretilecek. App Store, GitHub Releases ve Homebrew sürümleri aynı sandbox uyumlu özellikleri sunacak. Kaynak kod Apache License 2.0 ile yayımlanacak.

## Uygulama ve deneyim

- Uygulama SwiftUI tabanlı tek çalışma alanı penceresi kullanacak. Gereken yerlerde AppKit köprüleri kullanılacak.
- Sol kenar çubuğu varsayılan olarak açık, dar, yeniden boyutlandırılabilir ve tamamen gizlenebilir olacak.
- Kenar çubuğunda `Create`, `Open`, `Merge`, `Split`, `Convert` ve yerel `Recents` bölümü bulunacak.
- PDF, `.foliofold`, Merge, Split ve Convert oturumları aynı üst sekme çubuğunda açılacak; sekmeler sıralanabilecek ve kaydedilmemiş durum gösterecek.
- Araçlar kalıcı yoğun paneller yerine seçime göre görünen bağlamsal araç çubuğu ve denetçilerle sunulacak.
- Sistem açık ve koyu görünümü izlenecek. Nötr yüzeylere yalnızca seçim, odak ve birincil eylemlerde düşük doygunluklu mürekkep mavisi eşlik edecek.
- SF Symbols ve sistem yazı tipleri kullanılacak. Dekoratif cam efektleri, ağır gölgeler, gereksiz kart katmanları ve özel font paketleri kullanılmayacak.
- Klavye navigasyonu, VoiceOver, yüksek kontrast, azaltılmış hareket ve sistem metin büyüklüğü temel kabul kriterleri olacak.
- V1 arayüz dili İngilizce olacak. Kullanıcıya görünen tüm metinler String Catalog içinde tutulacak; tarih, sayı, para, çoğul ve metin yönü yerel ayarlara duyarlı olacak.

## Belge modeli ve editör

- `FolioDocument` sürümlü tek belge kökü olacak; belge ayarlarını, akış bloklarını, sayfaya sabitlenen öğeleri, şablon alanlarını, varlık referanslarını ve kaynak PDF bilgisini taşıyacak.
- Create belgeleri varsayılan olarak blok akışı kullanacak. Metin, başlık, liste, tablo, görsel, ayraç, şekil, form alanı, imza alanı ve açık sayfa sonu blokları desteklenəcək.
- İçerik belirlenen sayfa boyutu ve kenar boşluklarına göre deterministik biçimde sayfalara akacak.
- Kullanıcı bir bloğu `Pin to Page` ile belirli sayfadaki overlay katmanına taşıyabilecek; `Return to Flow` ile tekrar akışa alabilecek.
- Sabit öğeler sayfa koordinat sisteminde konum, boyut, dönüş, katman sırası ve kilit durumunu taşıyacak. Taşma, sayfa silme ve yeniden sıralama davranışları geri alınabilir olacak.
- Undo ve redo, belge modeli üzerindeki tersine çevrilebilir komutlarla çalışacak; görünüm nesneleri kalıcı veri modeli olmayacak.
- Şablonlar düzenlenebilir FolioFold belgelerinden üretilecek. Metin, tarih, sayı, para ve otomatik sıra numarası alanları ile çoğaltılabilir tablo satırları desteklenəcək.
- V1 formülleri ara toplam, yüzde/vergi, toplama ve genel toplamla sınırlı olacak; genel amaçlı ifade dili, koşullu içerik ve CSV ile toplu üretim kapsam dışında kalacak.

## Dosya biçimi ve güvenli kayıt

- Düzenlenebilir belge, Finder’da tek dosya görünen `.foliofold` paketinde saklanacak.
- Paket; sürümlü manifest, belge modeli, kaynak PDF, varlıklar ve bütünlük bilgisinden oluşacak. Geçici önizlemeler pakete dahil edilmeyecek.
- Bilinmeyen ileri sürüm alanları mümkün olduğunca korunacak; desteklenmeyen yeni ana sürümler salt okunur açılacak.
- Kayıt geçici hedefe yazma, doğrulama ve atomik değiştirme sırasıyla yapılacak. Başarısız kayıt geçerli önceki dosyayı bozmayacak.
- İsteğe bağlı paket şifrelemesi CryptoKit ile kimlik doğrulamalı şifreleme kullanacak. Parola tabanlı anahtar, paket içinde saklanan benzersiz salt ve sürümlü türetme ayarlarıyla üretilecek; parola kurtarma özelliği olmayacak.
- Dışarıdan açılan PDF varsayılan olarak değiştirilmeden korunacak. Düzenlemeler kurtarılabilir çalışma durumuna yazılacak; kullanıcı `.foliofold` veya yeni PDF hedefi seçebilecek.
- Kaynak PDF üzerine yazma ayrı ve açık bir komut olacak; işlem atomik yürütülecek.
- Recents yalnızca güvenlik kapsamlı dosya yer imleri, görünen ad ve yerel küçük resim kimliği saklayacak. Belge içeriğinin ikinci bir kopyasını tutmayacak.

## PDF servisleri ve v1 özellikleri

- PDF görüntüleme ve temel açıklamalar PDFKit, düşük seviyeli çizim ve yeniden yazma işlemleri Core Graphics üzerinden yürütülecek.
- PDF özelliği kullanan her modül küçük ve test edilebilir Swift protokolleri arkasında tutulacak: belge açma, dışa aktarma, sayfa işlemleri, birleştirme, parçalama, dönüştürme, form, güvenlik ve redaksiyon.
- Open akışı kaynak PDF görünümünü koruyan katmanlı düzenleme sunacak. Metin kutusu, görsel, çizim, vurgu, bağlantı, şekil, görsel imza ve temel form alanları eklenebilecek.
- Sayfalar sürüklenerek sıralanabilecek, döndürülebilecek, kopyalanabilecek, silinebilecek ve başka belgeye taşınabilecek.
- Merge dosya ve seçili sayfa aralıklarını sıralı kuyruğa alacak; Split seçili sayfalar, aralıklar, her N sayfa veya tek tek sayfalar üzerinden çıktı üretecek.
- Convert; JPEG, PNG, TIFF ve macOS’un güvenilir biçimde çözebildiği görselleri, düz metni, RTF’yi ve kontrollü yerel HTML’yi PDF’e dönüştürecek. PDF sayfaları PNG veya JPEG olarak dışa aktarılabilecek.
- DOCX, XLSX, PPTX, bulut dönüşümü, Office otomasyonu ve gömülü ofis motoru v1 kapsamında olmayacak.
- Görsel imza çizim, trackpad ve görsel içe aktarma ile oluşturulacak; yerel olarak saklanacak ve sertifikalı dijital imza olmadığı açıkça belirtilecek.
- Mevcut AcroForm alanları doldurulacak; metin, onay kutusu, seçenek düğmesi, açılır liste ve imza alanı oluşturulabilecek. PDF JavaScript’i, gelişmiş doğrulama, alan hesaplamaları ve sertifikalı imza kapsam dışında kalacak.
- PDF açma parolası ile standart yazdırma, kopyalama ve değiştirme izinleri desteklenəcək. Parolalar kaydedilmeyecek veya günlüklenmeyecek.
- Gerçek redaksiyon iki aşamalı olacak: düzenlenebilir işaretleme ve geri döndürülemez `Apply Redactions` dışa aktarımı. Kaynak korunacak, çıktı yeni dosyaya yazılacak.
- Redaksiyon sonrası çıktı yeniden açılacak; kapsanan bölgelerde metin çıkarımı, bağlantı, açıklama ve görünür içerik denetimleri geçmeden başarı bildirilmeyecek. Güvenli kaldırmanın doğrulanamadığı PDF’lerde işlem reddedilecek.
- Mevcut paragraf içeriğini yeniden akıtarak düzenleme, OCR, PDF/A, sertifikalı dijital imza ve Office dönüşümü sonraki sürümlere bırakılacak.

## Açık arayüzler ve veri türleri

- `WorkspaceSession`: belge ve araç sekmelerinin kimliği, türü, başlığı, değişiklik ve kurtarma durumu.
- `FolioDocument`: biçim sürümü, sayfa ayarları, `flow`, `overlays`, şablon alanları, varlıklar ve kaynak bilgisi.
- `Block`: kararlı kimlik, içerik türü, stil, şablon bağları ve sayfalama davranışı.
- `OverlayElement`: sayfa kimliği, geometri, dönüş, katman sırası, kilit ve içerik türü.
- `TemplateField`: metin, tarih, sayı, para, sıra numarası veya tablo satırı türü, biçim ve varsayılan değer.
- `PDFOperation`: girdi güvenlik erişimleri, ilerleme, iptal, çıktı hedefi ve yapılandırılmış hata sonucu taşıyan asenkron işlem sözleşmesi.
- Paket manifesti ve `.foliofold` biçim tanımı depoda kamuya açık belgelenecek; dosya biçimi uygulama lisansından bağımsız biçimde uygulanabilir olacak.

## Hata, eşzamanlılık ve mahremiyet

- Dosya okuma, PDF işleme, küçük resim üretimi ve dışa aktarma ana iş parçacığı dışında, Swift structured concurrency ile çalışacak.
- Uzun işlemler ilerleme ve iptal destekleyecek; iptal edilen işlem kısmi nihai dosya bırakmayacak.
- Aynı kaynak dosyanın dışarıda değişmesi algılanacak; kullanıcıya yeniden açma, kendi kopyasını kaydetme veya mevcut çalışma ile devam etme seçenekleri sunulacak.
- Bozuk, kısmen desteklenen veya parola korumalı belgeler veri kaybetmeden açıklayıcı ve yerelleştirilebilir hata durumlarına düşecek.
- Uygulama hesap, telemetri, analiz SDK’sı, reklam, bulut, ağ tabanlı dönüştürme veya belge yükleme içermeyecek.
- Ağ entitlement’ı yalnızca dağıtım kanalının zorunlu kıldığı durumda bulunacak; belge işleme yolu hiçbir ağ çağrısı yapmayacak.
- Günlükler belge metni, dosya içeriği, parola, imza verisi veya kullanıcı tarafından girilen şablon değerlerini içermeyecek.

## Test ve kabul planı

- Belge modeli için kodlama, sürüm yükseltme, bilinmeyen alan koruma, deterministik sayfalama ve undo/redo birim testleri yazılacak.
- Merge, Split, Convert, sayfa sıralama, form, parola, izin ve dışa aktarma işlemleri küçük ve büyük PDF fixture’larıyla doğrulanacak.
- Bloktan overlay’e ve overlay’den akışa dönüş, sayfa silme, yeniden sıralama, şablon çoğaltma ve formül sonuçları uçtan uca test edilecek.
- Redaksiyon testleri metin, vektör, gömülü görsel, bağlantı, açıklama ve metadata örnekleri içerecek; çıktı yeniden açılıp metinsel ve görsel olarak doğrulanacak.
- Şifreli paketlerde doğru parola, yanlış parola, bozuk veri, yarıda kesilen kayıt ve atomik kurtarma senaryoları test edilecek.
- UI testleri sekme geri yükleme, klavye kısayolları, VoiceOver adları, yüksek kontrast, açık/koyu görünüm ve İngilizce dışı sahte uzun metin yerleşimini kapsayacak.
- Test matrisi macOS 15 ve güncel macOS sürümünde, arm64 ve x86_64 derlemelerinde çalışacak.
- Her mimari için sıkıştırılmış dağıtım paketi 40 MB altında, boşta bellek 120 MB altında ve referans Apple Silicon cihazda soğuk açılış yaklaşık 1 saniye olacak.
- 1.000 sayfalık belge açılırken tüm sayfaların raster görüntüleri belleğe alınmayacak; görünür ve yakın sayfalar talebe göre işlenecek.
- GitHub CI derleme, birim test, UI duman testi, lisans denetimi, bağımlılık güvenlik kontrolü ve paket boyutu bütçesini yayın öncesi zorunlu tutacak.

## Yayın ve geliştirme sırası

1. Depo, Apache 2.0 lisansı, Swift proje yapısı, CI, tasarım tokenları ve temel çalışma alanı kabuğu.
2. `.foliofold` modeli, atomik kayıt, kurtarma, şifreleme ve belge sekmeleri.
3. PDF açma, görüntüleme, sayfa küçük resimleri ve sayfa düzenleme işlemleri.
4. Create editörü, blok sayfalama, overlay sistemi, undo/redo ve PDF dışa aktarma.
5. Merge, Split ve yerel Convert araç oturumları.
6. Açıklamalar, görsel imza, temel AcroForm doldurma ve oluşturma.
7. PDF ve paket güvenliği ile doğrulamalı gerçek redaksiyon.
8. Erişilebilirlik, performans, bozuk belge dayanıklılığı ve dağıtım sertleştirmesi.
9. Notarize edilmiş arm64 ve x86_64 GitHub sürümleri, Homebrew Cask ve aynı özellik kapsamındaki Mac App Store yayını.

## Sabit varsayımlar

- Windows desteklenmeyecek. Olası Linux sürümü v1 mimarisini ağırlaştırmayacak ayrı bir gelecek projesidir.
- V1 saf Swift olacak; Rust, Electron, Tauri, WebView tabanlı editör ve GPL/AGPL bağlı bileşen kullanılmayacak.
- Üçüncü taraf bağımlılık yalnızca sistem çerçevelerinin açık bir ihtiyacı karşılayamadığı durumda, izinli lisans ve ölçülmüş boyut etkisiyle eklenecek.
- Notion referansı görünümün birebir kopyası anlamına gelmeyecek; FolioFold kendi mürekkep mavisi kimliğini ve macOS etkileşim davranışlarını koruyacak.
- Güvenli biçimde doğrulanamayan işlem sessizce yaklaşık sonuç üretmeyecek; özellikle redaksiyon, şifreleme ve dosya üzerine yazma işlemleri güvenli şekilde başarısız olacak.
