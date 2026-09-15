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

# ODDPub's full-text screening is the slow step (~20 s/paper) and it re-screens
# every paper on every run. Cache its output per article so each paper is screened
# only ONCE: re-runs and newly-added papers reuse the cache and only NEW papers get
# screened. (Parallelising open_data_search via plan(multisession) stalled on this
# Windows/renv setup -- 0% CPU, workers never engaged -- so we speed it up by not
# repeating work instead. The DOI-lookup parallelism further down is unaffected.)
# Stored as .rds to preserve exact column types. CAVEAT: keyed by filename -- if you
# replace a PDF's *contents* but keep its name, delete data/oddpub_screen_cache.rds
# (and the paper's .txt in data/pdfs) so it gets re-screened.
screen_cache_path <- "data/oddpub_screen_cache.rds"
screen_cache <- if (file.exists(screen_cache_path)) readRDS(screen_cache_path) else NULL
done_articles <- if (!is.null(screen_cache)) screen_cache$article else character(0)
new_articles  <- setdiff(names(pdf_text), done_articles)
message("ODDPub screening: ", length(pdf_text), " papers, ", length(done_articles),
        " cached, ", length(new_articles), " to screen ...")
if (length(new_articles) > 0) {
  new_results  <- oddpub::open_data_search(pdf_text[new_articles])
  screen_cache <- if (is.null(screen_cache)) new_results else bind_rows(screen_cache, new_results)
  saveRDS(screen_cache, screen_cache_path)
}
results <- screen_cache[screen_cache$article %in% names(pdf_text), , drop = FALSE]

# Vanilla ODDPub output (its native columns only, no post-processing) written to
# its own file for side-by-side comparison with the enriched results below. This
# is `results` before we add any columns, so it costs no extra run time.
write.csv(results, "data/results_oddpub_vanilla.csv", row.names = FALSE)
message("Wrote vanilla ODDPub output to: data/results_oddpub_vanilla.csv (",
        nrow(results), " papers)")

# ── Helper function: normalise PDF artefacts (line-break splits) ───────────────
# Re-joins DOIs and URLs that a PDF broke across a line. The URL rejoin is
# deliberately conservative: an earlier version glued ANY whitespace after a URL
# to the next token, which welded complete URLs onto following prose (e.g.
# "https://snd.gu.se/en acknowledgments:" -> "https://snd.gu.se/enacknowledgments:").
# We now only rejoin when the break looks like a genuine URL continuation.
normalize_text <- function(text) {
  text |>
    # Normalise fancy Unicode dashes (hyphen U+2010 .. horizontal bar U+2015, and
    # the minus sign U+2212) to a plain ASCII hyphen, so DOIs/URLs broken by a
    # typographic dash still match/resolve. \u escapes so file encoding can't break it.
    str_replace_all("[\u2010-\u2015\u2212]", "-") |>
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
    # str_extract_all (not str_extract) so multi-dataset papers list every
    # repository, not just the first (e.g. s00253 hits ENA + PRIDE + Figshare).
    matched_repository = extract_all_collapse(tolower(source_text), repo_pattern),

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

# NOTE: results.csv is written at the very END of this script, as ONE merged table
# (article-level flags + per-dataset detail). `results_extended` is still computed
# here because the enrichment below reuses its `is_open_data_corrected` flag and
# `das`/`cas` handling. Raw ODDPub columns live in data/results_oddpub_vanilla.csv.


# ==============================================================================
# LIST-FREE DATASET ENRICHMENT   (added 2026-08-05; run in RStudio, needs internet)
# ------------------------------------------------------------------------------
# For every DOI in the FULL paper text, ask doi.org what it is. Keep the ones
# that come back as a dataset/software; use the returned metadata for a clean
# repository name + title + license + creators; then tag each as the authors'
# OWN data (named in the availability section, or a creator surname matches the
# paper's author block) vs REUSED (a cited third-party dataset).
#
# This does NOT need a hand-maintained list of repositories: whether a link is a
# dataset is answered by the DOI's own registration (DataCite/Crossref), so it
# works for any repository worldwide, including small/domain-specific ones.
#
# One-time setup in RStudio:  renv::install(c("httr","jsonlite")); renv::snapshot()
# The per-dataset rows built here are merged with the article-level flags at the
# end of the script and written together to data/results.csv.
# ==============================================================================
library(httr)
library(jsonlite)

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

contact_email <- "therese.tikkanen@chalmers.se"   # polite User-Agent for the DOI APIs
doi_ua <- user_agent(paste0("SWE-DDPub (mailto:", contact_email, ")"))

# Look up ONE doi via doi.org content negotiation (works for Crossref AND
# DataCite). Always returns a 1-row data.frame incl. http_status + type so the
# diagnostic log can show WHY a DOI was kept or dropped. type = NA => dropped.
lookup_doi <- function(doi) {
  out <- data.frame(doi = doi, http_status = NA_integer_, type = NA_character_,
                    repository = NA_character_, title = NA_character_,
                    creators = NA_character_, license = NA_character_,
                    stringsAsFactors = FALSE)
  res <- tryCatch(
    GET(paste0("https://doi.org/", doi), doi_ua,
        add_headers(Accept = "application/vnd.citationstyles.csl+json"), timeout(20)),
    error = function(e) NULL)
  if (is.null(res)) return(out)                       # network error: status stays NA
  out$http_status <- status_code(res)
  if (out$http_status != 200) return(out)             # e.g. 404 for a malformed DOI
  m <- tryCatch(fromJSON(content(res, "text", encoding = "UTF-8"),
                         simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(m)) return(out)

  auths <- m$author
  out$creators <- if (!is.null(auths) && length(auths) > 0)
    paste(vapply(auths, function(a) {
      fam <- a$family %||% a$literal %||% ""
      giv <- a$given %||% ""
      trimws(paste0(fam, if (nchar(giv)) paste0(", ", giv) else ""))
    }, character(1)), collapse = "; ") else NA_character_

  out$type       <- m$type %||% NA_character_
  out$repository <- m$publisher %||% NA_character_
  out$title      <- if (!is.null(m$title)) as.character(m$title)[1] else NA_character_
  out$license    <- tryCatch(m$license[[1]]$URL, error = function(e) NULL) %||% NA_character_

  # License is usually absent from CSL JSON. Fall back to DataCite's native format
  # (DataCite DOIs only) and read rightsList for a licence id / URL.
  if (is.na(out$license)) {
    res2 <- tryCatch(
      GET(paste0("https://doi.org/", doi), doi_ua,
          add_headers(Accept = "application/vnd.datacite.datacite+json"), timeout(20)),
      error = function(e) NULL)
    if (!is.null(res2) && status_code(res2) == 200) {
      dc <- tryCatch(fromJSON(content(res2, "text", encoding = "UTF-8"),
                              simplifyVector = FALSE), error = function(e) NULL)
      rl <- tryCatch(dc$rightsList, error = function(e) NULL)
      if (!is.null(rl) && length(rl) > 0)
        out$license <- rl[[1]]$rightsIdentifier %||% rl[[1]]$rights %||%
                       rl[[1]]$rightsUri %||% NA_character_
    }
  }
  out
}

# Per-article full text + availability text + author-block (first ~1500 chars).
article_text <- data.frame(
  article   = names(pdf_text),
  full_text = vapply(pdf_text, function(x) paste(unlist(x), collapse = " "), character(1)),
  stringsAsFactors = FALSE) |>
  left_join(select(results, article, das, open_data_statements, cas, open_code_statements),
            by = "article") |>
  mutate(
    full_text = normalize_text(full_text),
    das_text  = normalize_text(coalesce(
      if_else(nchar(trimws(open_data_statements)) > 0, open_data_statements, NA_character_), das)),
    cas_text  = normalize_text(coalesce(
      if_else(nchar(trimws(open_code_statements)) > 0, open_code_statements, NA_character_),
      as.character(cas))),
    header    = substr(full_text, 1, 3000))

# Candidate DOIs from the FULL text (base R, no extra deps).
# The char class now also stops at < ( [ so glued PDF junk ("<section" markers,
# "(accessed", "(2018") never enters the DOI in the first place.
doi_rx <- "10\\.\\d{4,}/[^\\s,);>\"'<(\\[]+"

# Trim residual junk PDF extraction leaves on a DOI, otherwise it 404s. Strips
# trailing punctuation, then a trailing glued word after a dot (".holtmann",
# ".section") while keeping version suffixes like ".v3" (those contain a digit).
clean_doi <- function(d) {
  d <- str_remove(d, "[.,);>\"'\\]]+$")
  d <- str_remove(d, "\\.[a-z]{2,}$")
  tolower(str_trim(d))
}
cand <- do.call(rbind, lapply(seq_len(nrow(article_text)), function(i) {
  txt <- article_text$full_text[i]
  d <- clean_doi(str_extract_all(txt, doi_rx)[[1]])
  # Also capture Zenodo "record" URLs (zenodo.org/record/12345 or /records/12345),
  # which some papers use instead of a 10.xxxx DOI. The record id maps 1:1 to the
  # canonical DOI 10.5281/zenodo.<id>, so it flows through the same lookup.
  zid <- str_match_all(txt, "zenodo\\.org/records?/(\\d+)")[[1]]
  if (nrow(zid) > 0) d <- c(d, paste0("10.5281/zenodo.", zid[, 2]))
  d <- unique(d[str_detect(d, "^10\\.\\d{4,}/.{2,}$")])
  if (length(d) == 0) NULL else data.frame(article = article_text$article[i], doi = d,
                                            stringsAsFactors = FALSE)
}))

# ---- Look up each UNIQUE doi (cached across runs, fetched in parallel) --------
# Fast BUT polite, by design:
#  * a persistent cache (data/doi_cache.csv) means each DOI is fetched at most
#    ONCE, ever -- re-runs and next year's batch only fetch DOIs never seen before.
#  * only a small number of workers hit doi.org at a time (lookup_workers), plus a
#    tiny per-call pause, so we don't flood the service or peg the CPU.
# To go gentler/faster, lower/raise lookup_workers. Reuses lookup_doi() unchanged.
lookup_workers <- 5           # simultaneous requests; modest on purpose
cache_path <- "data/doi_cache.csv"

unique_dois <- unique(cand$doi)
cache <- if (file.exists(cache_path))
  read.csv(cache_path, colClasses = "character", stringsAsFactors = FALSE) else data.frame()
have <- if (nrow(cache)) cache$doi else character(0)
to_lookup <- setdiff(unique_dois, have)
message("DOIs: ", length(unique_dois), " needed, ", length(have), " already cached, ",
        length(to_lookup), " to fetch via ", lookup_workers, " workers ...")

if (length(to_lookup) > 0) {
  library(furrr)
  plan(multisession, workers = lookup_workers)
  new_meta <- future_map_dfr(
    to_lookup,
    function(d) { Sys.sleep(0.05); lookup_doi(d) },
    .options = furrr_options(packages = c("httr", "jsonlite"),
                             globals = c("lookup_doi", "doi_ua", "%||%"), seed = TRUE))
  plan(sequential)            # shut the worker processes down again
  new_meta$http_status <- as.character(new_meta$http_status)   # stable cache column
  cache <- bind_rows(cache, new_meta)
  write.csv(cache, cache_path, row.names = FALSE)
}

# Assemble this run's metadata from the (now complete) cache.
meta_tbl <- cache[match(unique_dois, cache$doi), , drop = FALSE]
meta_tbl$http_status <- suppressWarnings(as.integer(meta_tbl$http_status))

# Diagnostic: log every DOI + HTTP status + returned type so we can see WHY DOIs
# are kept or dropped (200 + dataset/software = kept; anything else = dropped).
diag_path <- "data/doi_lookup_log.csv"
write.csv(meta_tbl[, c("doi", "http_status", "type", "repository")], diag_path,
          row.names = FALSE)
message("Wrote lookup diagnostic to: ", diag_path, "  |  ",
        sum(meta_tbl$http_status == 200, na.rm = TRUE), " ok / ",
        sum(is.na(meta_tbl$http_status)), " network-fail / ",
        sum(!is.na(meta_tbl$http_status) & meta_tbl$http_status != 200), " non-200; ",
        sum(meta_tbl$type %in% c("dataset", "software", "collection")), " typed as data.")

# Keep only datasets/software (the list-free 'is it data?' filter), then tag
# own vs reused.
datasets <- cand |>
  left_join(meta_tbl, by = "doi") |>
  left_join(select(article_text, article, das_text, header), by = "article") |>
  filter(type %in% c("dataset", "software", "collection")) |>
  mutate(
    in_das = !is.na(das_text) & str_detect(tolower(das_text), fixed(doi)),
    creator_in_header = mapply(function(cr, hd) {
      if (is.na(cr) || is.na(hd)) return(FALSE)
      # Compare the dataset's creators to the paper's author block. Keep only
      # "Family, Given" creators and drop comma-less ones (orgs/usernames like
      # "ORCID", "BindingDB", "adriaat") -- those caused false "own" when the org
      # name happened to be the paper's topic. Skip datasets with >20 such creators
      # (big consortia / tools like Qiskit that a paper merely reused). Then ANY
      # matching surname in the author block => the paper's own data. Using ANY
      # creator (not just the first) catches datasets whose lead author is a
      # co-author of the paper, e.g. replication packages.
      people <- str_split(cr, ";\\s*")[[1]]
      people <- people[str_detect(people, ",")]
      if (length(people) == 0 || length(people) > 20) return(FALSE)
      surs <- str_trim(str_extract(people, "^[^,]+"))
      surs <- surs[nchar(surs) >= 3]
      if (length(surs) == 0) return(FALSE)
      any(vapply(surs, function(s) str_detect(tolower(hd), fixed(tolower(s))), logical(1)))
    }, creators, header),
    is_authors_own  = in_das | creator_in_header,
    provenance      = if_else(is_authors_own, "own", "reused"),
    source_location = if_else(in_das, "data_availability", "full_text")) |>
  select(article, doi, provenance, source_location, resource_type = type,
         repository, title, creators, license)

# ---- #1: non-DOI identifiers (accessions + code repos) from ODDPub's DAS/CAS ----
# ODDPub already isolated the availability statements; mining THOSE (not the whole
# paper) keeps precision high -- an accession or github URL sitting in the data/code
# availability statement is the paper's own by construction, so provenance = "own".
# No DOI lookup, so title/creators/license stay NA. NOTE: for these rows the "doi"
# column holds the accession or repo URL instead of a DOI.
gh_rx <- "https?://(?:github|gitlab|bitbucket)\\.[a-z.]+/[^\\s,);>\"'<(\\[]+"
accession_repo <- function(a) dplyr::case_when(
  str_detect(a, "^PRJ")       ~ "ENA/GenBank (BioProject)",
  str_detect(a, "^SAM")       ~ "BioSample",
  str_detect(a, "^GSE")       ~ "GEO",
  str_detect(a, "^PXD")       ~ "PRIDE",
  str_detect(a, "^MTBLS")     ~ "MetaboLights",
  str_detect(a, "^GCA_")      ~ "GenBank assembly",
  str_detect(a, "^SR[PRXSZ]") ~ "SRA",
  str_detect(a, "^EGA")       ~ "EGA",
  str_detect(a, "^S-BSST")    ~ "BioStudies",
  str_detect(a, "-[A-Z]{4}-") ~ "ArrayExpress",
  TRUE                        ~ NA_character_)

extra <- do.call(rbind, lapply(seq_len(nrow(article_text)), function(i) {
  art <- article_text$article[i]
  das <- article_text$das_text[i]; cas <- article_text$cas_text[i]
  mk <- function(id, loc, rtype, repo) data.frame(
    article = art, doi = id, provenance = "own", source_location = loc,
    resource_type = rtype, repository = repo, title = NA_character_,
    creators = NA_character_, license = NA_character_, stringsAsFactors = FALSE)
  rows <- list()
  # accession numbers in the DATA statement (reuse the existing accession_pattern)
  acc <- if (!is.na(das)) toupper(unique(unlist(
    str_extract_all(das, regex(accession_pattern, ignore_case = TRUE))))) else character(0)
  for (a in acc) rows[[length(rows) + 1]] <- mk(a, "data_availability", "accession", accession_repo(a))
  # code-hosting URLs (github/gitlab/bitbucket) in either statement, de-duplicated
  both <- paste(c(if (!is.na(cas)) cas, if (!is.na(das)) das), collapse = " ")
  urls <- unique(str_remove(unlist(str_extract_all(both, gh_rx)), "[.,);>\"'\\]/]+$"))
  urls <- urls[nchar(urls) > 0]
  for (u in urls) rows[[length(rows) + 1]] <-
    mk(u, "code_availability", "code", str_to_title(str_extract(u, "(?<=//)(?:www\\.)?[a-z]+")))
  if (length(rows) == 0) NULL else do.call(rbind, rows)
}))
if (!is.null(extra) && nrow(extra) > 0) datasets <- bind_rows(datasets, extra)

# ---- Merge into ONE output (results.csv): article-level flags + dataset detail --
# One row per dataset, with each paper's article-level flags repeated. Papers with
# NO dataset get a single row with the dataset columns blank, so the full set of
# screened papers -- the monitoring denominator -- stays countable. Heavy raw text
# (ODDPub's das/statements) is NOT repeated here; it lives in the vanilla file.
article_flags <- results_extended |>
  select(article, is_open_data, open_data_category, is_reuse, is_open_code,
         is_open_data_corrected)

merged <- article_flags |>
  left_join(datasets, by = "article")

write.csv(merged, output_path, row.names = FALSE)
message("Done! Wrote ", output_path, ": ", nrow(merged), " rows across ",
        nrow(article_flags), " papers (", length(unique(datasets$article)),
        " with >=1 dataset). Datasets: ",
        sum(datasets$provenance == "own", na.rm = TRUE), " own / ",
        sum(datasets$provenance == "reused", na.rm = TRUE), " reused; incl. ",
        sum(datasets$resource_type == "accession", na.rm = TRUE), " accession + ",
        sum(datasets$resource_type == "code", na.rm = TRUE), " code (non-DOI).")
