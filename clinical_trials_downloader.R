#!/usr/bin/env Rscript
# ClinicalTrials.gov Document Downloader (R version)
#
# Downloads study documents (protocols, SAPs, informed consent forms)
# from ClinicalTrials.gov using the API v2.
#
# Dependencies: httr, jsonlite
#   install.packages(c("httr", "jsonlite"))
#
# Usage:
#   source("clinical_trials_downloader.R")
#   download_study_docs("NCT04280705")
#   search_and_download(condition = "diabetes", doc_types = "protocol", max_studies = 5)

suppressPackageStartupMessages({
  library(httr)
  library(jsonlite)
})

BASE_API_URL <- "https://clinicaltrials.gov/api/v2/studies"
CDN_BASE_URL <- "https://cdn.clinicaltrials.gov/large-docs"
API_HEADERS  <- add_headers(`User-Agent` = "ClinicalTrialsDocDownloader/1.0 (R research tool)")

# aggFilters values used by the ClinicalTrials.gov API v2
DOC_AGG_CODES <- list(protocol = "prot", sap = "sap", icf = "icf")

# Fields to request — omit to get full response including largeDocumentModule
API_FIELDS <- NULL

DOC_TYPE_LABELS <- c(
  Prot         = "Protocol",
  SAP          = "Statistical Analysis Plan",
  ICF          = "Informed Consent Form",
  Prot_SAP     = "Protocol + SAP",
  Prot_ICF     = "Protocol + ICF",
  Prot_SAP_ICF = "Protocol + SAP + ICF"
)

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

.parse_study <- function(study) {
  proto       <- study$protocolSection
  id_mod      <- proto$identificationModule
  sponsor_mod <- proto$sponsorCollaboratorsModule
  docs_mod    <- study$documentSection$largeDocumentModule  # NOT under protocolSection

  list(
    nct_id       = id_mod$nctId %||% "",
    title        = id_mod$briefTitle %||% "",
    lead_sponsor = sponsor_mod$leadSponsor$name %||% "Unknown",
    docs         = docs_mod$largeDocs %||% list()
  )
}

# Null-coalescing operator
`%||%` <- function(x, y) if (!is.null(x)) x else y

.doc_matches_filter <- function(type_abbrev, doc_type_filter) {
  any(
    ("protocol" %in% doc_type_filter & grepl("Prot", type_abbrev)),
    ("sap"      %in% doc_type_filter & grepl("SAP",  type_abbrev)),
    ("icf"      %in% doc_type_filter & grepl("ICF",  type_abbrev))
  )
}

# ---------------------------------------------------------------------------
# API functions
# ---------------------------------------------------------------------------

#' Fetch document metadata for a single study by NCT ID.
#'
#' @param nct_id  Character. NCT identifier, e.g. "NCT04280705".
#' @return Named list with nct_id, title, lead_sponsor, docs, or NULL on error.
get_study_by_nct_id <- function(nct_id) {
  nct_id <- toupper(trimws(nct_id))
  url    <- paste0(BASE_API_URL, "/", nct_id)

  resp <- tryCatch(
    GET(url, API_HEADERS, query = list(format = "json"), timeout(30)),
    error = function(e) { message("Request failed: ", e$message); NULL }
  )
  if (is.null(resp) || http_error(resp)) {
    message("Could not fetch ", nct_id, ": HTTP ", status_code(resp))
    return(NULL)
  }

  data <- fromJSON(content(resp, "text", encoding = "UTF-8"), simplifyVector = FALSE)
  .parse_study(data)
}

#' Search for studies with uploaded documents.
#'
#' @param condition    Character. Disease/condition (e.g. "lung cancer").
#' @param intervention Character. Drug/intervention (e.g. "pembrolizumab").
#' @param sponsor      Character. Sponsor name (e.g. "Pfizer").
#' @param doc_types    Character vector. Any of "protocol", "sap", "icf".
#' @param max_studies  Integer. Maximum results to return.
#' @return List of parsed study records.
search_studies_with_documents <- function(
    condition    = NULL,
    intervention = NULL,
    sponsor      = NULL,
    doc_types    = "protocol",
    max_studies  = 10
) {
  agg_codes  <- unlist(DOC_AGG_CODES[doc_types], use.names = FALSE)
  agg_filter <- paste0("docs:", paste(agg_codes, collapse = ","))

  query <- list(
    format     = "json",
    pageSize   = min(max_studies, 100),  # fetch exactly what we need in one call
    aggFilters = agg_filter
  )
  if (!is.null(condition))    query[["query.cond"]]  <- condition
  if (!is.null(intervention)) query[["query.intr"]]  <- intervention
  if (!is.null(sponsor))      query[["query.spons"]] <- sponsor

  resp <- tryCatch(
    GET(BASE_API_URL, API_HEADERS, query = query, timeout(30)),
    error = function(e) { message("Request failed: ", e$message); NULL }
  )
  if (is.null(resp) || http_error(resp)) {
    message("API error: HTTP ", status_code(resp))
    return(list())
  }

  data  <- fromJSON(content(resp, "text", encoding = "UTF-8"), simplifyVector = FALSE)
  batch <- data$studies %||% list()
  batch <- batch[seq_len(min(length(batch), max_studies))]

  # Phase 2: the search endpoint returns trimmed data (no largeDocumentModule).
  # Re-fetch each study individually to get the full record including doc metadata.
  message("  Fetching full records for ", length(batch), " study/studies ...")
  studies <- list()
  for (raw in batch) {
    nct_id <- raw$protocolSection$identificationModule$nctId %||% ""
    if (nchar(nct_id) == 0) next
    full <- get_study_by_nct_id(nct_id)
    if (!is.null(full)) studies <- c(studies, list(full))
    Sys.sleep(0.3)
  }
  studies
}

# ---------------------------------------------------------------------------
# Download functions
# ---------------------------------------------------------------------------

#' Download one document from the ClinicalTrials.gov CDN.
#'
#' URL pattern: https://cdn.clinicaltrials.gov/large-docs/{last2}/{NCTId}/{filename}
#'
#' @param nct_id   Character. NCT identifier.
#' @param filename Character. Document filename from the API.
#' @param dest_dir Character or path. Directory to save the file.
#' @return TRUE on success, FALSE on failure.
download_document <- function(nct_id, filename, dest_dir) {
  last2    <- substr(nct_id, nchar(nct_id) - 1, nchar(nct_id))
  url      <- paste(CDN_BASE_URL, last2, nct_id, filename, sep = "/")
  dest     <- file.path(dest_dir, filename)

  resp <- tryCatch(
    GET(url, API_HEADERS, timeout(120), write_disk(dest, overwrite = TRUE)),
    error = function(e) { message("    Download failed: ", e$message); NULL }
  )

  if (is.null(resp) || http_error(resp)) {
    message("    Failed to download ", filename, ": HTTP ", status_code(resp))
    return(FALSE)
  }

  size_kb <- round(file.info(dest)$size / 1024)
  message("    Saved: ", dest, "  (", size_kb, " KB)")
  TRUE
}

#' Download all matching documents for one study.
#'
#' @param study          Named list from get_study_by_nct_id() or search results.
#' @param output_dir     Character. Root output directory; a sub-folder per NCT ID is created.
#' @param doc_type_filter Character vector or NULL. Filter to "protocol", "sap", "icf".
#' @return Integer count of files downloaded.
download_study_documents <- function(study, output_dir = "./clinical_trial_docs",
                                     doc_type_filter = NULL) {
  nct_id   <- study$nct_id
  docs     <- study$docs

  if (length(docs) == 0) {
    message("  No documents available for ", nct_id)
    return(0L)
  }

  study_dir <- file.path(output_dir, nct_id)
  dir.create(study_dir, recursive = TRUE, showWarnings = FALSE)

  downloaded <- 0L
  for (doc in docs) {
    type_abbrev <- doc$typeAbbrev %||% ""
    filename    <- doc$filename   %||% ""
    label       <- doc$label      %||% DOC_TYPE_LABELS[type_abbrev] %||% type_abbrev
    doc_date    <- doc$date       %||% "N/A"

    if (!is.null(doc_type_filter) && !.doc_matches_filter(type_abbrev, doc_type_filter)) next
    if (nchar(filename) == 0) {
      message("  [", type_abbrev, "] ", label, " — no filename, skipping")
      next
    }

    message("  [", type_abbrev, "] ", label, "  (date: ", doc_date, ")  -> ", filename)
    if (download_document(nct_id, filename, study_dir)) downloaded <- downloaded + 1L
  }

  downloaded
}

# ---------------------------------------------------------------------------
# High-level convenience functions
# ---------------------------------------------------------------------------

#' Download documents for a specific NCT ID.
#'
#' @param nct_id         Character. E.g. "NCT04280705".
#' @param doc_types      Character vector or NULL (all). E.g. c("protocol", "sap").
#' @param output_dir     Character. Where to save files.
#' @return Invisibly, the number of files downloaded.
#'
#' @examples
#' download_study_docs("NCT04280705")
#' download_study_docs("NCT04280705", doc_types = "protocol", output_dir = "~/trials")
download_study_docs <- function(nct_id,
                                doc_types  = NULL,
                                output_dir = "./clinical_trial_docs") {
  nct_id <- toupper(trimws(nct_id))
  message("\nFetching metadata for ", nct_id, " ...")
  study <- get_study_by_nct_id(nct_id)

  if (is.null(study)) {
    message("Study not found or API error.")
    return(invisible(0L))
  }

  message("\n  Title:   ", study$title)
  message("  Sponsor: ", study$lead_sponsor)
  message("  Docs:    ", length(study$docs), " record(s) found")

  if (length(study$docs) == 0) {
    message("\nNo documents are available for this study.")
    return(invisible(0L))
  }

  message("\nAvailable documents:")
  for (doc in study$docs) {
    ta    <- doc$typeAbbrev %||% "?"
    label <- doc$label %||% DOC_TYPE_LABELS[ta] %||% ta
    fname <- doc$filename %||% "no filename"
    message("  [", ta, "] ", label, "  (", fname, ")")
  }

  message("\nDownloading to ", file.path(output_dir, nct_id), "/ ...")
  n <- download_study_documents(study, output_dir, doc_types)
  message("\n", n, " file(s) downloaded.")
  invisible(n)
}

#' Search ClinicalTrials.gov and optionally download matching documents.
#'
#' @param condition    Character or NULL.
#' @param intervention Character or NULL.
#' @param sponsor      Character or NULL.
#' @param doc_types    Character vector. Default "protocol".
#' @param max_studies  Integer. Default 5.
#' @param download     Logical. Download files after listing? Default FALSE.
#' @param output_dir   Character. Where to save files.
#' @return Invisibly, a list of matched study records.
#'
#' @examples
#' search_and_download(condition = "diabetes", doc_types = "protocol")
#' search_and_download(condition = "cancer", sponsor = "Pfizer",
#'                     doc_types = c("protocol", "sap"), max_studies = 10,
#'                     download = TRUE)
search_and_download <- function(
    condition    = NULL,
    intervention = NULL,
    sponsor      = NULL,
    doc_types    = "protocol",
    max_studies  = 5,
    download     = FALSE,
    output_dir   = "./clinical_trial_docs"
) {
  message("\nSearching ClinicalTrials.gov ...")
  if (!is.null(condition))    message("  Condition:    ", condition)
  if (!is.null(intervention)) message("  Intervention: ", intervention)
  if (!is.null(sponsor))      message("  Sponsor:      ", sponsor)
  message("  Doc types:    ", paste(doc_types, collapse = ", "))
  message("  Max studies:  ", max_studies)

  studies <- search_studies_with_documents(
    condition    = condition,
    intervention = intervention,
    sponsor      = sponsor,
    doc_types    = doc_types,
    max_studies  = max_studies
  )

  if (length(studies) == 0) {
    message("\nNo matching studies found.")
    return(invisible(list()))
  }

  message("\nFound ", length(studies), " study/studies with documents:\n")
  for (i in seq_along(studies)) {
    s <- studies[[i]]
    message(i, ". ", s$nct_id, ": ", s$title)
    message("   Sponsor: ", s$lead_sponsor)
    for (doc in s$docs) {
      ta    <- doc$typeAbbrev %||% "?"
      label <- doc$label %||% DOC_TYPE_LABELS[ta] %||% ta
      fname <- doc$filename %||% "no filename"
      message("   [", ta, "] ", label, "  (", fname, ")")
    }
    message()
  }

  if (download) {
    dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
    message("Downloading to ", output_dir, "/ ...")
    total <- 0L
    for (s in studies) {
      message("\n", s$nct_id, " - ", s$title)
      total <- total + download_study_documents(s, output_dir, doc_types)
    }
    message("\nTotal files downloaded: ", total)
  }

  invisible(studies)
}

# ---------------------------------------------------------------------------
# Run as a script (Rscript clinical_trials_downloader.R NCT04280705)
# ---------------------------------------------------------------------------
if (!interactive()) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) == 0) {
    cat("Usage:\n")
    cat("  Rscript clinical_trials_downloader.R <NCT_ID> [output_dir]\n\n")
    cat("Examples:\n")
    cat("  Rscript clinical_trials_downloader.R NCT04280705\n")
    cat("  Rscript clinical_trials_downloader.R NCT04280705 ~/my_trials\n")
    quit(status = 1)
  }
  nct_id     <- args[1]
  output_dir <- if (length(args) >= 2) args[2] else "./clinical_trial_docs"
  download_study_docs(nct_id, output_dir = output_dir)
}
