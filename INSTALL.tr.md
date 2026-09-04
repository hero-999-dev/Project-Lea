# KURULUM — Lea

> Kendi Claude Code oturumuna bu dosyayı göster (`INSTALL.tr.md dosyasını oku ve Lea'yı bana kur`),
> kurulumun tamamını yapabilir. Aynı adımlar elle de takip edilebilir.
>
> English: [`INSTALL.md`](INSTALL.md)

**Kurulan şey tek bir dosya.** Plugin yok, marketplace yok, indirilecek bağımlılık yok. Lea bir
`SessionStart` hook'u: her oturumun başında ~180 token'lık bir kural seti yüklüyor.

Neden bu ve neden diğerleri değil: 220 koşuluk benchmark beş yapılandırmayı ölçtü ve hiçbiri her
iş tipinde kazanmadı. Lea o ölçümlerin gösterdiği mekanizmalardan tasarlandı ve beş test turunun
beşinde de o turun en iyi rakibine karşı ölçüldü. Rakamlar
[`guide/benchmarks.tr.md`](guide/benchmarks.tr.md) ve rapor sayfasında.

| test turu | Lea | o turun en iyi rakibi | fark |
|---|---|---|---|
| metin, tool yok | 0.0626 | `modes` 0.0577 | berabere |
| kolay bug fix | 0.0828, 3/3 doğru | `bare` 0.0957 | −%13 |
| zor bug fix | 0.0897, **4/5 doğru** | `superpowers` 0.1244, 1/5 | −%28, 4× doğru |
| sıfırdan web sitesi | 0.0757, 3 kez 7/7 | `bare` 0.0911 | −%17 |
| zor bug fix #2 | 0.0815, 3/3 doğru | `bare` 0.0799 | +%2, berabere |

Hepsi Sonnet, 25 Ağustos 2026, rakipler aynı gün yeniden ölçüldü.

---

## Adım 1 — Ön koşullar

```bash
claude --version   # Claude Code CLI kurulu olmalı
node --version     # hook bir Node scripti
```

`node` yoksa önce Node.js kur. Lea'nın başka bağımlılığı yok.

---

## Adım 2 — Mevcut ayarları yedekle

```bash
mkdir -p ~/.claude/backups/lea-kurulum
cp ~/.claude/settings.json ~/.claude/backups/lea-kurulum/settings.json
```

Windows PowerShell'de:

```powershell
New-Item -ItemType Directory -Force ~\.claude\backups\lea-kurulum | Out-Null
Copy-Item ~\.claude\settings.json ~\.claude\backups\lea-kurulum\settings.json -Force
```

`settings.json` yoksa bu adımı atla; adım 4 dosyayı sıfırdan yazar.

---

## Adım 3 — Hook dosyasını kopyala

```bash
mkdir -p ~/.claude/hooks
cp config/hooks/lea.js ~/.claude/hooks/lea.js
node ~/.claude/hooks/lea.js | head -1     # "LEA ACTIVE ..." yazmalı
```

Son satır bir şey yazdırmıyorsa hook bozuk demektir; devam etme.

---

## Adım 4 — `settings.json` içine hook'u ekle

Mevcut `settings.json` dosyana **birleştir** — üzerine yazma. `SessionStart` bloğu zaten varsa
Lea'yı o bloğun `hooks` dizisine bir eleman olarak ekle.

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume|clear|compact",
        "hooks": [
          {
            "type": "command",
            "command": "node \"/home/<kullanıcı>/.claude/hooks/lea.js\"",
            "timeout": 20
          }
        ]
      }
    ]
  }
}
```

Windows'ta komut şöyle olur (JSON içinde ters bölü çiftlenir):

```json
"command": "node \"C:\\Users\\<kullanıcı>\\.claude\\hooks\\lea.js\""
```

`<kullanıcı>` yerine gerçek kullanıcı adını yaz. Göreli yol ya da `~` çalışmaz.

---

## Adım 5 — CLI'ı yeniden başlat

Hook yalnızca oturum açılışında okunur. Çalışan oturumlar eski hâlini taşımaya devam eder.

---

## Adım 6 — Doğrula (atlama)

Yeni bir oturum aç. İlk sistem bağlamında şu satır görünmeli:

```
LEA ACTIVE - always on. Terse prose, unlimited analysis.
```

Görünmüyorsa: `settings.json` geçerli JSON mu, `command` içindeki yol mutlak mı, dosya gerçekten
o yolda mı — üçünü sırayla kontrol et.

---

## Buraya ne konur, ne konmaz

Gölge kolu bir defter yazıyor, tek komut onu paketliyor, raporlar da yayınlanıyor — o yüzden
eklediğin her şeye şunu sor: *bu dosya yarın tanımadığım birinin elinde olsa ne olur?* Üç yere
gidebilir ve üçünün de geri dönüşü yok: **public depo** (çatal ve klonlar silmeden sonra da
yaşar), **yayınlanan sayfa** (önbellek ve arşivler de öyle), ve **taşınabilir disk** (kaybolacağını
varsay).

Bu yüzden, istisnasız:

- **Parola, token, API anahtarı, kurtarma kodu** üçünden hiçbirine yazılmaz. Ne config'e, ne
  yoruma, ne "geçici olarak". `export.ps1` diff'leri varsayılan olarak dışarıda bırakıyor, sebebi
  aynı: onlar senin kaynak kodun.
- **Hesap adı içeren mutlak yol yok, makine adı yok.** Defter `user` ve `host` tutuyor çünkü tek
  dosyaya yazan iki kurulum başka türlü ayırt edilemez; `export.ps1` ise makine adını dışarı
  çıkmadan önce tek yönlü bir özete çeviriyor. Yayınlanan sayfalar `shadow/config.json`'daki
  hesap etiketlerini (`A`, `B`) kullanıyor, gerçek adı asla.
- **Şifre kapısı gizlilik değildir.** Raporları bir kapının arkasına koyarsan bu, bir URL'nin
  elden ele yayılmasını engeller; depoyu okuyan birini engellemez. Okunması sakıncalı hiçbir şey
  oraya konmaz.
- **Emin değilsen koyma.** Üçünün de geri alması yok.

## Kurulmayan şeyler ve nedeni
Bu rehber `caveman`, `ponytail` ve `superpowers` plugin'lerini **kurmuyor**. Ölçüm, üçünün birlikte
yaptığı işi Lea'nın çoğu turda daha ucuza yaptığını söylüyor: üç plugin yaklaşık 6.000 token'lık
kural seti yüklüyor ve bu metin araçlı bir görevin 6–9 turunun her birinde yeniden okunuyor;
Lea'nınki ~180 token.

**Zaten kuruluysalar Lea ile birlikte çalıştırma.** Kural setleri üst üste biner, çelişen talimatlar
oluşur ve ölçülen kazanç kaybolur. Önce `~/.claude/settings.json` içinde `enabledPlugins` altındaki
`caveman`, `ponytail`, `superpowers` girdilerini `false` yap, sonra CLI'ı yeniden başlat.

İki eski hook (`verification-activate.js`, `lean-context-activate.js`) Lea ile çakışmaz ama
ölçümde `hooks` yapılandırması araçlı işte `bare`'e göre pahalıydı ve web turunda tek koşuda
maliyeti 4.4 katına çıkardı. İstersen bırak, ama Lea'nın rakamları onlar olmadan ölçüldü.

Bu rehber yalnızca Lea'nın kural setini kuruyor. Lea'yı ölçen gölge kolu — her prompt'u arka planda
hazır bir yapılandırmayla ikinci kez cevaplayıp iki tarafın maliyetini yerel bir deftere yazan kol —
buna dahil değil: o kol ve kendi kurulum script'leri `collector/` dizininde, ayrıntısı
[`collector/README.md`](collector/README.md) içinde.

---

## Sorun giderme

| Belirti | Sebep | Çözüm |
|---|---|---|
| Oturumda `LEA ACTIVE` yok | hook hiç çalışmadı | `settings.json` JSON olarak geçerli mi (`node -e "JSON.parse(require('fs').readFileSync('$HOME/.claude/settings.json'))"`), yol mutlak mı |
| `node: not found` benzeri hata | PATH'te node yok | `command` içinde node'un tam yolunu yaz |
| Cevaplar hâlâ uzun | eski oturum | CLI'ı yeniden başlat; hook oturum ortasında yüklenmez |
| Cevaplar aşırı kısa, analiz de kesiliyor | başka bir kısaltma kuralı da açık | `caveman`/`ponytail` kapalı mı diye bak — Lea'nın analiz istisnası onların kuralıyla çakışır |
| `... hook timed out after 20s` (örn. `UserPromptSubmit hook timed out after 10s - output discarded`) | hook, `settings.json` girdisindeki `timeout` süresi içinde bitmedi ve çıktısı atıldı — yani `LEA ACTIVE` o oturuma hiç ulaşmıyor | o girdinin `timeout` değerini büyüt ve CLI'ı yeniden başlat; Lea'nın hook'u yalnızca bir metin yazdırıyor, 20 saniye yetmiyorsa yavaş açılan node'dur — `command` içine node'un tam yolunu yaz. `UserPromptSubmit`/`Stop` zaman aşımı Lea'nın değil collector'ın hook'undan gelir ([`collector/README.md`](collector/README.md)) |

---

## Kaldırma

```bash
cp ~/.claude/backups/lea-kurulum/settings.json ~/.claude/settings.json
rm ~/.claude/hooks/lea.js
```

Sonra CLI'ı yeniden başlat.

---

## Tam dokümantasyon

- Lea'nın tasarımı, sürüm günlüğü ve beş test sonucu: rapor sayfası (`rapor-lea.html`)
- Ölçüm yöntemi ve beş yapılandırmanın karşılaştırması: [`guide/benchmarks.tr.md`](guide/benchmarks.tr.md)
- Kurulum notlarının uzun hâli: [`guide/setup-guide.tr.md`](guide/setup-guide.tr.md)
