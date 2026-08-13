# SWE-DDPub

**SWE-DDPub** (`SWE` + `[O]DDPub`)
is an R pipeline for finding and describing the datasets and code shared in
academic publications. It runs [ODDPub](https://github.com/quest-bih/oddpub) to
detect data/code availability, then enriches the result: it pulls persistent
identifiers (DOIs, accession numbers, repository URLs) from the full text and
looks each DOI up against DataCite/Crossref to recover a clean repository name,
title, creators and licence — and to judge whether a dataset is the authors'
**own** or **reused**. Tuned for the Swedish research landscape.

> 🚧 **Status: experimental, work in progress (pre-1.0).** Vibe-coded with
> [Claude Code](https://claude.com/claude-code).

## What it does

Runs ODDPub on a folder of PDFs, then produces **two** outputs:

**`results.csv` — one row per article** (ODDPub's detection + post-processing):

- `is_open_data` / open-data category, plus a corrected flag that catches cases
  ODDPub misses
- DOIs (incl. reconstruction of DOIs split across two-column layouts), accession
  numbers and non-DOI URLs found in the availability statement
- Repository name matched from a known list

**`results_datasets.csv` — one row per dataset** (the enrichment layer):

- Every DOI in the full text, looked up against DataCite/Crossref so only real
  **datasets / software** are kept — no hand-maintained repository list needed,
  so it works for any repository worldwide, including small/domain-specific ones
- Clean **repository**, **title**, **creators** and **licence** from the DOI's
  own metadata
- **`provenance`** — whether the dataset is the authors' **own** or **reused**
- Non-DOI identifiers too (accession numbers, GitHub/GitLab repos) mined from
  ODDPub's data/code availability statements

## Requirements

- R and RStudio
- **Poppler** (PDF text extraction): Windows — unzip
  [poppler-windows](https://github.com/oschwartz10612/poppler-windows/releases)
  and add its `Library/bin` to PATH; macOS — `brew install poppler`
- Packages are pinned via [renv](https://rstudio.github.io/renv/) — do not
  install them manually.
- **Internet access** — the enrichment step looks DOIs up against doi.org
  (DataCite/Crossref). ODDPub detection itself runs offline.

## Setup

```sh
git clone https://github.com/Princthess/SWE-DDPub.git
```

1. Open **`SWE-DDPub.Rproj`** in RStudio. This sets the working
   directory to the project root and activates renv.
2. Run `restore.R` (`renv::restore()`) to install the locked package versions.

## Usage

- **Input:** place PDFs in `data/pdfs/`.
- **Run:** source `sweddpub.R`.
- **Output:** `data/results.csv` (one row per article) and
  `data/results_datasets.csv` (one row per dataset).

PDFs, intermediate `.txt`, outputs, and caches are git-ignored and stay local.

**Speed & caching.** ODDPub screening runs ~20 s per paper the first time, and
each DOI lookup takes a moment. Both are cached — screening in
`data/oddpub_screen_cache.rds`, DOI lookups in `data/doi_cache.csv` — so re-runs
and newly-added papers only do the new work. Delete a cache to force a re-run of
that step. A big first-time corpus can be processed in batches; nothing is
re-done.

## renv maintenance

- `renv::status()` — check whether the library matches `renv.lock`.
- `renv::restore()` — reinstall the locked versions.
- `renv::snapshot()` — record an intentional package update, then commit `renv.lock`.

## Version control

Tracked: the script, docs, `.Rproj`, `.Rprofile`, `renv.lock`, the renv
infrastructure files (`renv/activate.R`, `renv/settings.json`, `renv/.gitignore`),
`setup.R`/`restore.R`, and `data/pdfs/.gitkeep`.

Ignored: `renv/library/` (large, machine-specific, rebuilt by `restore()`) and
everything under `data/` except `.gitkeep` (your corpus and outputs).

## Output columns

### `results.csv` (one row per article)

All original ODDPub columns are retained. Added columns:

| Column | Description |
|---|---|
| `extracted_doi` | DOI found in the availability statement (includes split-DOI reconstruction) |
| `extracted_accession` | Accession number found in the availability statement |
| `extracted_url` | Non-DOI URL found in the availability statement |
| `matched_repository` | Repository name matched from a known list |
| `is_open_data_corrected` | Corrected open-data flag (extends ODDPub's detection) |

### `results_datasets.csv` (one row per dataset)

| Column | Description |
|---|---|
| `doi` | The dataset's DOI (for non-DOI rows, holds the accession number or repo URL) |
| `provenance` | `own` (authors created/shared it) or `reused` (cited third-party data) |
| `source_location` | Where found: `data_availability`, `code_availability`, or `full_text` |
| `resource_type` | `dataset`, `software`, `accession`, or `code` |
| `repository` | Repository name from the DOI's metadata (inferred for accessions) |
| `title` / `creators` / `license` | From the DOI's DataCite/Crossref metadata (blank for non-DOI rows) |

`provenance` is inferred: a dataset named in the availability statement, or whose
creators overlap the paper's authors, is `own`; otherwise `reused`. It's a
heuristic — a strong hint, not ground truth.

## Repositories & identifiers covered

Tuned for the Swedish research landscape alongside the major international
archives. To extend coverage, edit `repo_pattern`, `accession_pattern`, or the
orphan-DOI prefix list near the top of `sweddpub.R`.

> These lists drive the `matched_repository` column in **`results.csv`**. The
> **`results_datasets.csv`** layer does **not** rely on them — it identifies
> datasets by asking DataCite/Crossref what each DOI is, so it covers any
> repository, including ones not listed here.

**Swedish / Nordic**

| Repository | Matched by |
|---|---|
| Swedish National Data Service (SND / DORIS) | name, `snd.se`, `snd.gu.se`, `researchdata.se`, DOI `10.5878` |
| SciLifeLab Data Repository | name, DOI `10.17044` |
| Bolin Centre Database | name, DOI `10.25504` |
| ICOS Carbon Portal | name, `ICOS`, DOI `10.18160` |

Most Swedish universities deposit through SND/DORIS rather than running their
own repository, so SND coverage catches the bulk of institutional data.

**International**

Zenodo (`10.5281`), Figshare (`10.6084`), Dryad (`10.5061`), Mendeley Data
(`10.17632`), OSF (`10.17605`), Harvard Dataverse (`10.7910`), GigaDB,
OpenNeuro, GitHub, GBIF (`10.15468`).

**Accession-number formats**

| Archive | Format example |
|---|---|
| EGA (controlled-access human data) | `EGAS…`, `EGAD…` |
| ENA / GenBank BioProject | `PRJEB…`, `PRJNA…` |
| BioSample | `SAMEA…`, `SAMN…` |
| GEO | `GSE…` |
| PRIDE / ProteomeXchange | `PXD…` |
| MetaboLights | `MTBLS…` |
| ArrayExpress / BioStudies | `E-MTAB-…`, `S-BSST…` |
| SRA / GenBank assembly | `SRR…`, `GCA_…` |

Swedish-language availability statements (e.g. *tillgänglig*, *deponerad*) are
also recognised.

## License

GNU Affero General Public License v3.0 — see [LICENSE](LICENSE). Depends on
[ODDPub](https://github.com/quest-bih/oddpub) (AGPL-3.0, © QUEST Center, Berlin
Institute of Health).