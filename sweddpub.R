# SWE-DDPub: run ODDPub on PDFs in data/pdfs/ and extract DOIs,
# accessions, URLs and repository mentions to data/results.csv.
#
# Setup: open SWE-DDPub.Rproj in RStudio (sets the wd + activates
# renv), then run restore.R. Packages are pinned via renv — do not install them
# manually. See README.md for details.

# ── Load packages ─────────────────────────────────────────────────────────────

library(oddpub)
library(dplyr)
library(stringr)

# Paths are relative to the project root (the .Rproj sets the working directory).
pdf_folder  <- "data/pdfs"
output_path <- "data/results.csv"

# Guard against running from the wrong working directory.
if (!file.exists("renv.lock")) {
  stop("Working directory is not the project root. Open ",
       "SWE-DDPub.Rproj in RStudio, then run this script again.")
}
dir.create(pdf_folder, recursive = TRUE, showWarnings = FALSE)

# Convert PDFs to txt and run ODDPub
oddpub::pdf_convert(pdf_folder, output_folder = pdf_folder)
pdf_text <- oddpub::pdf_load(pdf_folder)
results  <- oddpub::open_data_search(pdf_text)

# ── Helper function: normalise PDF artefacts (line-break splits) ───────────────
# Re-joins DOIs and URLs that a PDF broke across a line. The URL rejoin is
# deliberately conservative: an earlier version glued ANY whitespace after a URL
# to the next token, which welded complete URLs onto following prose (e.g.
# "https://snd.gu.se/en acknowledgments:" -> "https://snd.gu.se/enacknowledgments:").
# We now only rejoin when the break looks like a genuine URL continuation.
normalize_text <- function(text) {
  text |>
    str_replace_all("\\b(10\\.?)\\s+(\\d{4,}/)", "\\1\\2") |>
    str_replace_all("(10\\.\\d{4,}/[^\\s]{2,20})\\s+([^\\s,);>\"']{3,})", "\\1\\2") |>
    # (a) first fragment ends in a URL-structural char, so a path clearly continues
    #     (e.g. ".../ena/" + "browser/..." -> ".../ena/browser/...")
    str_replace_all("(https?://[^\\s]{3,80}[/.=?&#_-])\\s+([^\\s,);>\"']{2,})", "\\1\\2") |>
    # (b) the continuation itself starts with a URL-structural char
    #     (e.g. "https://zenodo" + ".org/records/..." -> "https://zenodo.org/records/...")
    str_replace_all("(https?://[^\\s]{3,80})\\s+([./?#&=][^\\s,);>\"']{1,})", "\\1\\2")
}

# ── Patterns ──────────────────────────────────────────────────────────────────
# ODDPub lower-cases the statement text, which makes the short repository
# acronyms (ENA / GEO / EGA) collide with ordinary words — notably Swedish
# "ena" ("one"/"the one"). Only count these as a repository hit when an
# accession, identifier, or repo-context word sits immediately after them.
repo_acronym_ctx <- paste0(
  "(?=[^a-z0-9]{0,4}",
  "(\\d|gse|gsm|prj|sam|pxd|mtbls|sr[prxsz]|",
  "accession|database|archive|repositor|portal|deposit|browser|study|under|:))"
)

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
                      # Long-forms match unconditionally; the ambiguous acronyms
                      # require a disambiguating neighbour (see repo_acronym_ctx).
                      "european nucleotide archive", paste0("\\bena\\b", repo_acronym_ctx),
                      "\\bpride\\b", "proteomexchange",
                      "gene expression omnibus", paste0("\\bgeo\\b", repo_acronym_ctx),
                      "european genome-?phenome archive", paste0("\\bega\\b", repo_acronym_ctx),
                      "global biodiversity", "\\bgbif\\b",
                      # ── Data journals ─────────────────────────────────────
                      # A DAS that points to a data paper (a dataset published in
                      # a data journal) is itself an open-data signal. Matched by
                      # the journal's DOI prefix. Mirrors ODDPub's data_journal_dois.
                      "10\\.3390/data", "10\\.1016/j\\.dib", "10\\.1038/s41597",
                      "10\\.3897/bdj\\.", "10\\.1016/j\\.cdc\\.", "10\\.5194/essd",
                      "10\\.1002/gdj3", "10\\.1016/j\\.gdata", "10\\.5334/jo\\.d\\.",
                      "10\\.5334/ojb\\.", "10\\.1107/s2414314624", "10\\.1021/acs\\.jced",
                      "10\\.1163/24523666-bja", "10\\.18174/odjar"
)

non_data_url_pattern <- "youtu\\.be|youtube\\.com|twitter\\.com|vimeo\\.com"

# Phrases that signal data is NOT openly available — restricted, on-request, or
# absent. Used to veto our own open-data upgrade (ODDPub's own TRUE still wins).
# Unanchored (the earlier "^..." version only caught statements that *started*
# with the phrase, missing the common "...available from the corresponding
# author upon reasonable request"). Mirrors ODDPub's upon_request/not_available
# lists, plus Swedish (\u escapes so file encoding can't break the match).
restricted_pattern <- paste(sep = "|",
  "(up)?on (reasonable )?request", "by request", "can be requested",
  "available (from|on request from)( the)? (corresponding|lead) (author|contact)",
  "from the (corresponding|lead) (author|contact)",
  "bona fide research", "without undue reservation",
  "(upon|after) (reasonable )?approval",
  "not (publicly )?available", "not provided", "not (been )?deposited",
  "p\\u00e5 beg\\u00e4ran", "vid f\\u00f6rfr\\u00e5gan", "efter (rimlig )?beg\\u00e4ran"
)

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
    # TRUE if ODDPub already flagged it, OR a known repository is named AND:
    #   (a) a concrete identifier (DOI / accession / URL) was extracted — strong
    #       evidence of an actual open deposit, so an "on request" phrase
    #       elsewhere (often ODDPub merging body text into the statement) does
    #       NOT veto it; OR
    #   (b) only a vague availability word is present (no identifier) — weaker,
    #       so it counts only if the text does not signal restricted / on-request
    #       / absent data (see restricted_pattern).
    is_open_data_corrected = is_open_data | (
      !is.na(matched_repository) & (
        (!is.na(extracted_doi) | !is.na(extracted_accession) | !is.na(extracted_url)) |
          (
            str_detect(tolower(coalesce(source_text_raw, "")),
                       paste0("\\bavailable\\b|\\bdeposited\\b|\\baccessible\\b|\\bopenly\\b",
                              # Swedish: tillganglig / deponerad / nedladdningsbar
                              # (a-ring/a-umlaut/o-umlaut written as \\u escapes so the
                              #  file's text encoding can never break the match)
                              "|tillg\\u00e4nglig|deponerad|nedladdningsbar")) &
              !str_detect(tolower(coalesce(source_text_raw, "")), restricted_pattern)
          )
      )
    )
  ) |>
  select(-source_text_raw)

# ── Save output ────────────────────────────────────────────────────────────────
write.csv(results_extended, output_path, row.names = FALSE)

message("Done! Results saved to: ", output_path)
message("Added columns: extracted_doi, extracted_accession, extracted_url, ",
        "matched_repository, is_open_data_corrected")
