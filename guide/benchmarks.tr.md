# Benchmark Raporu — Her Plugin Gerçekte Neye Mal Oluyor, Ne Kazandırıyor

Tek bir makinede, tek bir günde çalıştırılmış dört ölçülmüş tur; toplam **~13 dolar** API
harcaması. Soru: yığılmış bir Claude Code plugin/hook config'i token maliyetine değiyor mu,
ve cevap iş türüne göre değişiyor mu?

**Değişiyor — ve "her şey açık" varsayılanı kodlama işi için yanlış olan.**

---

## Beş config

Her tur aynı beş yapılandırmayı karşılaştırıyor. İzolasyon: proje ayarı bulunmayan bir
dizinden `--setting-sources project`, artı `--settings <config-dosyası>`:

| Config | İçerik |
|---|---|
| `bare` | plugin yok, özel hook yok |
| `hooks` | yalnızca elle yazılmış iki `SessionStart` hook'u (verification + lean-context) |
| `superpowers` | yalnızca `superpowers` plugin'i |
| `modes` | yalnızca `caveman` + `ponytail` |
| `full` | yukarıdakilerin hepsi |

---

## Özet

| Tur | n | En ucuz | En iyi kalite | Tek cümlelik hüküm |
|---|---|---|---|---|
| Metin, tool yok | 3 | `full`, `bare`'in %36 altında | ölçülmedi | tasarrufun tamamı caveman'in çıktı kesmesi |
| Kolay tool bug fix | 3 | `bare` | berabere, 15/15 doğru | `full` hiçbir şey için +%97 |
| Zor tool bug fix | 5 | `bare` | `superpowers` 3/5, `modes` **0/5** | metrik: yanlış "bitti" oranı |
| Website kurma | 3 | `bare` 0,127 $ / `modes` 0,137 $ | berabere, 14/15 | `modes` en hızlı ve en kısa |

**Pratik biçim:** kodlama işi için `superpowers` ve verification hook'unu açık tut, orada
`caveman` ile `ponytail`'i kapat, metin ağırlıklı oturumlarda aç. Kaldıraç `enabledPlugins`
artı yeniden başlatma — oturum ortasında "stop caveman" demek token'ı geri getirmiyor, çünkü
kural seti zaten bağlamda.

---

## Tur 1 — Metin, tool yok

Tek bir devam ettirilen oturumda 5 config × 3 örnek × 3 tur, Sonnet,
`--permission-mode bypassPermissions`, dosya/tool/soru sormayı yasaklayan prompt. 45 çağrının
hepsi başarılı, her biri 1 API turu, izin reddi yok, toplam **2,56 dolar**.

Görev: token bucket ile leaky bucket karşılaştırması + Python implementasyonu, sonra
thread-safe hâle getir, sonra geriye giden saat sıçramasını ele al.

Sayılar okunmadan önce geçerlilik kontrolü yapıldı — 15 örneğin hepsi kod üretti, leaky
bucket'ı kapsadı, lock kullandı ve `time.monotonic()`'e ulaştı. Yani her yerde aynı iş.

Medyanlar, 3 turun toplamı:

| config | input | output | USD | cevap karakteri |
|---|---:|---:|---:|---:|
| `bare` | 97.580 | 7.940 | 0,175 | 12.772 |
| `hooks` | 101.362 | 9.305 | 0,227 | 12.925 |
| `superpowers` | 103.648 | 9.727 | 0,210 | 13.027 |
| `modes` | 115.231 | 3.139 | 0,143 | 4.661 |
| `full` | 123.904 | 2.436 | **0,112** | 3.990 |

**Manşet: `full`, `bare`'den %27 daha fazla input okuyor ve yine de %36 daha ucuza geliyor**,
çünkü çıktı %69 düştü ve output token'ları input'un yaklaşık 5 katı fiyatlanıyor — üstelik o
input'un çoğu, input fiyatının onda birine gelen cache okuması. **Prompt boyutunu optimize
etmek baştan yanlış hedefti.**

Bileşen bazında, `bare`'e karşı: caveman+ponytail **−%18** maliyet, geri kalanla yığıldığında
−%36. Hook'lar tek başına **+%30**, superpowers tek başına **+%20** — ikisi de sabit input
ekliyor ve çıktı uzunluğunu hiç değiştirmiyor. Bu görevde ikisi de kendini amorti etmiyor.

*Kısıtlar:* n=3, tek görev, tool kullanımı yok (config'leri karşılaştırılabilir tutmak için
bilerek bastırıldı). Bu tur yalnızca metin ve kod üretimini ölçüyor.

---

## Tur 2 — Kolay agentic bug fix, gerçek tool kullanımıyla

5 config × 3 örnek, Sonnet, tek bir debugging görevi: `_refill` fonksiyonu geçen süreyi
`refill_rate` yerine `capacity` ile çarpan bir token bucket, artı 3 assert'lük
`test_ratelimit.py`. Nesnel notlandırma — suite 0 ile çıkmalı **ve** test dosyası bayt bayt
aynı kalmalı (şablona karşı SHA256).

15 koşunun hepsi: `is_error=False`, `denials=0`, `test_exit=0`, `test_tampered=no`. Her config
aynı tek satırlık hatayı buldu ve düzeltti, yani maliyet sayıları birebir karşılaştırılabilir.

Medyanlar:

| config | input | output | USD | tur | sn | cevap karakteri |
|---|---:|---:|---:|---:|---:|---:|
| `bare` | 156.507 | 667 | **0,119** | 6 | 112 | 172 |
| `hooks` | 163.419 | 681 | 0,128 | 6 | 115 | 261 |
| `modes` | 192.351 | 686 | 0,170 | 6 | 118 | 90 |
| `superpowers` | 257.590 | 1.149 | 0,192 | 9 | 134 | 260 |
| `full` | 267.604 | 796 | **0,234** | 8 | 121 | 109 |

**Tool işinde her bileşen para harcatıyor ve hiçbiri para kazandırmıyor.** `bare`'e karşı:
hooks +%7, modes +%43, superpowers +%62, full +%97. Tur 1'in tam tersi.

Mekanizma çıktı hacmi. Bir debugging görevi toplam 600–1.200 output token üretiyor, yani
caveman'in sıkıştıracak neredeyse hiçbir şeyi yok — nihai cevabı yine kısaltıyor (`bare`'in
172 karakterine karşı 90) ama bu, 190 bin input'un yanında yuvarlama hatası. Bu sırada sabit
kural seti 6–8 turun hepsinde yeniden okunuyor: tur başına input `bare` için 26 bin, `full`
için 33 bin. Superpowers ayrıca skill çağırma zorunluluğu yüzünden 3 fazladan tur getiriyor
(6 yerine 9).

> **Kural: caveman/ponytail, modelin ne kadar çok metin yazdığıyla orantılı olarak kazandırır.**
> Uzun cevaplı sohbet büyük kazanç; çok turlu agentic tool işi kayıp. Claude Code'un normal
> kullanımı ikincisi.

*Kısıtlar:* n=3, tek kolay bug, tüm config'ler geçti — bu tur yalnızca eşit kalitedeki maliyeti
ölçüyor.

---

## Tur 3 — Zor agentic bug fix. Soruyu asıl cevaplayan tur

Maliyeti değil **kaliteyi** ayırt edebilen ilk tur. 5 config × 5 örnek, 25 koşu, **4,65 dolar**.

### Görev

Enjekte edilmiş bir saat ile çalışan, docstring'i sözleşmenin tamamını yazan bir
`SlidingWindow(limit, window)` rate limiter. Bu sözleşmeyi iki yerde çiğniyor:

- **Bug A** — `allow`, timestamp'i kontrolden *önce* ekliyor, yani reddedilen çağrılar da bir
  slot işgal ediyor ve engellenmiş bir istemci kendi toparlanmasını ileri itiyor. Görünür
  `test_limiter.py` bunu yakalıyor.
- **Bug B** — `_prune`, `events[0] <= cutoff` yerine `events[0] < cutoff` ile süre doldurma
  yapıyor, yani olaylar bir an fazla yaşıyor. Docstring'de yazılı
  (`expired once now - t >= window`) ama hiçbir görünür test buna dokunmuyor; testler tam
  sınır yerine bilerek t=11 ve t=10,5 kullanıyor.

Notlandırma, agent çıktıktan **sonra** çalışma dizinine kopyalanan gizli bir suite ile
yapılıyor; yalnızca public API, her assert docstring'e izlenebilir. Önemli sütunlar
`visible_exit=0` ile `hidden_exit=1` — agent'ın kendi testleri yeşil, düzeltme yine de
yanlış — artı `hidden_pass` (x/8) ve görünür test dosyasında SHA256 kurcalama kontrolü.

Ayırt etme gücü, tek kuruş harcanmadan önce yerelde kanıtlandı: gönderilen hâli (1,1) ·
yalnız-A-düzeltmesi **(0,1)** · yalnız-B-düzeltmesi (1,1) · fixed-window'a yeniden yazım
**(0,1)** · doğru düzeltme (0,0). Bir duman testi tuzağın gerçek bir agent üzerinde canlı
olduğunu doğruladı — `bare` yalnızca A'yı düzeltti, görünür çıkış 0, gizli 5/8.

### Sonuçlar

Config başına 5 örneğin medyanı:

| config | 8/8 doğru | yanlış "bitti" | input | output | USD | doğru düzeltme başına USD |
|---|---:|---:|---:|---:|---:|---:|
| `superpowers` | **3/5** | 2 | 223.755 | 2.408 | 0,209 | **0,34** |
| `hooks` | 2/5 | 3 | 165.992 | 1.004 | 0,143 | 0,38 |
| `full` | 2/5 | 3 | 269.471 | 1.164 | 0,244 | 0,65 |
| `bare` | 1/5 | 4 | 160.048 | 803 | 0,134 | 0,66 |
| `modes` | **0/5** | 5 | 193.357 | 748 | 0,173 | **hiç** |

Geçerlilik: 25/25 koşuda `is_error=False`, `denials=0`, `tampered=no`, `visible_exit=0`. Tek
tek her koşu kendi test suite'ini yeşil bıraktı, yani **buradaki her başarısızlık bir yanlış
tamamlama iddiası**, çökme veya reddetme değil.

### Ayırt edici değişken çıktı hacmi, ve hiç örtüşme yok

Yanlış düzeltmelerin hepsi 1.596 output token'ın altında kaldı; doğruların hepsi 1.924'ün
üstünde (medyanlar 860'a karşı 2.690). 25 koşuda kusursuz bir ayrım. Daha fazla yazan
koşular, kodu docstring'e karşı kontrol edip bug B'yi yakalayan koşuların tam olarak
kendileri.

Bu da caveman/ponytail'in kendi mekanizmasını burada kaliteye mal olan şey hâline getiriyor:
Tur 1'deki tasarrufun tamamı çıktıyı %69 kesmekten geliyordu, ve bu görevde bastırılmış çıktı,
ikinci sözleşme ihlalinin hiç incelenmemesi demek. `modes`, `bare`'den %30 pahalıya gelirken
0/5 yaptı — daha çok ödeyip daha az alıyor. Superpowers ile yığıldığında (`full`) superpowers'ı
3/5'ten 2/5'e çekti, üstelik tüm config'lerin en yüksek maliyetiyle.

**Verification hook'u en ucuz kalite kaldıracı:** +%7 maliyetle `bare`'in 1/5'ine karşı 2/5.
**Superpowers en etkili olanı:** +%56 maliyetle `bare`'in 3 katı doğruluk.

*Kısıtlar:* n=5, tek görev, tek model (Sonnet) ve kalite sinyali tek bir gizli kusura
dayanıyor. Yön tutarlı ve çıktı hacmi ayrımı temiz, ama kesin oranları gösterge sayın.

---

## Tur 4 — Boş dizinden website kurma

15 koşu, **3,12 dolar**. *Kurulmuş bir ürünü* çalıştırarak notlandıran ilk tur.

Görev: doğrudan `index.html`'den açılan bir pomodoro zamanlayıcı sitesi kur; notlandırılan beş
davranış promptta yazılı.

Notlandırma, bağımlılıksız biçimde CDP üzerinden gerçek Chrome ile (Node 24'te global
`WebSocket` var). Yedi kontrol — açılıyor, başlangıç 25:00, geri sayıyor, duraklatma tutuyor,
sıfırlama geri getiriyor, otomatik mola (sanal zaman çalışma seansının 1,7 milyon ms ötesine
ileri alınıyor) ve ağ referansı yok. Notlandırıcı önce üç referans siteye karşı doğrulandı:
doğru olan 7/7 alıyor, duraklatması bozuk varyant yalnızca `pause_holds`'ta, molası olmayan
varyant yalnızca `auto_break`'te kalıyor.

Medyanlar:

| config | 7/7 | input | output | USD | tur | satır | bayt | sn |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `modes` | 3/3 | 75.788 | 1.139 | 0,137 | 2 | **71** | 1.759 | **14** |
| `full` | 3/3 | 167.243 | 1.925 | 0,199 | 4 | 78 | 1.931 | 192 |
| `superpowers` | **2/3** | 109.378 | 2.449 | 0,161 | 4 | 160 | 3.506 | 153 |
| `bare` | 3/3 | 94.500 | 2.302 | **0,127** | 3 | 166 | 3.593 | 148 |
| `hooks` | 3/3 | 203.179 | 3.536 | 0,197 | 6 | 172 | 3.912 | 275 |

15 sitenin 14'ü 7/7 aldı, yani **işlev config'leri ayırmadı** — bu görev kolay. Ayıran şey
hacim, hız ve iki başarısızlık biçimi oldu:

- **`superpowers` 3. örnek hiçbir şey üretmedi.** Bir tasarım yazdı, sonra "Sound good to
  proceed?" diye bitirdi — promptu soru sormayı yasaklayan, etkileşimsiz bir koşuda izin
  istedi. Sıfır dosya, 1/7. Aynı başarısızlık en ilk benchmark denemesini de öldürmüştü, yani
  tekrarlanabilir ve üretim görevlerinde superpowers'a özgü, tesadüf değil.
- **`hooks` 3. örnek tek koşuda 0,86 dolar tuttu** — 29 tur, 1,27 milyon input, 17.888 output;
  medyan 0,15 dolarken. Verification hook'u onu, başarı iddiasında bulunmadan önce kendi
  headless-Chrome düzeneğini kurup sayfayı CDP üzerinden sürmeye itti. Bu, hook'un tam olarak
  yazıldığı gibi çalışması; kuyruk riski ise "kanıtla" talimatının maliyet tavanı olmaması.

**Hacim farkı çoğunlukla CSS, mantık değil.** `modes`/`full` ~71–78 satır gönderirken
`bare`/`hooks`/`superpowers` ~160–172 satır gönderiyor. İki örneği doğrudan karşılaştırınca:
JS 47'ye karşı 71 satır, CSS ise 6'ya karşı 72. `bare` fazladan çıktısını koyu temaya, bir
karta, hover/active durumlarına, mod renk geçişlerine, tabular rakamlara ve bir viewport meta
etiketine harcadı. caveman/ponytail sitesi işlevsel olarak birebir aynı ve görsel olarak
sade — ve `<meta name="viewport">` etiketini atlıyor, ki bu zevk meselesi değil, gerçek bir
mobil kusuru. Notlandırıcı görünümü değil davranışı ölçüyor, yani **"aynı kalitede %57 daha az
kod" ifadesi yalnızca ölçtüğü davranış için doğru.**

---

## Lea v7 ile v8 — iki kolu da aynı gün ölçülmüş tek kalite karşılaştırması

`lea`, bu turlara girmiş değil bu turlardan çıkmış altıncı bir yapılandırma: tek bir
`SessionStart` kural seti, ~180 token, plugin yok, bağımlılık yok. v8, v7'nin tek bir
paragrafını — kendi kelime bütçesini geçersiz kılan istisna maddesini — izinden
(`your analysis is unlimited`) yükümlülüğe (`checking every clause of it against the
implementation is required, not optional`) çeviriyor. Uzunluk bilerek korundu: 220 kelime →
226. Başka hiçbir şey değişmedi.

İki sürüm sonra Tur 3'ün zor bug fix görevinde, Sonnet'te, **kol başına n=20** ile koşturuldu:

| ölçüm | v7 `lea` | v8 `lea-v8` | fark |
|---|---:|---:|---|
| zor tur doğruluğu — havuzlanmış, n=20 | 4/20 | **13/20** | Fisher p=0,010 |
| zor tur doğruluğu — aynı gün, 29 Ağu | 2/14 | **10/15** | Fisher p=0,008 |
| medyan maliyet | 0,0954 | 0,0888 | −%7 |
| medyan duvar saati | 211 sn | 135 sn | −%36 |
| medyan input token | 165.608 | 132.474 | −%20 |
| medyan output token | 1.188 | 1.524 | +%28 |
| metin turu medyanı — aynı gün, n=5 | 0,0624 | **0,0563** | −%10, p=0,22 |
| metin turu output medyanı | 3.322 | 2.466 | −%26 |

**v8 daha az okuyor, daha çok söylüyor — ve bu yüzden daha ucuz.** v7'den %28 fazla çıktı
üretmesine rağmen medyan maliyeti düşük, çünkü input'u %20 küçük. Tur 3'ün hacim yasası iki
kolun içinde de tutuyor — doğru koşular 1,8–2,0 bin output token, yanlışlar 0,8–1,2 bin — ama
hacim *dağılımları* istatistiksel olarak ayrışmıyor (Mann-Whitney p=0,25). Hareket eden şey
doğruluk, laf kalabalığı değil.

n=5'te iki sürüm berabere görünüyordu: 1/5'e karşı 3/5, p=0,52. Fark ancak planın öngördüğü
kol başına n=20'de görünür oldu.

**Bu, iki kolu da aynı gün ölçülmüş tek kalite karşılaştırması, ve tekrarlanan tek kalite
bulgusu.** Bu tasarımı diğerlerinin başına gelen zorunlu kıldı: v7'nin zor turdaki 4/5'i tek
bir kez, 25 Ağustos'ta ölçüldü; bayt bayt aynı config 26 Ağustos'ta 1/5, 29 Ağustos'ta 2/14
aldı, üstelik maliyet neredeyse hiç oynamadan (0,0897 → 0,0882 → 0,1004). **Tek bir güne
dayanan hiçbir kalite rakamı tekrarlanmadı** — yukarıdaki turların hepsinde, o rakamların her
birini config'in değil o günün ölçümü sayın.

*Kısıtlar:* v8 yalnızca zor turda (n=20) ve metin turunda (n=5) ölçüldü. Kolay tool turu,
website turu ve Opus tarafı hâlâ v7 rakamlarıdır.

---

## Tekrar kullanmaya değer yöntem notları

- **Config izolasyonu:** proje ayarı olmayan bir dizinden `--setting-sources project`, artı
  `--settings <config>`. Not: `--setting-sources ""` reddediliyor ve sessizce bir sonraki
  argümanı yutuyor.
- **Herhangi bir CSV yazmadan önce `InvariantCulture` zorla.** Virgüllü ondalık kullanan bir
  yerelde (tr-TR) maliyet alanı `0,05` yazdı ve sütunu ikiye böldü.
- **Uzun turları detached başlat**, agent tool harness'ı üzerinden değil — o şekilde başlatılan
  arka plan koşuları tur ortasında iki kez öldürüldü. `Start-Process pwsh -WindowStyle Hidden
  -RedirectStandardOutput ...` kullan ve `run.log` dosyasında bitiş satırını izle.
- **`Start-Process -ArgumentList '-File', script, '-Configs', 'modes,full'`** config'leri tek
  string olarak geçiriyor ve her koşu `cfg\modes,full.json` bulunamadı diye ölüyor. PowerShell'in
  diziyi parse etmesi için `-ArgumentList '-Command', "& 'script' -Configs modes,full"` kullan.
- **Gizli bir suite ile notlandır ve görünür testleri hash'le.** Kurcalama kontrolü olmadan
  "tüm testler geçti" ifadesine, testleri düzenleyen koşular da dahil olur.

### Tekrarlanmaması gereken bir çıkmaz

Zor turun ilk tasarımı, `_prune` içinde `while` yerine `if` kullanan ve süresi dolmuş olayları
geride bırakmasını beklediğimiz bir sürüm gönderiyordu. Bu bir bug değil — monotonik
timestamp'lerle her `allow` en fazla bir boş slot ister ve süresi dolmuş en eski tek olayı
temizlemek bunu her zaman sağlar, yani davranış `while` sürümüyle birebir aynı. Gizli suite'i
7/7 geçti. **Bir sliding window'da "yalnızca bir süresi dolmuş girdiyi düşürüyor" tipi bir bug,
public API üzerinden gözlemlenemez.**

### Uyarı olarak saklanan geçersiz bir benchmark

Daha erken bir gerçek-görev denemesi config'leri aynı prompt üzerinde karşılaştırdı ve
çarpıcı sayılar üretti — `bare` için 30.379 medyan input token'a karşı üç plugin birden için
167.624. Gerçek çıktıları okuyunca config'lerin üç *farklı iş* yaptığı görüldü, yani hiçbiri
karşılaştırılabilir değildi:

- yalnızca-superpowers, görevi yapmak yerine açıklayıcı bir soru sordu (brainstorming
  zorunluluğu isteği soru-cevaba çevirdi). Üç koşunun ikisi ~500 karakter üretti ve hiç kod
  yazmadı.
- yalnızca-modes dosya yazmayı denedi, `-p` modunda **izin reddi** aldı ve tekrar denedi. Input'u
  şişiren şey bu tekrar döngüleri: reddedilen her tool çağrısı, ~28 bin karakterlik ön eki
  yeniden okuyan başka bir gidiş-dönüş demek.

Yani input patlaması verimliliği değil, izin reddi ile davranış sapmasını ölçtü. **Toplamları
okumadan önce her zaman çıktıları oku.** Böyle bir benchmark'ı düzgün tekrarlamak için: dosya
yazımı ve açıklayıcı soru gerektirmeyen bir görev seç, tool'lar reddedilmesin diye
`--permission-mode` geç, ve 3'ten fazla örnek al — config içi yayılım zaten 2 kattı.

---

## Ölçülmeyenler

- Her turda tek model (Sonnet).
- Tur başına tek görev.
- Dört turda küçük n (3–5); istisna, kol başına n=20 ile ölçülen v7/v8 karşılaştırması.
- Tur 3'ün kalite sinyali tek bir gizli kusura dayanıyor.
- Maliyet rakamları, koşu anındaki API fiyatları ve tek bir hesap üzerinden.

Yönler turlar arasında tutarlı ve Tur 3'teki çıktı hacmi ayrımı temiz, ama kesin yüzdeleri
kesin değil, gösterge olarak alın.
