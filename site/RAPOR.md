# Raporlar

Bütün ölçümler tek sayfada. **2026-09-03 14:41** tarihinde `savings.py` tarafından üretildi —
elle düzenlenmiyor.

> Bu sayfa GitHub'da açılır çünkü Markdown. Yanındaki `.html` raporlar açılmaz: GitHub HTML'i
> kaynak olarak gösterir, ve private depoda Pages bu planda reddediliyor (HTTP 422). Onları
> okumak için `pwsh -File site/ac.ps1` — çeker ve tarayıcıda açar.

## Lea ne kazandırdı

| | |
|---|---|
| **Tasarruf** | **$327 · −26%** |
| Ölçülen gerçek harcama | $910.37 · 135 istem · 3,182 tur |
| Aynı iş `full` config'iyle | $1,237 |
| Üst sınır (en iyi ölçülen tur) | $962 · −51% |
| Bunu kanıtlamanın maliyeti | $10.91 · 11 gölge koşusu |

Manşet **alt sınır**: dört ölçülmüş turun Lea'ya en az kazandıranını kullanıyor
(Kolay bug fix, n=3/3). Ölçülmüş oran × ölçülmüş harcama — doğrudan ölçülmüş tasarruf
değil. Onu ölçecek olan gölge kolu.

## Ölçülen oranlar (Opus, `full` karşısında)

| tur | Lea USD | full USD | oran | kesinti | n |
|---|---|---|---|---|---|
| Metin (araç yok) | 0.2032 | 0.4180 | 0.486 | −51.4% | 5 / 3 |
| Gerçek proje turu | 3.7349 | 5.5595 | 0.672 | −32.8% | 3 / 3 |
| Zor bug fix | 0.2058 | 0.2923 | 0.704 | −29.6% | 5 / 5 |
| Kolay bug fix | 0.1842 | 0.2503 | 0.736 | −26.4% | 3 / 3 |

## Gerçek işin maliyeti nereye gidiyor

| kalem | token | pay |
|---|---|---|
| cache okuma (konuşmayı yeniden okumak) | 1,271,236,424 | %70 |
| girdi + cache yazma | 16,974,228 | %19 |
| çıktı | 4,324,508 | %12 |

Paranın üçte ikisi konuşmayı yeniden okumaya gidiyor, çıktıya değil. Lea'nın 120 kelimelik
bütçesinin doğrudan kestiği kalem en küçüğü — asıl kaldıraç **tur sayısı**.

## Hangi kurulum ne kadarını yazdı

| kurulum | istem | USD |
|---|---|---|
| `A` | 133 | $904.43 |
| `B` | 2 | $5.94 |

## Gölge kolu

| | |
|---|---|
| kayıtlı istem | 163 |
| koşan | 11 |
| harcanan | $10.91 |
| **karşılaştırılabilir çift** | **3** |

## Karşılaştırılabilir çiftler

Aynı istem, iki kol, aynı ağaçtan. Tur ve çıktı karşılaştırılabilir; maliyet yalnız iki kolun taşıdığı girdi birbirine yakınsa.

| tarih | kaynak | config | tur L/S | çıktı L/S | taşınan girdi L/S |
|---|---|---|---|---|---|
| 2026-09-02 21:24 | local | bare | 23 / 13 | 19k / 6k | 1.3M / 251k |
| 2026-09-03 06:52 | local | bare | 4 / 4 | 527 / 1k | 161k / 90k |
| 2026-09-03 08:05 | local | bare | 57 / 25 | 81k / 25k | 5.0M / 1.0M |

## Tam raporlar

Aşağıdakiler HTML; GitHub'da kaynak olarak görünürler. `pwsh -File site/ac.ps1` hepsini çeker
ve tarayıcıda açar.

| dosya | ne anlatıyor |
|---|---|
| [`index.html`](index.html) | çerçeve — banner ve diğerlerine bağlantılar |
| [`rapor-lea.html`](rapor-lea.html) | Lea'nın kendisi, kuralları, v7'ye karşı v8 |
| [`rapor.html`](rapor.html) | dört benchmark turu, beş config, Sonnet |
| [`rapor-model-karsilastirma.html`](rapor-model-karsilastirma.html) | aynı turlar Sonnet ve Opus yan yana |
| [`rapor-opus-proje-turu.html`](rapor-opus-proje-turu.html) | gerçek depo turu, Opus |
| [`rapor-tasarruf.html`](rapor-tasarruf.html) | tasarruf hesabının tamamı |
| [`rapor-golge.html`](rapor-golge.html) | gölge kolunun durumu ve verimi ne kilitliyor |
| [`savings.json`](savings.json) | manşetin arkasındaki her ara değer |

Sayfalarda kullanıcı adı, makine adı ve hesap adı içeren mutlak yol **yok**; kurulumlar
`A` / `B` hesap etiketiyle görünüyor. `check_docs.py`'nin `leak` geçişi bunu her koşuda
doğruluyor.
