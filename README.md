# Oddpub-postprocessing

R script for extracting persistent identifiers (DOIs, accession numbers, URLs)
and repository mentions from Data Availability Statements in academic publications,
built on top of [ODDPub](https://github.com/quest-bih/oddpub).

## What it does

Runs ODDPub on a folder of PDFs and post-processes the output to extract:
- DOIs (including reconstruction of DOIs split across two-column PDF layouts)
- Accession numbers (e.g. GSE*, PXD*, PRJNA*)
- Non-DOI URLs
- Repository name (Zenodo, Figshare, SND, Dryad, OSF, etc.)
- A corrected `is_open_data` flag that catches cases ODDPub misses

## Requirements

- R ≥ 4.1.0
- RStudio (recommended): [posit.co/download/rstudio-desktop](https://posit.co/download/rstudio-desktop)
- Poppler:
  - **Windows**: download from [github.com/oschwartz10612/poppler-windows](https://github.com/oschwartz10612/poppler-windows/releases), unzip to `C:/poppler/`
  - **Mac**: `brew install poppler`
- R packages (see installation instructions at the top of the script):
  - `oddpub` (via GitHub)
  - `dplyr`
  - `stringr`

## Usage

1. Follow the installation steps at the top of `oddpub_postprocess.R`
2. Create the folder structure:
~/Desktop/oddpub/
~/Desktop/oddpub/pdfs/       ← put your PDF files here
~/Desktop/oddpub/results/    ← output CSV will be saved here
3. Run the script in RStudio
4. Output is a CSV with one row per article

## Output columns

All original ODDPub columns are retained. Added columns:

| Column | Description |
|---|---|
| `extracted_doi` | DOI found in DAS (includes split-DOI reconstruction) |
| `extracted_accession` | Accession number found in DAS |
| `extracted_url` | Non-DOI URL found in DAS |
| `matched_repository` | Repository name matched from known list |
| `is_open_data_corrected` | Corrected open data flag (extends ODDPub's detection) |

## License

GNU Affero General Public License v3.0 — see [LICENSE](LICENSE).

This script depends on [ODDPub](https://github.com/quest-bih/oddpub)
(AGPL-3.0, © QUEST Center, Berlin Institute of Health).

## Acknowledgements

Script developed with assistance from Claude Sonnet 4.6 (Anthropic), June 2026.
