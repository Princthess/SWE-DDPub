# ── Run once ───────────────────────────────────────────────────────────────────
# STEP 1: Install Poppler (Windows)
# Download from: https://github.com/oschwartz10612/poppler-windows/releases/
# Unzip to C:/poppler/ — make sure the path below matches your version

# STEP 2: Install R packages
# install.packages("devtools")
# devtools::install_github("quest-bih/oddpub")
# install.packages("dplyr")
# install.packages("stringr")

# ── Add Poppler to PATH and load packages ─────────────────────────────────────
# Mac users: install Poppler via Homebrew in the terminal: brew install poppler
if (.Platform$OS.type == "windows") {
  Sys.setenv(PATH = paste("C:/poppler/poppler-25.12.0/Library/bin", Sys.getenv("PATH"), sep = ";"))
}

library(oddpub)
library(dplyr)
library(stringr)

# ── Set folders ────────────────────────────────────────────────────────────────
# Create these folders on your computer before running:
#   ~/Desktop/oddpub/
#   ~/Desktop/oddpub/pdfs/       ← put your PDF files here
#   ~/Desktop/oddpub/results/    ← output CSV will be saved here
# (~ resolves to your home directory on both Windows and Mac)

pdf_folder  <- path.expand("~/Desktop/oddpub/pdfs")
output_path <- path.expand("~/Desktop/oddpub/results/results.csv")

# Convert PDFs to txt and run ODDPub
oddpub::pdf_convert(pdf_folder, output_folder = pdf_folder)
pdf_text <- oddpub::pdf_load(pdf_folder)
results  <- oddpub::open_data_search(pdf_text)

# ── Helper function: normalise PDF artefacts (line-break splits) ───────────────
normalize_text <- function(text) {
  text |>
    str_replace_all("\\b(10\\.?)\\s+(\\d{4,}/)", "\\1\\2") |>
    str_replace_all("(10\\.\\d{4,}/[^\\s]{2,20})\\s+([^\\s,);>\"']{3,})", "\\1\\2") |>
    str_replace_all("(https?://[^\\s]{3,50})\\s+([^\\s,);>\"']{3,})", "\\1\\2")
}

# ── Patterns ──────────────────────────────────────────────────────────────────
repo_pattern <- paste(sep = "|",
  "zenodo", "figshare", "dryad", "dataverse", "openneuro",
  "open science framework", "\\bosf\\b", "mendeley data", "gigadb",
  "swedish national data service", "snd\\.gu\\.se", "researchdata\\.se",
  "scilifelab", "10\\.5878", "10\\.71870",
  "european nucleotide archive", "\\bena\\b", "\\bpride\\b",
  "proteomexchange", "gene expression omnibus", "\\bgeo\\b",
  "github", "harvard dataverse"
)

non_data_url_pattern <- "youtu\\.be|youtube\\.com|twitter\\.com|vimeo\\.com"

accession_pattern <- paste(sep = "|",
  "PRJ[EDNB]\\d+", "[EPS]-[A-Z]{4}-\\d+", "GSE\\d{2,}",
  "PXD\\d{6}", "MTBLS\\d{2,}", "GCA_\\d{9}\\.\\d+", "SR[PRXSZ]\\d{3,}"
)

# ── Post-processing ───────────────────────────────────────────────────────────
results_extended <- results |>
  mutate(
    source_text_raw = coalesce(
      if_else(nchar(trimws(open_data_statements)) > 0, open_data_statements, NA_character_),
      if_else(nchar(trimws(das))                  > 0, das,                  NA_character_),
      if_else(nchar(trimws(open_code_statements)) > 0, open_code_statements, NA_character_),
      if_else(nchar(trimws(cas))                  > 0, cas,                  NA_character_)
    ),
    source_text = normalize_text(source_text_raw),

    # ── DOI extraction (includes fix for two-column PDF split DOIs) ───────────
    # First tries direct extraction; if none found, looks for orphan DOI suffixes
    # from known repositories (SND: 5878/71870, Zenodo: 5281, SciLifeLab: 17044).
    extracted_doi = {
      direct <- str_extract(source_text, "10\\.\\d{4,}/[^\\s,);>\"']+") |>
        str_remove("[.,);>\"']+$") |>
        str_trim()
      orphan <- str_extract(
        source_text,
        "(?<![\\d/])(5878|71870|5281|17044|5334|6084|17632)/[^\\s,);>\"']+"
      )
      if_else(
        is.na(direct) & !is.na(orphan),
        paste0("10.", str_remove(orphan, "[.,);>\"']+$")),
        direct
      )
    },

    # ── Accession numbers ─────────────────────────────────────────────────────
    extracted_accession = str_extract(source_text, accession_pattern),

    # ── URLs (excluding DOIs and video links) ─────────────────────────────────
    extracted_url = {
      u <- str_extract(source_text, "https?://(?!doi\\.org)[^\\s,);>\"']+") |>
        str_remove("[.,);>\"']+$")
      if_else(str_detect(coalesce(u, ""), non_data_url_pattern), NA_character_, u)
    },

    # ── Repository match ──────────────────────────────────────────────────────
    matched_repository = str_extract(tolower(source_text), repo_pattern),

    # ── Corrected is_open_data flag ───────────────────────────────────────────
    # TRUE if ODDPub already flagged it, OR if:
    #   (a) a known repository + PID was found, OR
    #   (b) a known repository + "available/deposited/accessible" in the text
    # ...and the text is not exclusively about "upon request"
    is_open_data_corrected = is_open_data | (
      !is.na(matched_repository) &
      (
        !is.na(extracted_doi) | !is.na(extracted_accession) | !is.na(extracted_url) |
        str_detect(tolower(coalesce(source_text_raw, "")),
                   "\\bavailable\\b|\\bdeposited\\b|\\baccessible\\b|\\bopenly\\b")
      ) &
      !str_detect(tolower(coalesce(source_text_raw, "")),
                  "^(upon request|on request|not available|not provided)")
    )
  ) |>
  select(-source_text_raw)

# ── Save output ────────────────────────────────────────────────────────────────
write.csv(results_extended, output_path, row.names = FALSE)

message("Done! Results saved to: ", output_path)
message("Added columns: extracted_doi, extracted_accession, extracted_url, ",
        "matched_repository, is_open_data_corrected")
