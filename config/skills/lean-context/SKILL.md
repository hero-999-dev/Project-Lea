---
name: lean-context
description: Route bulky sources through local converters instead of loading them raw. Use when reading .xlsx/.xls/.docx/.pptx files, extracting article text from saved or fetched HTML, exploring CSV/Parquet/spreadsheet datasets that are too large to paste, or packing a repository into context.
---

# Lean context

Four CLIs are installed on this machine. Reach for them before pulling a bulky
source into the conversation.

| Source | Tool | Command |
|---|---|---|
| Office documents | markitdown | `markitdown report.xlsx > report.md` |
| Web pages | trafilatura | `trafilatura -u https://example.com/post --markdown` |
| Tabular data | duckdb | `duckdb -c "SELECT ... FROM read_csv_auto('data.csv')"` |
| Repositories | repomix | `repomix . --compress --token-budget 50000` |

## Rules that matter

**Query data, don't convert it.** A spreadsheet or CSV with more than a screenful
of rows goes through `duckdb`, returning only the aggregate or the sample that
answers the question. `read_xlsx()`, `read_csv_auto()`, and `read_parquet()` all
read the file in place. Converting a 100k-row sheet to markdown defeats the
purpose — that is `markitdown`'s job only for small or heavily formatted sheets
you actually need to read end to end.

**trafilatura reads local HTML from stdin.** `-i` expects a file *listing URLs*,
not an HTML file, and silently produces garbage when misused:

```powershell
Get-Content page.html -Raw | trafilatura --markdown
```

**`repomix --compress` strips function bodies.** Good for understanding a
repository's shape; useless as a base for edits, since `Edit` needs exact text
to match against.

**Route HTML to trafilatura, not markitdown.** markitdown converts HTML too, but
via markdownify, which keeps far more boilerplate. Office formats are what it is
for.

## When to skip all of this

`WebFetch` already returns markdown for a single URL — trafilatura is for saved
HTML and bulk extraction. `Read` handles PDFs natively via its `pages` parameter.
Small files are cheaper to read directly than to convert.
