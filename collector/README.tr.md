# Lea toplayıcı

Lea'yı kullan. Cevapladığın her prompt, arka planda bir kez daha cevaplanır — çalışma dizininin
bir kopyasında, hazır bir Claude Code yapılandırmasıyla. İkisinin maliyeti, istersen ikisinin ne
değiştirdiği de, yerel bir deftere yazılır. Sen defteri geri gönderirsin; Lea kural seti başka
bir yerde o veriyle geliştirilir.

Senden geliştirme beklenmiyor. Kur, normal çalış, canın istediğinde tek komut çalıştır.

**English:** [README.md](README.md)

---

## Sana neye mal olacak

Prompt başına ikinci bir ajan koşusu gerçek para ve gerçek kullanım demek. Varsayılanlar bunu
bir paya hapsediyor:

| tavan | varsayılan | ne yapıyor |
|---|---|---|
| kayan 5 saat | $3 | gölge kolu penceren'in ancak bir dilimini alabilir |
| model başına, aynı pencerede | opus $2 / sonnet $1 | bir model diğerinin verisini aç bırakamaz |
| günlük | $6 | emniyet ağı |
| koşu başına | $3 | bundan büyük bir görev `truncated` yazılır, asla karşılaştırılmaz |

Ayrıca her kullanım limitinden sonra bir saat çekilir, karşılayamadığı prompt'ları kuyruğa alır
ve aynı anda en fazla bir gölge koşar. Hepsi `~/.claude/shadow/config.json` içinde; istediğin
sayıyı değiştir, ya da tamamen durdurmak için `"enabled": false` yap.

## Neye dokunuyor

```
~/.claude/hooks/          shadow-enqueue.js, shadow-collect.js, shadow-hidden-launch.vbs, lea.js
~/.claude/shadow/         runner, seçici, rapor, defterler, koşu kopyaları
~/.claude/shadow-dir.txt  tek satır, hook'lar o dizini bulabilsin diye
~/.claude/settings.json   üç hook kaydı + autoContinueAtUsageLimit, birleştirilerek - önce yedeklenir
```

Başka hiçbir şey. Çalışma dizinine asla yazılmaz: gölge ajan yalnızca
`~/.claude/shadow/runs/<id>/work/` içinde, yani bir kopyada koşar. **Hiçbir şey yüklenmiyor.**
Veri makineni ancak sen `export.ps1` çalıştırıp dosyayı gönderdiğinde terk eder.

### Değiştirdiği tek davranış ayarı, ve nedeni

`autoContinueAtUsageLimit`, kurulumun değiştirdiği hook olmayan tek ayar. CLI'ın kendi
açıklaması: *"When a claude.ai usage limit stops your session, wait for the limit to reset and
continue the task automatically. When off, the limit dialog offers the wait as a choice
instead."* Varsayılan olarak açık, çünkü 5 saatlik limitte biten bir oturum o istemin ölçümünü
geciktirmiyor, **kaybediyor**: gölge kolunun satırı çoktan yazılmış oluyor, Lea'nın turu ise hiç
yazılmıyor — yani çift yarım kaydedilmiş oluyor. Oturumun açık kalması gerekiyor ve izin
sorularında yine durabilir. `-NoAutoContinue` bu ayara dokunmaz.

**Düşük öncelik (lower-priority) bambaşka bir şey ve önceden ayarlanamıyor.** İstemciye
rate-limit yanıt başlıklarında *teklif ediliyor*, yani ancak limit gerçekten yendikten sonra var
oluyor; bayrağı, ortam değişkeni ve ayar anahtarı yok, teklif gelmeden yazılacak bir şey de yok.
Limit diyaloğundan kabul et, ya da menüyü `/rate-limit-options` ile yeniden aç. Bunların hiçbiri
gölge koluna ulaşmıyor — o headless: karşılığı `config.json`'daki erteleme kuyruğu ve limitli
koşudan sonraki bekleme, ikisi de zaten kurulu.

## Tek Anthropic hesabında birden çok kurulum

Her makinenin ve her Windows kullanıcısının kendi `~/.claude` dizini var, yani kurulumlar
birbirine karışmaz — ama **aynı Anthropic hesabına** giriş yaparlarsa aynı kullanım penceresini
harcarlar. `config.json` içindeki bütçeler kurulum başına ve birbirlerinden habersiz, dolayısıyla
N kurulum tek pencereden N katı pay alabilir.

Dağıtmadan önce böl — `-InstallsOnThisAccount <n>` bunu senin yerine yapıyor:
`window_budget_usd`, `daily_budget_usd` ve model keselerini n'e bölüyor. (`budget_usd_per_run`
bilerek bölünmüyor: tek bir koşunun tavanı, gerçek bir görevin iş ortasında kesilmesini önleyen
şey, ve kesilmiş bir koşu ucuz değil, boşa gitmiş bir koşudur.) Rapor yine dolar, sadece daha
yavaş, ve pencerenin kalanı senin kendi oturumlarına kalır.

Aynı makinedeki ikinci bir Windows kullanıcısı için Claude Code CLI'ın **o kullanıcıya** kurulu
olması gerekir — bir kullanıcının profili diğeri tarafından okunamaz. Kurulum bunu kontrol eder
ve eksikse adıyla söyler.

### Dört kurulum, iki hesap - ne yazacaksın

Her kurulumu giriş yaptığı hesabın adıyla etiketle ve o hesabı kaç kurulumun paylaştığını söyle.
Kurulum bütçeleri senin yerine böler ve etiketi her export'a yazar; böylece havuzda aynı pencere
için yarışan satırlarla yarışmayanlar ayırt edilebilir.

```powershell
# makine 1, kullanıcı 1  ve  makine 2, kullanıcı 1   -> hesap A
pwsh -File install.ps1 -Account A -InstallsOnThisAccount 2

# makine 1, kullanıcı 2  ve  makine 2, kullanıcı 2   -> hesap B
pwsh -File install.ps1 -Account B -InstallsOnThisAccount 2
```

Dördü de pencere $3 / gün $5 / opus $2 / sonnet $1 / haiku $0.50 ile koşar — şablondaki
$6 / $10 / $4 / $2 / $1 değerlerinin yarısı, hesap başına iki kurulum. Ölçülmüş bir 5 saatlik
pencere $15–20'lik token tutuyor, yani her hesap yine bir pencerenin beşte birinden azını veriyor.

## Tek makinede iki Windows kullanıcısı, tek defter

`install.ps1` bir makineyi tek katkı sağlayıcı olarak kurar: gölge dizini o profilin kendi
`~/.claude`'unun altına koyar ve var olan bir dizini başka yere yönlendirmeyi reddeder. Yeni bir
makine için doğru, ama iki profil **aynı kişinin aynı proje üzerinde çalıştığı** durumda yanlış:
iki ayrı defter olur ve `claude`'u hangi profilde başlattıysan yalnızca o kaydeder. İkinci profil
için `install-user.ps1` kullan — paralel bir defter açmak yerine birincinin defterine katılır.

```powershell
# birinci profil: defteri oluşturan normal kurulum
pwsh -File install.ps1 -Account A -InstallsOnThisAccount 2

# ikinci profil: yeni defter açma, o deftere katıl
pwsh -NoProfile -File install-user.ps1 `
     -TargetHome  C:\Users\<ikinci-kullanici> `
     -SharedShadow C:\Users\<birinci-kullanici>\.claude\shadow
```

Hedef profile yazabilen bir hesaptan çalıştır — yönetici ya da o kullanıcının kendisi. Üzerine
yazdığı her dosyayı önce yedekler, başka bir dizini gösteren `shadow-dir.txt`'yi yeniden
yönlendirmeyi reddeder ve sonunda yazdığı her hook komutunun gerçekten var olan bir dosyaya
çözüldüğünü doğrular. Hiçbir şeye dokunmadan planı görmek için `-WhatIf` ekle.

**İkinci profilde `enabledPlugins`'i de kapatır; bu yan etki değil, işin kendisi.** Eklentileri
açık bir oturum Lea değildir, dolayısıyla satırları da Lea'nın satırı değildir. İki defter de
`user`, `host` ve `lea_config` taşıyor: tek dosyaya iki kurulum yazarken, satırın kim tarafından
hangi kural setiyle yazıldığını söylemeyen bir satır, başka bir hesapta / bütçede / modelde
yazılmış bir satırdan ayırt edilemez — ve kurulumlar arasındaki fark, config'ler arasındaki fark
gibi okunur. `report.py` kurulum başına bir satır basar; `lea_config`'i `lea` olmayan hiçbir satır
Lea iddiasına katılmaz, sessizce ortalamaya karışmaz. `-KeepPlugins`'i yalnızca bilerek kullan.

İki profil de aynı iki CSV'ye eklediği için ekleme işlemleri bir kilit dosyasından
(`.ledger.lock`) geçiyor; PowerShell koşucusu ile Node hook'u aynı kilidi kullanıyor. Paylaşılan
bütçe kendiliğinden geliyor: pencere ve gün limitleri paylaşılan `shadow.csv`'den hesaplanıyor,
yani tek Anthropic hesabındaki iki profil payın tamamını ayrı ayrı harcayamıyor.

Tek kurulumdan gelen eski bir defter yeni sütunları şöyle kazanır:

```powershell
python shadow/migrate_ledgers.py          # önce görmek istersen --dry-run
```

**`claude`'u nereden başlattığın hatırlaman gereken bir kural değil.** Gölge kolu çalışma
dizininin bir kopyasının içinde cevap verir, yani o dizin kopyalanabilir olmalı — ve buna bir
kural değil, bir ön tarama karar verir. Ön tarama kopyalama fonksiyonunun kendisi olduğu için
kopyalamanın reddedeceği bir ağaca asla evet diyemez; boyut da tek başına belirleyici değil:
`max_file_mb` üstündeki dosyalar sayılmadan eleniyor. Varsayılan limitlerde 885 dosya / 56 MB'lık
bir proje sığıyor, **bir üst dizini** de sığıyor (1.649 dosya / 399 MB), ev dizini ise genelde
sığmıyor — biri 1.473 dosyada 600 MB tavanına çarptı, diğeri 20 saniyelik ön taramayı bitiremedi.

Sığmadığında `config.json` içindeki `project_roots` nerede koşulacağını söylüyor; istem atılmıyor,
ölçülüyor. Sessizce değil: satır `tree_root` kaydediyor ve `report.py` bunu Lea'nın kendi çalışma
dizini ile karşılaştırıp, iki kolu farklı ağaçtan başlamış çifti diğerlerinden ayrı tutuyor.
`project_roots` boşsa eski "atla" davranışı geri gelir. Lea'nın kendi tarafı her hâlükârda kaydeder.

## Dosyaları makineye almak

Repo private, yani klonlama aynı GitHub hesabını gerektirir:

```powershell
gh auth login          # makine ya da kullanıcı başına bir kez
gh repo clone hero-999-dev/Project-Lea
```

Ya da giriş yapmışken repo sayfasından ZIP indirip aç — toplayıcının git geçmişine ihtiyacı yok,
sadece dosyalara.

## Gereksinimler

PowerShell 7 (`pwsh`), Node, Python, git ve Claude Code CLI. Kurulum eksik olanı adıyla söyler.

## Kurulum

```powershell
git clone https://github.com/hero-999-dev/Project-Lea.git
cd Project-Lea\collector
pwsh -NoProfile -File install.ps1
```

Sonra Claude Code'u yeniden başlat. Oturum banner'ı `LEA ACTIVE` ile başlamalı.

Kendi `SessionStart` hook'un varsa ve korumak istiyorsan `-SkipLea` ekle — ama önce script'teki
notu oku: karşılaştırma *Lea'ya karşı hazır config*, yani Lea olmadan defter başka bir şey ölçer.

## Kullanırken

Normal çalış. Toplanan veriyi iki şey belirliyor:

- **Proje dizininden çalış.** Ev dizininden gönderilen prompt atlanır: ev ağacı kopyalanamayacak
  kadar büyük ve içinde `.claude`, anahtarların ve kimlik bilgilerin var.
- **Sorular her yerden toplanır.** Cevabı yanıtın içinde olan bir prompt ("X ile Y arasındaki
  fark ne") dizine ihtiyaç duymaz; onlar ev dizininden bile toplanır.

Her atlama sebebiyle birlikte deftere yazılır. Hiçbir şey sessizce düşmez.

## Elindekini gör

```powershell
python "$env:USERPROFILE\.claude\shadow\report.py"
```

Prompt başına bir satır: Lea'nın turu ne tuttu, hazır config ne tuttu, hangi config'i neden
seçti, oran ne. Bir şey göndermeden önce bunu oku.

## Geri gönder

```powershell
pwsh -NoProfile -File "$env:USERPROFILE\.claude\shadow\export.ps1"
```

Masaüstüne `lea-shadow-<makine>-<kullanıcı>-<tarih>.zip` yazar: iki defter, yazdığın prompt'lar
ve rakamları hangi modelin ve hangi bütçelerin ürettiğini söyleyen bir manifest.

**Kodunu içermez.** Yamalar — Lea'nın ne değiştirdiği ve hazır config'in ne değiştirdiği —
karşılaştırmayı yalnız maliyetten çıkarıp *kaliteye* taşıyan şey, ama onlar senin kaynak kodun.
Eklemek istersen:

```powershell
pwsh -NoProfile -File "$env:USERPROFILE\.claude\shadow\export.ps1" -IncludePatches
```

`-Since 2026-09-01` her iki biçimi de son koşularla sınırlar. Göndermeden önce zip'i aç ve oku;
içi düz CSV ve JSON.

## Durdurmak ya da kaldırmak

Toplamayı durdur, her şey kalsın: `~/.claude/shadow/config.json` içinde `"enabled": false`.

Kaldır: `~/.claude/settings.json` içindeki üç hook kaydını sil (yanında tarihli yedeği duruyor),
sonra `~/.claude/shadow/`, `~/.claude/shadow-dir.txt` ve `~/.claude/hooks/` altındaki üç
`shadow-*` dosyasını sil.

## Gönderdiğin veriye ne oluyor

Her makinenin defteri havuzlanıyor ve her satır geldiği makine ve kullanıcıyla etiketleniyor —
o etiket olmadan havuz okunamaz, çünkü model ve bütçeler kurulumdan kuruluma değişiyor.
Havuzlanan veri, Lea'nın hazır bir config'ten nerede fazla harcadığını ve nerede bunu hak
ettiğini söylüyor. Kural setinde bir değişiklik önerildiğinde buradaki her şey gibi ölçülüyor:
iki sürüm, aynı gün, aynı görev, kol başına yirmi örnek. Bunu geçemeyen öneri girmiyor.
