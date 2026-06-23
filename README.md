# Oddpub-postprocessing

R script for extracting persistent identifiers (DOIs, accession numbers, URLs)
and repository mentions from Data Availability Statements in academic
publications, built on top of [ODDPub](https://github.com/quest-bih/oddpub).

> ⚠️ Vibe-coded with [Claude Code](https://claude.com/claude-code). Heuristic — sanity-check the output.

## What it does

Runs ODDPub on a folder of PDFs and post-processes the output to extract:

- DOIs (including reconstruction of DOIs split across two-column PDF layouts)
- Accession numbers (e.g. `GSE*`, `PXD*`, `PRJNA*`)
- Non-DOI URLs
- Repository name (Zenodo, Figshare, SND, Dryad, OSF, etc.)
- A corrected `is_open_data` flag that catches cases ODDPub misses

## Requirements

- R and RStudio
- **Poppler** (PDF text extraction): Windows — unzip
  [poppler-windows](https://github.com/oschwartz10612/poppler-windows/releases)
  and add its `Library/bin` to PATH; macOS — `brew install poppler`
- Packages are pinned via [renv](https://rstudio.github.io/renv/) — do not
  install them manually.

## Setup

```sh
git clone https://github.com/Princthess/Oddpub-postprocessing.git
```

1. Open **`Oddpub-postprocessing.Rproj`** in RStudio. This sets the working
   directory to the project root and activates renv.
2. Run `restore.R` (`renv::restore()`) to install the locked package versions.

## Usage

- **Input:** place PDFs in `data/pdfs/`.
- **Run:** source `oddpub-swextract.R`.
- **Output:** `data/results.csv`, one row per article.

PDFs, intermediate `.txt`, and `results.csv` are git-ignored and stay local.
Note that ODDPub runs on the order of ~20 s per paper.

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

All original ODDPub columns are retained. Added columns:

| Column | Description |
|---|---|
| `extracted_doi` | DOI found in DAS (includes split-DOI reconstruction) |
| `extracted_accession` | Accession number found in DAS |
| `extracted_url` | Non-DOI URL found in DAS |
| `matched_repository` | Repository name matched from known list |
| `is_open_data_corrected` | Corrected open-data flag (extends ODDPub's detection) |

## Repositories & identifiers covered

Tuned for the Swedish research landscape alongside the major international
archives. To extend coverage, edit `repo_pattern`, `accession_pattern`, or the
orphan-DOI prefix list near the top of `oddpub-swextract.R`.

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
