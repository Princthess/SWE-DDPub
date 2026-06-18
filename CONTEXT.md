# CONTEXT — Oddpub-postprocessing

Working handoff notes. Last updated 2026-06-18.

## What we're building

An R pipeline that runs **ODDPub** (open-data/open-code detection) on a folder of
academic PDFs, then **post-processes** the output to extract persistent identifiers
and judge open-data status. Tuned for the **Swedish research landscape** (the owner
is a Chalmers researcher).

Core script: `Oddpub+Postprocessing.R`. It:
1. Converts PDFs → text and runs `oddpub::open_data_search()`.
2. Adds columns: `extracted_doi`, `extracted_accession`, `extracted_url`,
   `matched_repository`, `is_open_data_corrected`.
3. Writes `data/results.csv`.

## Current state of the codebase

**Working and verified.** Latest run produces `data/results.csv` correctly.

Project layout:
```
Oddpub-postprocessing/
├── Oddpub-postprocessing.Rproj   # open THIS in RStudio (sets wd + activates renv)
├── Oddpub+Postprocessing.R       # main script
├── data/pdfs/                    # input PDFs go here (git-ignored, .gitkeep tracked)
│   └── (results.csv written to data/)
├── renv.lock + renv/ + .Rprofile # reproducibility (renv)
├── setup.R / restore.R           # regenerate / restore packages
├── README.md, push.md, CONTEXT.md
└── .gitignore
```

- **Reproducibility:** renv pins all packages incl. `oddpub` at a GitHub commit.
  New machine → open `.Rproj`, run `restore.R`. R 4.5.2.
- **Git:** private repo https://github.com/Princthess/Oddpub-postprocessing
  (HTTPS, credentials cached). `push.md` is the git cheat-sheet.
- **Detection patterns** live near the top of the main script: `repo_pattern`,
  `accession_pattern`, orphan-DOI prefix list, and Swedish availability terms.

## Decisions made and why

- **renv over manual installs** — reproducible across machines/R updates. Script
  STEP 1 deliberately points to `restore.R`, NOT `install.packages()`.
- **`.Rproj` added + committed** — opening it sets the working dir to project root
  (so relative `data/pdfs` paths work) AND activates renv. Plain-opening the `.R`
  file does neither. A safety check (`if (!file.exists("renv.lock")) stop(...)`)
  guards against running from the wrong wd.
- **Data inside the project (`data/pdfs/`), git-ignored** — self-contained and
  obvious, but PDFs/results never get uploaded.
- **Swedish tuning** — added SND (`10.5878`), SciLifeLab (`10.17044`), Bolin
  (`10.25504`), ICOS (`10.18160`), EGA accessions, BioSample, GBIF, and Swedish
  availability words (`tillgänglig`/`deponerad`, written as `\u` escapes to dodge
  Windows file-encoding issues). Did NOT add bare `slu`/`doris`/`chalmers` — too
  many false positives (most SE universities deposit via SND anyway).

## Bugs found by comparing DAS → extracted columns, and fixed (all verified)

1. **Accessions never matched** — ODDPub lower-cases text but patterns were
   upper-case. Fixed: `regex(..., ignore_case = TRUE)` + `toupper()` on results.
2. **`das` column ignored** — DOIs that only live in `das` were missed (2 Swedish
   SND papers). Fixed: added `das` as a fallback in the `coalesce()`.
3. **BioProject pattern wrong** — `PRJ[EDNB]\d+` expects 1 letter; real accessions
   have 2 (PRJEB, PRJNA). Fixed: `PRJ[A-Z]{2}\d+`.
4. **Junk `"10."`** in `extracted_doi`. Fixed: filter to well-formed DOIs only
   (`^10\.\d{4,}/.{2,}$`).

Verification was done with a throwaway base-R script against the existing
`results.csv` statements (since `Rscript` segfaults loading stringr from the global
library — use RStudio, where the renv library works). Confirmed: buildings →
`10.5878/7v2p-gr22`, journal.pone → `10.5878/cnaf-v548` (split DOI rejoined via
orphan branch), s00253 → `PRJEB84056; PXD061695`, junk `10.` → NA.

## Gotcha worth remembering

Editing the script outside RStudio while it's open leaves RStudio running a **stale
editor buffer**. Reload from disk (don't Ctrl+S the old tab — it would overwrite
saved fixes) before re-running.

## Exact next steps

1. **Commit the fixes** (not yet pushed):
   ```
   git add -A
   git commit -m "Fix accession case-matching, das fallback, BioProject pattern, DOI validation; add data/ + .Rproj"
   git push
   ```
   (This also pushes `push.md`, `.Rproj`, the `data/` restructure, README updates,
   Swedish patterns, and this CONTEXT.md.)
2. **Skim the new `data/results.csv`** to sanity-check the four fixes landed.

## Open / optional (not blockers)

- **Truncated dataset URL** in `rsif.2023.0421` → `extracted_url` is `https://snd`
  (ODDPub cut the sentence mid-URL; full URL only in `das`). Optional fix: also
  scan `das` for URLs/accessions (low risk; not done for DOIs because `das`
  sometimes holds the article's own DOI — would need a self-DOI filter, e.g. drop
  DOIs whose suffix matches the article filename stem).
- No blockers currently.
