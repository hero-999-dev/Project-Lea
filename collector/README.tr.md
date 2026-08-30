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
~/.claude/settings.json   üç hook kaydı, birleştirilerek - önce yedeklenir
```

Başka hiçbir şey. Çalışma dizinine asla yazılmaz: gölge ajan yalnızca
`~/.claude/shadow/runs/<id>/work/` içinde, yani bir kopyada koşar. **Hiçbir şey yüklenmiyor.**
Veri makineni ancak sen `export.ps1` çalıştırıp dosyayı gönderdiğinde terk eder.

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
