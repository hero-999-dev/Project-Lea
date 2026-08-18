# KURULUM — bir Claude Code oturumu için talimatlar

> Kendi Claude Code oturumuna bu dosyayı göster (`INSTALL.tr.md dosyasını oku ve bunu bana
> kur`), kurulumun tamamını yapabilir. Aynı adımlar elle de takip edilebilir.
>
> English: [`INSTALL.md`](INSTALL.md)

**Herhangi bir şey çalıştırmadan önce dosyanın tamamını oku.** Adım 0 bir komut değil, bir karar.

---

## Adım 0 — Gerçekte ne istediğine karar ver

Bu kurulumun birbirinden bağımsız üç parçası var. Kurulmaya değerlikleri eşit değil ve
[`guide/benchmarks.tr.md`](guide/benchmarks.tr.md) içindeki benchmark verisi bunu söylüyor:

| Parça | Kur, eğer | Atla, eğer |
|---|---|---|
| `superpowers` plugin'i | CLI'da çok adımlı kodlama işi yapıyorsan | yalnızca kısa sohbet promptları kullanıyorsan |
| `verification-activate.js` hook'u | kendinden emin ama yanlış bir "bitti" seni yaktıysa | mümkün olan en ucuz oturumları istiyorsan |
| `caveman` + `ponytail` plugin'leri | kullanımının çoğu uzun metin/açıklama ise | kullanımının çoğu agentic kodlama ise — zor bir bug fix'te **0/5** doğru ölçtüler |
| `lean-context` hook'u + skill'i | `markitdown`, `trafilatura`, `duckdb`, `repomix` kuruluysa | kurulu değilse — hook sessizce çıkar, ama skill'in tavsiyesi işe yaramaz olur |

Herhangi bir dosyayı düzenlemeden önce kullanıcıya bunlardan hangilerini istediğini sor.
Kodlama ağırlıklı bir kullanıcı için varsayılan öneri: **superpowers + verification hook'u,
caveman/ponytail olmadan.**

---

## Adım 1 — Ön koşullar

```bash
claude --version   # Claude Code CLI kurulu olmalı
node --version     # iki hook da Node scripti
```

`node` yoksa önce Node.js kur ya da hook'ları tamamen atla (adım 4–5).

---

## Adım 2 — Mevcut ayarları yedekle

`settings.json` dosyasını orijinalinin bir kopyası olmadan asla düzenleme.

**macOS / Linux**
```bash
cp ~/.claude/settings.json ~/.claude/settings.json.bak 2>/dev/null || echo "mevcut settings.json yok"
```

**Windows PowerShell**
```powershell
Copy-Item "$env:USERPROFILE\.claude\settings.json" "$env:USERPROFILE\.claude\settings.json.bak" -ErrorAction SilentlyContinue
```

---

## Adım 3 — Config'i birleştir

[`config/settings.json`](config/settings.json) dosyasını aç ve `~/.claude/settings.json`
içine birleştir.

**Birleştir, üzerine yazma.** Hedef dosyada halihazırda `permissions`, `model`, `statusLine`,
MCP config'i veya korunması gereken başka hook'lar olabilir.

Sonra birleştirilmiş dosyada:

1. `_comment` anahtarını sil.
2. Her `ABSOLUTE_PATH_TO_HOME` yerine gerçek home dizinini yaz. Hook `command` string'leri
   shell tarafından genişletilmez — `~`, `$HOME` ve `%USERPROFILE%` orada çalışmaz. Düz bir
   yol kullan, örn. `/home/ali` veya `C:/Users/ali`.
3. Adım 0'da `caveman`/`ponytail`'e hayır dediysen, ikisini de `enabledPlugins` içinde `false`
   yap ve `extraKnownMarketplaces` girdilerini sil.
4. Dört dönüştürücü CLI'ı kurmayacaksan `permissions` ve `skillOverrides` bloklarını sil.
5. `"model": "opus"` bir tercih — değiştir veya kaldır.

---

## Adım 4 — Hook'ları kopyala

[`config/hooks/`](config/hooks/) içeriğini `~/.claude/hooks/` içine kopyala.

**macOS / Linux**
```bash
mkdir -p ~/.claude/hooks
cp config/hooks/*.js ~/.claude/hooks/
```

**Windows PowerShell**
```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\.claude\hooks" | Out-Null
Copy-Item config\hooks\*.js "$env:USERPROFILE\.claude\hooks\"
```

Her iki hook'u da istemiyorsan bu adımı atla — ve atlıyorsan adım 3'te birleştirdiğin `hooks`
bloğunu da sil, yoksa her oturum scriptleri bulamayarak başlar.

---

## Adım 5 — `lean-context` skill'ini kopyala (yalnızca o hook'u aldıysan)

**macOS / Linux**
```bash
mkdir -p ~/.claude/skills/lean-context
cp config/skills/lean-context/SKILL.md ~/.claude/skills/lean-context/
```

**Windows PowerShell**
```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\.claude\skills\lean-context" | Out-Null
Copy-Item config\skills\lean-context\SKILL.md "$env:USERPROFILE\.claude\skills\lean-context\"
```

`lean-context-activate.js` bu dosyayı her oturum başında okur. Dosya yoksa hook sessizce 0 ile
çıkar ve hiçbir şey bozulmaz.

---

## Adım 6 — CLI'ı yeniden başlat

Plugin açma/kapama ve `SessionStart` hook'ları yalnızca yeni bir süreçte etkili olur.
Kapatılmış bir plugin'in hook'ları o ana kadar çalışmaya devam eder.

Bundan sonraki ilk başlangıç yavaş olacak: CLI her plugin'i indirip
`~/.claude/plugins/cache/` altına önbelleğe alır.

---

## Adım 7 — Doğrula (atlama)

```bash
claude plugin list
```

Beklenen: seçtiğin plugin'ler `✔ enabled`, gerisi `✘ disabled`.

Sonra bir oturum başlat ve şunları doğrula:

1. Hook başlıkları oturum bağlamının en üstünde görünüyor — `VERIFICATION-BEFORE-COMPLETION
   ACTIVE` ve/veya `LEAN-CONTEXT ACTIVE`.
2. Agent listesi `caveman:AGENTS` veya `caveman:CLAUDE` **içermiyor** (bkz. sorun giderme).
3. `/skills` beklediğin skill'leri listeliyor.

Modlar aktifleşmediyse sorun gidermeye geç — kurulumu körlemesine tekrarlama.

---

## Sorun giderme

**Hiçbir şey aktifleşmedi. Hook başlığı yok, caveman yok, ponytail yok.**
`SessionStart` hook'ları tek bir timeout penceresi paylaşır: süre dolduğunda tüm grup iptal
edilir ve hiçbir hook çıktısı enjekte edilmez — yani yavaş tek bir hook diğerlerinin hepsini
sessizce öldürür. Oturum transcript'inde
(`~/.claude/projects/<slug>/<session-id>.jsonl`) `hook_cancelled` ile `hook_success` ara.
`SessionStart` hook'una asla PowerShell scripti koyma; `powershell.exe` soğuk başlangıcı tek
başına ~2–3 sn. Node ~200 ms'de açılıyor.

**`claude plugin list`, skill'leri açıkça yüklenen bir plugin'i göstermiyor.**
`settings.json` içindeki `enabledPlugins`,
`~/.claude/plugins/installed_plugins.json` ile senkronunu kaybetmiş. Çözüm:
`claude plugin install <plugin>@<marketplace> -y`.

**Plugin kurulu ama eski sürüm gibi davranıyor.**
Eski bir elle kurulumdan kalan `~/.claude/skills/<ad>/SKILL.md`, plugin kopyasını gölgeliyor.
`~/.claude/plugins/cache/<marketplace>/<plugin>/<sürüm>/skills/<ad>/SKILL.md` ile `diff`'le,
sonra başıboş olanı sil veya üzerine yaz.

**Agent listesinde hayalet `caveman:AGENTS` / `caveman:CLAUDE`, hepsi tüm tool'larla
spawn edilebilir.**
Bunlar plugin'in katkı dokümanlarının agent tanımı olarak okunması. Yeniden adlandır:

```bash
cd ~/.claude/plugins/cache/caveman/caveman/*/agents/
mv AGENTS.md AGENTS.doc.txt
mv CLAUDE.md CLAUDE.doc.txt
```

Bu bir cache düzenlemesi — plugin güncellemesi dosyaları geri getirir, her güncellemeden sonra
tekrar kontrol et.

**`skillOverrides` hiçbir etki yapmıyor.**
Plugin skill'lerini gizleyemez; çözümleyici, plugin kaynaklı skill'leri ayar hiç
danışılmadan `"on"` değerine kısa devre yapar. Yalnızca `~/.claude/skills/` altındaki kendi
skill'lerinde çalışır. Bir plugin skill'i üzerindeki tek kaldıraç plugin'in tamamını kapatmak.

**Scriptli `claude -p` koşuları düz metin olarak dönüyor ve her tool çağrısı reddediliyor
(Windows).**
`PATH` üzerindeki `claude` bir `claude.cmd` batch shim'i olabilir; `cmd.exe` komut satırını bir
argümanın içindeki ilk satır sonunda keser, yani çok satırlı bir `-p` promptu kendisinden
sonraki tüm bayrakları sessizce düşürür. Scriptlerden doğrudan
`<home>/.local/bin/claude.exe` dosyasını çağır.

---

## Kaldırma

```bash
# adım 2'deki yedeği geri yükle
cp ~/.claude/settings.json.bak ~/.claude/settings.json
rm ~/.claude/hooks/verification-activate.js ~/.claude/hooks/lean-context-activate.js
rm -rf ~/.claude/skills/lean-context
```

Sonra CLI'ı yeniden başlat.

---

## Tam dokümantasyon

- [`guide/setup-guide.tr.md`](guide/setup-guide.tr.md) — her parça ne yapıyor, kapatılan her
  plugin neden kapatıldı
- [`guide/benchmarks.tr.md`](guide/benchmarks.tr.md) — önerilerin arkasındaki dört ölçülmüş tur
