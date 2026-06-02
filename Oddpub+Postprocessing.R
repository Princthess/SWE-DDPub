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
Sys.setenv(PATH = paste("C:/poppler/poppler-25.12.0/Library/bin", Sys.getenv("PATH"), sep = ";"))

library(oddpub)
library(dplyr)
library(stringr)

# ── Set folders ────────────────────────────────────────────────────────────────
pdf_folder  <- "C:/Users/thereset/Documents/OddPubTest/NyKorpus" # ⚠️ Change this
output_path <- "C:/Users/thereset/Documents/OddPubTest/resultss.csv"   # ⚠️ Change this

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

    # ── All DOIs found (semicolon-separated) ──────────────────────────────────
    extracted_dois_all = sapply(source_text, function(txt) {
      if (is.na(txt)) return(NA_character_)
      hits <- str_extract_all(txt, "10\\.\\d{4,}/[^\\s,);>\"']+")[[1]]
      hits <- str_remove(hits, "[.,);>\"']+$")
      hits <- unique(hits[nzchar(hits)])
      if (length(hits) == 0) NA_character_ else paste(hits, collapse = "; ")
    }),
    extracted_doi = str_extract(extracted_dois_all, "^[^;]+") |> str_trim(),

    # ── Fix for DOIs split across two-column PDF layouts (>10 char gap) ───────
    # Looks for "orphan" DOI suffixes starting with known repository prefixes.
    # Covers: SND (5878, 71870), Zenodo (5281), SciLifeLab (17044) and others.
    orphan_doi_suffix = str_extract(
      source_text,
      "(?<![\\d/])(5878|71870|5281|17044|5334|6084|17632)/[^\\s,);>\"']+"
    ),
    reconstructed_doi = if_else(
      is.na(extracted_doi) & !is.na(orphan_doi_suffix),
      paste0("10.", str_remove(orphan_doi_suffix, "[.,);>\"']+$")),
      NA_character_
    ),

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

    # ── Combined PID: DOI > reconstructed DOI > accession number > URL ────────
    extracted_pid = coalesce(
      extracted_doi,
      reconstructed_doi,
      extracted_accession,
      extracted_url
    ),

    # ── Corrected is_open_data flag ───────────────────────────────────────────
    # TRUE if ODDPub already flagged it, OR if:
    #   (a) a known repository + PID was found, OR
    #   (b) a known repository + "available/deposited/accessible" in the text
    # ...and the text is not exclusively about "upon request"
    is_open_data_corrected = is_open_data | (
      !is.na(matched_repository) &
      (
        !is.na(extracted_pid) |
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
message("New columns: extracted_dois_all, extracted_doi, reconstructed_doi, ",
        "extracted_accession, extracted_url, matched_repository, ",
        "extracted_pid, is_open_data_corrected")
