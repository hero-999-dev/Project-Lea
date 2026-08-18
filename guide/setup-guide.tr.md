# Claude Code CLI — Skill & Plugin Kurulumu

Ayarlanmış bir Claude Code skill kurulumunu başka bir makinede yeniden oluşturmak için
taşınabilir referans. Neyin kurulu olduğunu, nasıl otomatik aktifleştiğini, neyin bilerek
kapatıldığını ve nedenini, kopyalanacak tam config'i kapsar.

> **Bir token maliyet denetiminden sonra revize edildi (§5).** Etkin plugin sayısı 11'den
> 3'e indi. Bu kararın arkasındaki benchmark verisi:
> [`benchmarks.tr.md`](benchmarks.tr.md).

Bu dokümandaki yollar `~/.claude` biçiminde. Windows'ta karşılığı `%USERPROFILE%\.claude`.

---

## 1. "Skill"in üç katmanı

### A. Built-in — Claude Code ile birlikte gelir, kurulum gerektirmez

Her kurulumda otomatik mevcut: `artifact-design`, `artifact-diagramming`,
`artifact-capabilities`, `dataviz`, `claude-api`, `run`, `init`, `security-review`,
`update-config`, `keybindings-help`, `fewer-permission-prompts`, `loop`, `schedule`,
`code-review`, `simplify`.

Listede `code-review` ve `simplify` olmasına dikkat — bunlar **built-in**, ve bu yüzden
`code-review` ile `code-simplifier` plugin'leri gereksiz çıktı (§5).

### B. Resmî marketplace plugin'leri — kaynak `claude-plugins-official`, CLI zaten tanıyor

Marketplace ekleme adımı yok, sadece etkinleştir:

| Plugin | Amaç | Durum |
|---|---|---|
| `superpowers` | Meta-framework: her turda skill kontrolü disiplinini zorlar, ayrıca süreç skill'leri (brainstorming, TDD, systematic-debugging, plan yazma/uygulama, code review isteme/alma, git worktree) | **etkin** |
| `security-guidance` | `security-review` skill'ini besler, ayrıca her turda kendi LLM incelemesini çalıştıran hook'lar ekler | kapalı — §5 |
| `code-simplifier` | Yeni değişen kodu sadeleştiren agent | kapalı — built-in `simplify` ile aynı iş |
| `code-review` | `/code-review` komutu. Not: `ultra` bu plugin'den **gelmiyor** (bkz. §7) | kapalı — built-in `code-review` skill'i ile aynı iş |
| `skill-creator` | Özel skill oluşturma, düzenleme, benchmark | kapalı — superpowers `writing-skills` ile aynı iş |
| `frontend-design` | Arayüz tasarımı rehberliği | kapalı — kullanılmıyor |
| `claude-md-management` | `CLAUDE.md` dosyalarını denetleme/iyileştirme | kapalı — kullanılmıyor |
| `github` | `gh` tabanlı GitHub iş akışı yardımcıları | kapalı — MCP sunucusu tanımsız bir env değişkeni istiyor (§6) |
| `feature-dev` | Rehberli feature geliştirme (code-architect / code-explorer / code-reviewer agent'ları) | kapalı — kullanılmıyor |

### C. Üçüncü parti marketplace plugin'leri — önce marketplace kaydı gerekir

| Plugin | Marketplace repo | Amaç | Durum |
|---|---|---|---|
| `ponytail` | `github:DietrichGebert/ponytail` | Tembel-kıdemli-geliştirici modu — en basit/en kısa çalışan kod, YAGNI | **etkin** |
| `caveman` | `github:JuliusBrussee/caveman` | Aşırı sıkıştırılmış, kısa metin modu | **etkin** |

> `caveman` ve `ponytail`'i global olarak açmadan önce §5'i ve benchmark raporunu oku.
> Metin ağırlıklı işte büyük kazanç, çok adımlı agentic kodlamada ölçülmüş **kayıp**.

---

## 2. Yeni makinede yeniden oluşturma

[`config/settings.json`](../config/settings.json) dosyasını `~/.claude/settings.json` ile
birleştir, sonra CLI'ı yeniden başlat:

```json
{
  "enabledPlugins": {
    "superpowers@claude-plugins-official": true,
    "ponytail@ponytail": true,
    "caveman@caveman": true,
    "code-simplifier@claude-plugins-official": false,
    "frontend-design@claude-plugins-official": false,
    "skill-creator@claude-plugins-official": false,
    "security-guidance@claude-plugins-official": false,
    "code-review@claude-plugins-official": false,
    "claude-md-management@claude-plugins-official": false,
    "github@claude-plugins-official": false,
    "feature-dev@claude-plugins-official": false
  },
  "extraKnownMarketplaces": {
    "ponytail": { "source": { "source": "github", "repo": "DietrichGebert/ponytail" } },
    "caveman":  { "source": { "source": "github", "repo": "JuliusBrussee/caveman" } }
  }
}
```

`false` girdileri silinmek yerine bırakıldı; böylece karar kayıtlı kalıyor ve tek bir düzenleme
ile biri tekrar açılabiliyor.

CLI içinden eşdeğer açık yol:

```
/plugin marketplace add DietrichGebert/ponytail
/plugin marketplace add JuliusBrussee/caveman
/plugin install superpowers@claude-plugins-official
/plugin install ponytail@ponytail
/plugin install caveman@caveman
```

Her iki yolda da CLI, plugin'leri ilk kullanımda `~/.claude/plugins/cache/` altına indirir ve
önbelleğe alır.

---

## 3. Hemen aktif olanlar ve istek üzerine çalışanlar

**Plugin etkinleştirildiği anda otomatik aktif.** Her biri kendi kural setini bir
`SessionStart` hook'u ile gizli bağlama yazar — tetikleyici ifade gerekmez:

- `superpowers` → `using-superpowers` meta-kuralı ("bir skill uygulanabilir görünüyorsa,
  çağırmak zorundasın")
- `caveman` → kısa metin modu, varsayılan yoğunluk `full`
- `ponytail` → tembel/minimum kod modu, varsayılan yoğunluk `full`

Son ikisinin yoğunluğu oturumlar arasında `~/.claude/.caveman-active` ve
`~/.claude/.ponytail-active` dosyalarında saklanır. `ponytail` ayrıca bir `SubagentStart`
hook'u kaydeder, yani kuralları sadece ana threade değil, spawn edilen subagent'lara da ulaşır.

### Elle yazılmış iki always-on hook

Hiçbiri bir plugin'in parçası değil. [`config/hooks/`](../config/hooks/) klasörünü
`~/.claude/hooks/` içine kopyala ve tek bir `SessionStart` girdisine bağla:

```json
"hooks": {
  "SessionStart": [{
    "matcher": "startup|resume|clear|compact",
    "hooks": [
      {
        "type": "command",
        "command": "node \"<MUTLAK-YOL>/.claude/hooks/verification-activate.js\"",
        "timeout": 20,
        "statusMessage": "Loading verification-before-completion..."
      },
      {
        "type": "command",
        "command": "node \"<MUTLAK-YOL>/.claude/hooks/lean-context-activate.js\"",
        "timeout": 20,
        "statusMessage": "Loading lean-context..."
      }
    ]
  }]
}
```

- **`verification-activate.js`** `verification-before-completion` kuralını kalıcı olarak açık
  tutar; superpowers içinde normalde istek üzerine çalışır. Metnini **inline** yazar —
  superpowers `SKILL.md` dosyasını okumaz. O skill dosyası ~3,6 KB tablo ve gerekçe listesi,
  uygulanabilir çekirdek (Iron Law, kapı, kırmızı bayraklar) ise ~1 KB. Inline yazmak yükü
  3537 → 1060 karaktere düşürdü ve aynı anda iki kırılgan bağımlılığı ortadan kaldırdı:
  superpowers'ın kurulu olması zorunluluğu ve hangi cache dizininin güncel olduğunu tahmin
  etme ihtiyacı. Tam skill hâlâ `/superpowers:verification-before-completion` ile erişilebilir.
- **`lean-context-activate.js`** kişisel bir `lean-context` skill'ini sabitler (hacimli
  kaynakları ham okumak yerine `markitdown` / `trafilatura` / `duckdb` / `repomix` üzerinden
  geçir). Bu hook kaynağını **okur** (`~/.claude/skills/lean-context/SKILL.md`), böylece ikisi
  senkron kalır; o dosya inline yazmayı gerektirmeyecek kadar küçük. Skill
  [`config/skills/lean-context/`](../config/skills/lean-context/) içinde geliyor — o dört
  CLI'ın kurulu olduğunu varsayar, kurulu değilse bu hook'u atla.

İkisi de kaynağı bulunamazsa sessizce 0 ile çıkar; yarım göç etmiş bir makine oturumu
kırmak yerine yeteneğini kaybeder.

> Tarihsel not, `plugins/cache/` içine uzanan **yeni** hook'lar için hâlâ geçerli: önbelleğe
> alınmış `superpowers/*` dizinlerini dizin adını parse ederek değil, **mtime**'a göre sırala.
> O dizinler ya sürümle ya commit sha ile adlandırılır (`b36e0829c6d0`) ve bir sha üzerinde
> `[version]` cast'i hata fırlatır. Yinelenen dizin durumu gerçek (§6).

**Geri kalan her şey istek üzerine** — bir `/slash-command` ile, açık bir tetikleyici ifadeyle
veya `using-superpowers` meta-kuralının mevcut göreve uymasıyla çağrılır:

- superpowers süreç skill'leri: `brainstorming`, `systematic-debugging`,
  `test-driven-development`, `writing-plans`, `executing-plans`, `requesting-code-review`,
  `receiving-code-review`, `finishing-a-development-branch`, `subagent-driven-development`,
  `using-git-worktrees`, `dispatching-parallel-agents`, `writing-skills`
- caveman/ponytail ekleri: `cavecrew` (+ üç subagent'ı), `caveman-explore`, `caveman-commit`,
  `caveman-review`, `ponytail-review`, `ponytail-audit`, `ponytail-debt` ve iş akışı
  skill'leri (`surgical-patch`, `safe-refactor`, `lean-build`, `migration`,
  `investigate-first`, `verify-and-stop`)
- built-in'ler: bkz. §1A

---

## 4. Gerçek hata ayıklama zamanına mal olmuş tuzaklar

- **Yavaş tek bir `SessionStart` hook'u diğerlerinin hepsini öldürür.** `SessionStart`
  hook'ları tek bir timeout penceresini paylaşır; süre dolduğunda tüm grup iptal edilir ve
  **hiçbir** hook çıktısı enjekte edilmez — yani yavaş bir özel hook, caveman ve ponytail'i
  de sessizce yanında götürür ve oturum, plugin'ler hiç kurulmamış gibi görünür. Gözlenen
  vaka: PowerShell tabanlı bir verification hook'u 5000 ms bütçeye karşı 5738 ms sürdü
  (transcript'te `hook_cancelled` / `timedOut: true`), ve üç mod birden kayboldu. Windows'ta
  `powershell.exe` soğuk başlangıcı tek başına ~2–3 sn ve plugin cache yazılırken daha da
  yükseliyor, bu yüzden **`SessionStart` hook'una asla PowerShell koyma** — Node ~200 ms'de
  açılıyor. Teşhis: oturum transcript'inde
  (`~/.claude/projects/<slug>/<session-id>.jsonl`) `hook_cancelled` ile `hook_success`
  aramak. İlgili: `security-guidance` `"timeout": 180` ile bir `SessionStart` hook'u
  kaydediyor, bu da aynı arızanın tekrarında sürekli baş şüpheli olmasını sağlıyor.

- **Başıboş gölge dosya.** Eski bir elle kurulumdan kalan
  `~/.claude/skills/<ad>/SKILL.md`, `settings.json` doğru görünse bile plugin sürümünü
  sessizce gölgeler — plugin kurulu görünür ama yanlış davranır. Çözüm: başıboş dosyayı
  `~/.claude/plugins/cache/<marketplace>/<plugin>/<sürüm-hash>/skills/<ad>/SKILL.md` ile
  `diff`'le, farklıysa üzerine yaz.

- **Etkin ≠ kurulu.** `settings.json`, `enabledPlugins` altında bir plugin'i listelerken
  `~/.claude/plugins/installed_plugins.json` içinde ona ait kayıt olmayabilir — gözlenen bir
  vakada marketplace yenilemesi iki plugin'i o kayıttan düşürdü. Belirti: skill'leri hâlâ
  yüklenmesine rağmen `claude plugin list` plugin'i göstermiyor. Çözüm:
  `claude plugin install <plugin>@<marketplace> -y` (yeniden kaydeder, yeniden yapılandırma
  gerekmez). `plugin list` ile oturumun gördüğü şey uyuşmadığında bu iki dosyayı karşılaştır.

- **Bir plugin'in `agents/` klasöründeki başıboş `.md`, hayalet agent'a dönüşür.** caveman,
  `agents/AGENTS.md` ve `agents/CLAUDE.md` dosyalarını katkıda bulunan dokümanı olarak
  gönderiyor. YAML frontmatter'ın olmaması bunları dışarıda bırakmıyor — agent listesinde
  `caveman:AGENTS` ve `caveman:CLAUDE` olarak, yalnızca "Agent from caveman plugin" açıklamasıyla
  ve her biri **All tools** ile spawn edilebilir şekilde çıkıyorlar. Çözüm: ikisini de
  `.doc.txt` olarak yeniden adlandır. Bunu `settings.json` üzerinden yapacak bir
  `agentOverrides` ayarı yok, yani bu bir cache düzenlemesi ve **yukarı akış plugin
  güncellemesi dosyaları geri getirir** — her caveman güncellemesinden sonra tekrar kontrol et.

- **Sabit kodlanmış yollar.** `settings.json` içindeki hook `command` girdileri mutlak yol
  ister. Bu config'i başka bir hesaba veya makineye kopyalarken, §2'deki bloğu yapıştırmadan
  önce home dizini kısmını değiştir (veya `$HOME` / `%USERPROFILE%` kullan). CLI binary'si ile
  config ağacının aynı kullanıcı altında olması gerekmez — dosya ararken birinin diğerini
  ima ettiğini varsayma.

- **Windows ve POSIX farkı.** Elle yazılmış iki hook da Node, yani zaten platformdan bağımsız
  — macOS/Linux'ta bash'e çevirmeye gerek yok. Plugin'lerin kendi hook'ları (caveman,
  ponytail) hem POSIX `command` hem de `commandWindows` varyantı gönderiyor, yani onlar da
  değişiklik istemiyor.

- **Windows'ta batch shim argüman kırpması.** `PATH` üzerindeki `claude`, `%*` ile
  yönlendiren bir `claude.cmd` batch shim'ine çözülüyorsa, `cmd.exe` komut satırını bir
  argümanın içindeki ilk satır sonunda keser. Çok satırlı bir `-p` promptu bu yüzden
  kendisinden sonraki tüm bayrakları sessizce düşürür — `--output-format json` ve
  `--permission-mode bypassPermissions` ikisi de kaybolur, koşu düz metin olarak döner ve her
  tool çağrısı reddedilir. Belirti bir izin hatası gibi görünür ama değildir. Scriptlerden
  gerçek çalıştırılabilir dosyayı (`<home>/.local/bin/claude.exe`) doğrudan çağır.

---

## 5. Token maliyet denetimi

Etkin her plugin, sen daha bir şey yazmadan **her** oturumda token harcar: `SessionStart`
hook çıktısı, artı modele giden listelerde her skill ve her agent için birer satır. Ölçülen
temel değerler, karakter cinsinden:

| Kaynak | Önce | Sonra |
|---|---:|---:|
| `SessionStart` enjeksiyonları (5 hook) | 18.533 | 16.056 |
| Plugin skill listesi | 13.322 | 12.280 |
| Plugin agent listesi (kaldırılan girdiler) | — | −1.323 |
| **Toplam** | **31.855** | **~27.013** |

Oturum başına kabaca 1.300 token, doğrulanmış.

### Ölçülen başlangıç maliyeti

`claude -p`, Haiku, aynı prompt:

| Config | Prompt token |
|---|---:|
| plugin yok, özel hook yok | 22.651 |
| caveman+ponytail kapalı, superpowers açık | 24.842 |
| **3 plugin'li config (bu kurulum)** | **27.803** |
| eski 11 plugin'li config | 29.137 |

Oturum başına 1.334 token tasarruf = toplam promptun %4,6'sı, plugin+hook yığınının %20,6'sı.
caveman+ponytail'in kendi sabit input maliyeti: oturum başına **2.961 token**.

### Kesintiler nasıl seçildi

`~/.claude.json` gerçek kullanımı `pluginUsage` ve `skillUsage` altında kaydediyor. 22
başlangıç boyunca yedi plugin `usageCount: 0` idi — `code-simplifier`, `frontend-design`,
`skill-creator`, `code-review`, `claude-md-management`, `github`, `feature-dev`. Bunların
üçü zaten var olan bir şeyi tekrarlıyordu (§1A/§1B "Durum" sütunu), yani kapatmak hiçbir
yetenek kaybı doğurmadı. Bu dokümandaki neyin kullanılıp kullanılmadığına dair iddialara
güvenmeden önce aynı dosyaya bak:

```
node -e "const c=require(process.env.USERPROFILE+'/.claude.json'); console.log(c.pluginUsage)"
```

macOS/Linux'ta:

```
node -e "const c=require(process.env.HOME+'/.claude.json'); console.log(c.pluginUsage)"
```

### `security-guidance` kötü çalıştığı için değil, maliyeti yüzünden kapatıldı

`hooks.json` dosyası `security_reminder_hook.py` (111 KB) betiğini **her**
`UserPromptSubmit`'te, `Edit|Write|MultiEdit|NotebookEdit` için her `PostToolUse`'da, her
`Bash`'te ve her `Stop`'ta çalıştırıyor — log, bir saniye içinde altı Python spawn'ı gösterdi.
Bir git reposu dışında erken çıkıyor (`Stop hook: empty review set`), tool çağrısı başına
sadece ~150–300 ms. **Bir git reposu içinde ise `Stop` hook'u `asyncRewake: true` ve her turda
Agent SDK ile bir güvenlik incelemesi çalıştırıyor, faturası oturumun kendisiyle aynı kotaya
yazılıyor.** Bu kurulumdaki tek en büyük tekrarlayan maliyet bu. İstek üzerine çalışan
karşılıkları: built-in `/security-review` ve `/code-review`.

Plugin'in her düzenlemede verdiği desen uyarılarını, her turdaki LLM incelemesi olmadan
istiyorsan hook'lar plugin'in kendi `hooks/hooks.json` dosyasında — ama orayı düzenlemek bir
cache düzenlemesi ve güncelleme geri alır. `settings.json` hook'ları toplamsaldır, yani bir
plugin'in hook'unu kullanıcı ayarlarından çıkarmanın yolu yok; tek kaldıraç açmak veya kapatmak.

### `skillOverrides` — ne yapabilir, ne yapamaz

Şema, skill adına göre dört değer:

| Değer | Etki |
|---|---|
| `"on"` | yoksa varsayılan |
| `"name-only"` | skill'i açıklaması olmadan listeler |
| `"user-invocable-only"` | modelden gizler, `/ad` yazılabilir kalır |
| `"off"` | ikisinden de gizler |

`disableBundledSkills`, Claude Code ile gelen skill'ler için ayrı bir anahtar.

**Plugin skill'lerinde çalışmaz — tasarım gereği.** Çözümleyici şunu okuyor:
`if (e.type !== "prompt" || e.source === "plugin") return "on"` — yani plugin kaynaklı bir
skill, `skillOverrides` hiç danışılmadan `"on"` değerine kısa devre yapıyor. Bu bir anahtar
biçimi veya sözdizimi sorunu değil ve yeniden başlatmak düzeltmiyor. Deneysel olarak
doğrulandı: 13 girdilik bir deneme **sıfır** token tasarruf etti, çünkü 12'si plugin
skill'iydi; işe yarayan tek girdi `~/.claude/skills/` altındaki gerçek bir kullanıcı
skill'iydi. **Plugin skill'leri üzerindeki tek kaldıraç, `enabledPlugins` ile plugin'in
tamamını kapatmak.**

`skillOverrides` oturum başlangıcında değil, canlı uygulanır — dosya düzenlendiğinde liste
oturum ortasında değişiyor.

### Bütçe tavanı — skill listesini kısaltmak neden hiçbir şey kazandırmıyor

Skill listesinin tamamı yalnızca ~2.588 token tutuyor ve `skillListingBudgetFraction` ile
sınırlanıyor (varsayılan: bağlam penceresinin %1'i, karakter cinsinden). Liste tavanı aştığında
açıklamalar sığacak şekilde kısaltılıyor — yani skill kaldırmak toplamı **küçültmüyor**, sadece
kalanların daha uzun açıklama tutmasına izin veriyor. Dolayısıyla "token kazanmak için skill
listesini kısalt" fikri baştan yanlış; kısaltmak tetikleme isabetini artırır, token kazandırmaz.

Faydalı yan bulgu: `/skills` arayüzü plugin başına **"Skill-listing footprint … ~N tok/turn"**
bilgisi veriyor, yani plugin başına listeleme maliyeti tahmin edilmeden doğrudan okunabiliyor.

### Yeniden başlattıktan sonra denetimin tuttuğunu doğrula

1. `claude plugin list` → 3 `✔ enabled`, 8 `✘ disabled`.
2. Agent listesi artık `caveman:AGENTS` veya `caveman:CLAUDE` sunmuyor.
3. `security-guidance` kapatıldıktan sonra `~/.claude/security/log.txt` büyümeyi durduruyor.

Kapatılan bir plugin'in hook'ları süreç yeniden başlayana kadar yüklü kalır — güvenlik logu,
plugin'in kapatıldığı oturumun geri kalanında büyümeye devam etti, sonra durdu.

---

## 6. Disk ve MCP notları

- **Yinelenen plugin cache.** `~/.claude/plugins/cache/claude-plugins-official/superpowers/`
  hem `6.3.0/` hem `b36e0829c6d0/` dizinini barındırabiliyor; her biri 1,6 MB, içerik aynı,
  `installed_plugins.json` yalnızca birine referans veriyor. Sadece disk israfı — skill listesi
  her skill'i bir kez gösterdiği için token maliyeti yok. Plugin yöneticisinin hâlâ takip
  ettiği bir cache girdisini silmek 1,6 MB'a değmez.
- **Global MCP sunucusu yok.** `~/.claude.json` içinde boş bir `mcpServers` önemli, çünkü MCP
  tool şemaları potansiyel olarak en büyük tek bağlam yutucusudur.
- **`github` plugin'inin MCP sunucusu token istiyor.** `.mcp.json` dosyası
  `https://api.githubcopilot.com/mcp/` adresini `Authorization: Bearer
  ${GITHUB_PERSONAL_ACCESS_TOKEN}` ile hedefliyor. Bu değişkeni ayarlayan bir `env` bloğu
  yoksa her başlangıçta başarısız olmaya mahkûm bir bağlantı deniyor. Bu plugin'i istiyorsan
  önce token'ı ayarla:

  ```json
  "env": { "GITHUB_PERSONAL_ACCESS_TOKEN": "ghp_..." }
  ```

  Gerçek token'ları commit ettiğin hiçbir dosyaya koyma.

---

## 7. `ultra` code review faturalıdır, yapılandırma değildir

`/code-review ultra` (takma ad `/ultrareview`, CLI `claude ultrareview [hedef]`) **CLI
binary'sinin içinde gömülü**, `code-review` plugin'inden gelmiyor — plugin kurmak veya
kaldırmak onu etkilemiyor. Bu yüzden o plugin'i kapatmak (§5) `ultra`'ya dokunmuyor. Mevcut
dala veya bir PR'a karşı bulut tabanlı bir agent filosu başlatıyor; 5 agent'lı bir Opus filosu
~5–10 dakika sürüyor ve **çalıştırma başına 5–25 dolar**, ekstra kullanım / aşım kredisine
yazılıyor.

Yani ayarlarla değil, **kredi durumuyla** görünüp kayboluyor. `~/.claude.json` içinde
`cachedExtraUsageDisabledReason: "out_of_credits"` görünüyorsa seçenek slash menüsünden
gizlenir — bozuk bir şey yoktur ve çevrilecek bir anahtar da yoktur. Ekstra kullanım kredisi
yüklendiğinde geri gelir. Kontrol:

```
node -e "const c=require(process.env.USERPROFILE+'/.claude.json'); console.log(c.cachedExtraUsageDisabledReason ?? 'credits OK')"
```

Ayrıca oturum içinden senin adına başlatılamaz — yalnızca kullanıcı tetikler.

---

## 8. Burada kapsanmıyor — memory ayrı

`MEMORY.md` ve `~/.claude/projects/.../memory/*.md` yerel dosyalardır, plugin değil; plugin
kurmak bunları **kopyalamaz**. Hatırlanan proje bilgilerini, geri bildirimleri ve tercihleri
yeni makineye taşımak için o memory klasörünü ayrıca kopyala. İçinde o makinedeki oturumların
hatırlamayı seçtiği her şey vardır, bu yüzden kimseyle paylaşmadan önce gözden geçir.

---

## 9. Bu reponun bilerek göndermediği ayarlar

- `skipDangerousModePermissionPrompt` — bypass-permissions moduna girmeden önceki onayı
  bastırır. O onay olmadan çalışmak makineye özgü bir risk kararıdır, kopyalanacak bir
  varsayılan değil.
- Özel bir `statusLine` komutu — makineye özgü ve kozmetik.
- `permissions.allow` girdileri — her biri makinende kalıcı bir izin demektir. Gönderilen
  `settings.json` yalnızca dört `lean-context` dönüştürücü CLI'ına izin veriyor, o da bu
  bölümü tutarsan. Onları kurmayacaksan bölümü sil.

---

*Neyin gerçekten etkin olduğunun tek doğru kaynağı her zaman ilgili makinedeki
`~/.claude/settings.json` ve `~/.claude/plugins/installed_plugins.json` dosyalarıdır — aradan
çok zaman geçtiyse bu dosyaya güvenmeden önce onları kontrol et.*
