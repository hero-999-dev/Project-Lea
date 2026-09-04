# The report pages

The generated report pages, copied here so they travel with the repository.

**[`RAPOR.md`](RAPOR.md) is the one that opens in GitHub** — every measured number from the
pages below, in Markdown, so it renders in the browser you are already in. The `.html` files
need [`ac.ps1`](#there-is-no-url-and-that-is-on-purpose).

| page | what it is |
|---|---|
| `RAPOR.md` | all of it as one Markdown page — the only one GitHub renders |
| `index.html` | the frame: the savings banner and links to everything below |
| `rapor-lea.html` | Lea itself — the ruleset, why each rule is there, and v7 against v8 |
| `rapor.html` | the four benchmark rounds, five configs, Sonnet |
| `rapor-model-karsilastirma.html` | the same rounds on Sonnet and Opus side by side |
| `rapor-opus-proje-turu.html` | the real-repository round on Opus |
| `rapor-tasarruf.html` | what Lea has saved, and what proving it has cost |
| `rapor-golge.html` | the shadow arm: what it has collected and what is blocking it |
| `savings.json` | every intermediate number behind the savings figure |

## There is a URL now, behind a password

**https://hero-999-dev.github.io/Project-Lea/** — served from `docs/`, which holds a gate page
and the same reports one directory down, in a directory whose name is derived from the password.
Nothing in the gate's source names it, so a wrong password simply asks for a directory that is
not there.

It locks the link, not the repository. This repository is public, so the directory is visible to
anyone who browses it; the gate stops a URL from being casually shareable and nothing more.

GitHub's own file view still shows HTML as source rather than rendering it, so browsing to a page
*here* is not the same as reading it. To read them locally, on any machine with the GitHub CLI:

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
