# ── First-time setup ─────────────────────────────────────────────────────────
# STEP 1: Install the exact package versions this project was built with.
#   Open restore.R and run it (it calls renv::restore()), OR run:
#     renv::restore()
#   Do NOT install packages manually with install.packages()/pak — that would
#   pull newer versions and break reproducibility. See README.md.

# ── STEP 2: PDFs ──────────────────────────────────────────────────────────────
# Put your PDF files in the project's   data/pdfs/   folder (it already exists).
# The results are written to            data/results.csv .
#
# IMPORTANT: open this project by double-clicking  Oddpub-postprocessing.Rproj
# in RStudio. That sets the working directory to the project root (so the paths
# below work) AND activates renv (so you get the exact locked package versions).

# ── Load packages ─────────────────────────────────────────────────────────────

library(oddpub)
library(dplyr)
library(stringr)

# Paths are relative to the project root (see the note above about the .Rproj file).
pdf_folder  <- "data/pdfs"
output_path <- "data/results.csv"

# Safety check: make sure we're running from the project root, then ensure the
# input folder exists. If this stops, open Oddpub-postprocessing.Rproj first.
if (!file.exists("renv.lock")) {
  stop("Working directory is not the project root. Open ",
       "Oddpub-postprocessing.Rproj in RStudio, then run this script again.")
}
dir.create(pdf_folder, recursive = TRUE, showWarnings = FALSE)

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
                      # ── General / international repositories ──────────────
                      "zenodo", "figshare", "dryad", "dataverse", "openneuro",
                      "open science framework", "\\bosf\\b", "mendeley data", "gigadb",
                      "github", "harvard dataverse",
                      # ── Swedish / Nordic repositories & infrastructures ───
                      "swedish national data service", "snd\\.gu\\.se", "snd\\.se",
                      "researchdata\\.se",
                      "scilifelab", "10\\.17044", "10\\.5878", "10\\.71870",
                      "bolin\\s+centre", "10\\.25504",
                      "integrated carbon observation", "\\bicos\\b", "10\\.18160",
                      # ── Life-science / sequence & omics archives ──────────
                      "european nucleotide archive", "\\bena\\b", "\\bpride\\b",
                      "proteomexchange", "gene expression omnibus", "\\bgeo\\b",
                      "european genome-?phenome archive", "\\bega\\b",
                      "global biodiversity", "\\bgbif\\b"
)

non_data_url_pattern <- "youtu\\.be|youtube\\.com|twitter\\.com|vimeo\\.com"

accession_pattern <- paste(sep = "|",
                           "PRJ[A-Z]{2}\\d+", "SAM[END]A?\\d{4,}",       # BioProject / BioSample
                           "[EPS]-[A-Z]{4}-\\d+", "S-BSST\\d+",          # ArrayExpress / BioStudies
                           "GSE\\d{2,}", "PXD\\d{6}", "MTBLS\\d{2,}",    # GEO / PRIDE / MetaboLights
                           "GCA_\\d{9}\\.\\d+", "SR[PRXSZ]\\d{3,}",      # GenBank assembly / SRA
                           "EGA[SDNCRXF]\\d{6,}"                          # EGA (controlled-access human data)
)

# ── Helper: extract all matches and collapse to semicolon-separated string ─────
extract_all_collapse <- function(text, pattern) {
  str_extract_all(text, pattern) |>
    lapply(function(x) {
      x <- str_remove(x, "[.,);>\"'\\]]+$") |> str_trim()
      x <- x[x != ""]
      if (length(x) == 0) NA_character_ else paste(unique(x), collapse = "; ")
    }) |>
    unlist()
}

# ── Post-processing ───────────────────────────────────────────────────────────
results_extended <- results |>
  mutate(
    # Prefer the precise matched sentences; fall back to ODDPub's full data-
    # availability statement (das) when those are empty, so DOIs that only
    # appear in the das (common for Swedish/SND deposits) are still caught.
    source_text_raw = coalesce(
      if_else(nchar(trimws(open_data_statements)) > 0, open_data_statements, NA_character_),
      if_else(nchar(trimws(open_code_statements)) > 0, open_code_statements, NA_character_),
      if_else(nchar(trimws(as.character(cas)))    > 0, as.character(cas),    NA_character_),
      if_else(nchar(trimws(das))                  > 0, das,                  NA_character_)
    ),
    source_text = normalize_text(source_text_raw),

    # ── DOI extraction (includes fix for two-column PDF split DOIs) ───────────
    # Extracts all DOIs; if none found directly, looks for orphan suffixes
    # from known repositories (SND: 5878/71870, Zenodo: 5281, SciLifeLab: 17044).
    extracted_doi = {
      direct <- str_extract_all(source_text, "10\\.\\d{4,}/[^\\s,);>\"']+") |>
        lapply(function(x) {
          x <- str_remove(x, "[.,);>\"'\\]]+$") |> str_trim()
          x[x != ""]
        })

      orphan <- str_extract_all(
        source_text,
        # Swedish: 5878 SND, 71870, 17044 SciLifeLab, 25504 Bolin, 18160 ICOS
        # General: 5281 Zenodo, 6084 figshare, 17632 Mendeley, 5061 Dryad,
        #          7910 Harvard Dataverse, 17605 OSF, 15468 GBIF, 5334 Dataverse
        paste0("(?<![\\d/])(",
               "5878|71870|17044|25504|18160|",
               "5281|6084|17632|5061|7910|17605|15468|5334",
               ")/[^\\s,);>\"']+")
      ) |>
        lapply(function(x) paste0("10.", str_remove(x, "[.,);>\"'\\]]+$")))

      mapply(function(d, o) {
        combined <- if (length(d) == 0) o else d
        # Keep only well-formed DOIs (10.<registrant>/<suffix>); this discards
        # stray fragments such as a bare "10." with no suffix.
        combined <- combined[str_detect(combined, "^10\\.\\d{4,}/.{2,}$")]
        if (length(combined) == 0) NA_character_
        else paste(unique(combined), collapse = "; ")
      }, direct, orphan, SIMPLIFY = TRUE)
    },

    # ── Accession numbers ─────────────────────────────────────────────────────
    # ODDPub lower-cases the statement text, so match case-insensitively and
    # normalise the hits back to upper case (e.g. PRJEB84056, PXD061695).
    extracted_accession = toupper(
      extract_all_collapse(source_text, regex(accession_pattern, ignore_case = TRUE))
    ),

    # ── URLs (excluding DOIs and video links) ─────────────────────────────────
    extracted_url = {
      str_extract_all(source_text, "https?://(?!doi\\.org)[^\\s,);>\"']+") |>
        lapply(function(x) {
          x <- str_remove(x, "[.,);>\"'\\]]+$")
          x <- x[!str_detect(x, non_data_url_pattern)]
          x <- x[x != ""]
          if (length(x) == 0) NA_character_ else paste(unique(x), collapse = "; ")
        }) |>
        unlist()
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
                       paste0("\\bavailable\\b|\\bdeposited\\b|\\baccessible\\b|\\bopenly\\b",
                              # Swedish: tillganglig / deponerad / nedladdningsbar
                              # (a-ring/a-umlaut/o-umlaut written as \\u escapes so the
                              #  file's text encoding can never break the match)
                              "|tillg\\u00e4nglig|deponerad|nedladdningsbar"))
        ) &
        !str_detect(tolower(coalesce(source_text_raw, "")),
                    paste0("^(upon request|on request|not available|not provided",
                           "|p\\u00e5 beg\\u00e4ran|vid f\\u00f6rfr\\u00e5gan)"))
    )
  ) |>
  select(-source_text_raw)

# ── Save output ────────────────────────────────────────────────────────────────
write.csv(results_extended, output_path, row.names = FALSE)

message("Done! Results saved to: ", output_path)
message("Added columns: extracted_doi, extracted_accession, extracted_url, ",
        "matched_repository, is_open_data_corrected")
