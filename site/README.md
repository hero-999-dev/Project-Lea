# The report pages

The generated report pages, copied here so they travel with the repository. Open
[`index.html`](index.html) — it frames the rest.

| page | what it is |
|---|---|
| `index.html` | the frame: the savings banner and links to everything below |
| `rapor-lea.html` | Lea itself — the ruleset, why each rule is there, and v7 against v8 |
| `rapor.html` | the four benchmark rounds, five configs, Sonnet |
| `rapor-model-karsilastirma.html` | the same rounds on Sonnet and Opus side by side |
| `rapor-opus-proje-turu.html` | the real-repository round on Opus |
| `rapor-tasarruf.html` | what Lea has saved, and what proving it has cost |
| `rapor-golge.html` | the shadow arm: what it has collected and what is blocking it |
| `savings.json` | every intermediate number behind the savings figure |

## There is no URL, and that is on purpose

The repository is **private and stays private**. GitHub Pages is refused for a private
repository on this account's plan — `POST /repos/.../pages` answers **HTTP 422, "Your current
plan does not support GitHub Pages for this repository"** (confirmed 2026-09-03). And GitHub's
own file view shows HTML as source rather than rendering it, so browsing to a page here is not
the same as reading it.

So the pages are stored to be **pulled and opened locally**. On any machine with the GitHub CLI:

```powershell
gh auth login                    # once per machine
pwsh -File site\ac.ps1           # clones on first use, pulls afterwards, then opens the page
```

Or by hand:

```powershell
gh repo clone hero-999-dev/Project-Lea
Start-Process .\Project-Lea\site\index.html
```

## These files are generated — do not edit them here

They come from the project root and are carried across by `sync_payload.py`, whose `--check`
fails when the two diverge. Editing a copy here would be edited away on the next sync. To
refresh them:

```powershell
python savings.py          # regenerates the banner and two of the pages from the live ledger
python sync_payload.py     # carries them into site/
python check_docs.py       # links, stale numbers, and the leak pass below
```

## What is deliberately not in them

No Windows user names, no machine names, no absolute paths containing an account name. Installs
appear as **account labels** (`A`, `B`) taken from the shadow directory's own `accounts` map, so
the local copy and this one are the same file and there is no scrub step to forget.
`check_docs.py` has a `leak` pass that fails the build if any of that comes back.
