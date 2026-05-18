#!/usr/bin/env Rscript
# clinical_trials_analyzer.R
#
# Classifies ClinicalTrials.gov studies by:
#   - Phase (1 / 2 / 3 / 4 / Other)
#   - Therapeutic area (Oncology, CV, CNS, etc.)
#   - Study type (DDI, Hepatic Impairment, BE, Pivotal, etc.)
#
# Dependencies: httr, jsonlite, (optional) writexl
#   install.packages(c("httr", "jsonlite", "writexl"))
#
# Usage:
#   source("clinical_trials_analyzer.R")
#   df <- analyze_sponsor("Pfizer", doc_types = c("protocol","sap","icf"))
#   print_summary(df)
#   export_results(df, "pfizer_study_classification.csv")

source("clinical_trials_downloader.R")  # reuses get_study_by_nct_id & search helpers

# ---------------------------------------------------------------------------
# Classification dictionaries
# ---------------------------------------------------------------------------

TA_KEYWORDS <- list(
  "Oncology"                  = c("cancer","carcinoma","tumor","tumour","neoplasm",
                                   "leukemia","leukaemia","lymphoma","melanoma","sarcoma",
                                   "myeloma","glioma","glioblastoma","adenocarcinoma",
                                   "malignant","metastatic","oncology","blastoma"),
  "Cardiovascular"            = c("heart failure","hypertension","atrial fibrillation",
                                   "coronary","myocardial","stroke","thrombosis",
                                   "thromboembolism","arrhythmia","angina","cardiovascular",
                                   "cardiac","ventricular","aortic","peripheral artery"),
  "CNS / Neurology"           = c("alzheimer","parkinson","epilepsy","seizure",
                                   "schizophrenia","depression","anxiety","bipolar",
                                   "multiple sclerosis","migraine","neuropathy","dementia",
                                   "neurological","psychiatric","autism","adhd",
                                   "amyotrophic lateral","huntington"),
  "Infectious Disease"        = c("hiv","aids","hepatitis","covid","sars-cov","bacterial",
                                   "viral","infection","pneumonia","tuberculosis","malaria",
                                   "influenza","fungal","sepsis","antibiotic","antiviral"),
  "Immunology / Rheumatology" = c("rheumatoid arthritis","lupus","psoriasis","crohn",
                                   "ulcerative colitis","inflammatory bowel","autoimmune",
                                   "immunology","atopic dermatitis","spondylitis",
                                   "juvenile arthritis","vasculitis","myositis"),
  "Respiratory"               = c("asthma","copd","pulmonary","respiratory",
                                   "cystic fibrosis","idiopathic pulmonary fibrosis",
                                   "lung disease","bronchitis","bronchiectasis"),
  "Endocrinology / Metabolic" = c("diabetes","obesity","thyroid","metabolic syndrome",
                                   "dyslipidemia","hypercholesterolemia","nash",
                                   "non-alcoholic steatohepatitis","insulin","hypoglycemia",
                                   "fatty liver","steatosis"),
  "Dermatology"               = c("dermatitis","eczema","acne","urticaria","alopecia",
                                   "vitiligo","dermatology","psoriatic skin","rosacea"),
  "Gastroenterology"          = c("gastroenterology","liver disease","cirrhosis","ibs",
                                   "irritable bowel","gastric","intestinal","colitis",
                                   "gastrointestinal","constipation","diarrhea","nausea"),
  "Hematology"                = c("anemia","anaemia","hemophilia","sickle cell",
                                   "thrombocytopenia","hematology","haematology",
                                   "blood disorder","coagulation","myelodysplastic"),
  "Ophthalmology"             = c("ophthalm","retinal","macular","glaucoma","eye disease",
                                   "vision","diabetic retinopathy"),
  "Rare Disease"              = c("rare disease","orphan drug","rare disorder",
                                   "ultra-rare","rare condition")
)

STUDY_TYPE_PATTERNS <- list(
  "First-in-Human (FIH)"       = c("first.in.human","first human","first-in-man","fih",
                                    "first-in-healthy","first dose in human"),
  "Single Ascending Dose (SAD)"= c("single ascending dose","single-ascending-dose","\\bsad\\b",
                                    "single dose escalation","single-dose escalation"),
  "Multiple Ascending Dose (MAD)"=c("multiple ascending dose","multiple-ascending-dose",
                                    "\\bmad\\b","multiple dose escalation"),
  "Drug-Drug Interaction (DDI)"= c("drug.drug interaction","\\bddi\\b","drug interaction",
                                    "pharmacokinetic interaction","cyp.*inhibit","cyp.*induc",
                                    "p-glycoprotein","transporter.*inhibit","inhibit.*cyp"),
  "Hepatic Impairment"         = c("hepatic impairment","liver impairment",
                                    "hepatic dysfunction","child.pugh","hepatic failure",
                                    "liver failure"),
  "Renal Impairment"           = c("renal impairment","kidney impairment","renal dysfunction",
                                    "renal failure","\\begfr\\b","creatinine clearance",
                                    "chronic kidney"),
  "Food Effect"                = c("food effect","\\bfed\\b.*\\bfast","\\bfast.*\\bfed\\b",
                                    "high.fat meal","food interaction","fed state","fasted state",
                                    "effect of food"),
  "Bioequivalence / BA"        = c("bioequivalence","\\bbe study\\b","bioavailability",
                                    "\\bba/be\\b","relative bioavailability","absolute bioavailability",
                                    "formulation.*comparison","reference.*test.*formulation"),
  "Mass Balance / ADME"        = c("mass balance","radiolabeled","\\badme\\b","\\[14c\\]",
                                    "carbon.14","radioactive","absorption.*distribution.*metabolism",
                                    "excretion study"),
  "QTc / Cardiac Safety"       = c("\\bqtc\\b","qt.*prolongation","cardiac.*repolarization",
                                    "thorough qt","tqt"),
  "Dose Finding / Ranging"     = c("dose.find","dose.rang","dose.response",
                                    "dose.*optimal","optimal dose","dose.*selection"),
  "Dose Escalation"            = c("dose escalat","\\bmtd\\b","maximum tolerated dose",
                                    "dose.*expansion","escalating dose"),
  "Pivotal / Confirmatory"     = c("pivotal","confirmatory","registration","phase 3.*efficacy",
                                    "phase iii.*efficacy","approval.*trial","\\bphase 3\\b.*\\bprimary"),
  "Proof of Concept (PoC)"     = c("proof.of.concept","\\bpoc\\b","proof.of.principle",
                                    "exploratory.*efficacy","early.*efficacy","signal.*finding"),
  "Open-Label Extension (OLE)" = c("open.label extension","\\bole\\b",
                                    "long.term extension","extension study","extension phase"),
  "Long-Term Safety"           = c("long.term safety","safety extension","safety.*follow.up",
                                    "chronic.*safety","2.year.*safety","3.year.*safety"),
  "Pediatric"                  = c("pediatric","paediatric","child.*patient","adolescent",
                                    "neonatal","juvenile","age.*\\d+.*year.*child"),
  "Geriatric / Elderly"        = c("geriatric","elderly","older adult","aged.*\\d{2,}",
                                    "\\belderly\\b"),
  "Special Population"         = c("special population","intrinsic factor","extrinsic factor",
                                    "organ impairment"),
  "Phase 2 Efficacy"           = c("phase 2.*efficacy","phase ii.*efficacy",
                                    "\\bph2\\b.*efficacy","phase 2.*dose.*range"),
  "Phase 3 Efficacy"           = c("phase 3.*efficacy","phase iii.*efficacy",
                                    "\\bph3\\b.*efficacy","phase 3.*superiority",
                                    "phase 3.*non-inferiority")
)

# ---------------------------------------------------------------------------
# Metadata fetch (extended fields beyond the downloader's .parse_study)
# ---------------------------------------------------------------------------

get_study_metadata <- function(nct_id) {
  nct_id <- toupper(trimws(nct_id))
  url    <- paste0(BASE_API_URL, "/", nct_id)

  resp <- tryCatch(
    GET(url, API_HEADERS, query = list(format = "json"), timeout(30)),
    error = function(e) NULL
  )
  if (is.null(resp) || http_error(resp)) return(NULL)

  d <- fromJSON(content(resp, "text", encoding = "UTF-8"), simplifyVector = FALSE)
  proto  <- d$protocolSection %||% list()
  id_mod <- proto$identificationModule %||% list()
  st_mod <- proto$statusModule         %||% list()
  sp_mod <- proto$sponsorCollaboratorsModule %||% list()
  dc_mod <- proto$descriptionModule    %||% list()
  cn_mod <- proto$conditionsModule     %||% list()
  de_mod <- proto$designModule         %||% list()
  el_mod <- proto$eligibilityModule    %||% list()
  ai_mod <- proto$armsInterventionsModule %||% list()
  doc_mod <- d$documentSection$largeDocumentModule %||% list()
  mesh   <- d$derivedSection$conditionBrowseModule$meshes %||% list()

  # Flatten phases list to a string
  phases <- unlist(de_mod$phases %||% list())
  phases <- if (length(phases) == 0) "N/A" else paste(phases, collapse = " / ")

  # Collect condition text + mesh terms for TA classification
  conditions  <- unlist(cn_mod$conditions %||% list())
  keywords    <- unlist(cn_mod$keywords   %||% list())
  mesh_terms  <- sapply(mesh, function(m) m$term %||% "")
  cond_text   <- tolower(paste(c(conditions, keywords, mesh_terms), collapse = " "))

  # Collect text corpus for study-type classification
  title       <- tolower(paste(id_mod$briefTitle %||% "",
                               id_mod$officialTitle %||% ""))
  summary     <- tolower(dc_mod$briefSummary %||% "")
  detail      <- tolower(dc_mod$detailedDescription %||% "")
  text_corpus <- paste(title, summary, detail)

  # Healthy volunteers
  healthy_vol <- el_mod$healthyVolunteers %||% ""

  # Intervention names
  interventions <- sapply(ai_mod$interventions %||% list(),
                          function(x) x$name %||% "")

  # Available document types
  doc_types_avail <- sapply(doc_mod$largeDocs %||% list(),
                            function(x) x$typeAbbrev %||% "")

  list(
    nct_id         = id_mod$nctId        %||% nct_id,
    brief_title    = id_mod$briefTitle   %||% "",
    official_title = id_mod$officialTitle %||% "",
    lead_sponsor   = sp_mod$leadSponsor$name %||% "",
    status         = st_mod$overallStatus %||% "",
    start_date     = st_mod$startDateStruct$date %||% "",
    study_type_raw = de_mod$studyType    %||% "",
    phases         = phases,
    phases_raw     = phases,
    primary_purpose= de_mod$designInfo$primaryPurpose %||% "",
    allocation     = de_mod$designInfo$allocation %||% "",
    masking        = de_mod$designInfo$maskingInfo$masking %||% "",
    intervention_model = de_mod$designInfo$interventionModel %||% "",
    healthy_volunteers = healthy_vol,
    conditions     = paste(conditions, collapse = "; "),
    interventions  = paste(interventions, collapse = "; "),
    doc_types      = paste(doc_types_avail, collapse = ", "),
    cond_text      = cond_text,
    text_corpus    = text_corpus
  )
}

# ---------------------------------------------------------------------------
# Classifiers
# ---------------------------------------------------------------------------

classify_phase <- function(phases_raw) {
  p <- toupper(phases_raw)
  if (grepl("PHASE4|PHASE_4",  p)) return("Phase 4")
  if (grepl("PHASE3|PHASE_3",  p)) return("Phase 3")
  if (grepl("PHASE2|PHASE_2",  p)) return("Phase 2")
  if (grepl("PHASE1|PHASE_1|EARLY_PHASE", p)) return("Phase 1")
  if (p == "N/A" || nchar(trimws(p)) == 0)    return("N/A")
  "Other"
}

classify_therapeutic_area <- function(meta) {
  # Observational / registry studies with no real condition → Other
  if (meta$study_type_raw == "OBSERVATIONAL" && nchar(meta$cond_text) < 10)
    return("Observational / Other")

  # Healthy volunteer-only studies
  if (grepl("yes", tolower(meta$healthy_volunteers)) &&
      !grepl("patient|subject with|diagnosed", meta$text_corpus))
    return("Healthy Volunteer")

  txt <- paste(meta$cond_text, tolower(meta$conditions))

  for (ta in names(TA_KEYWORDS)) {
    pats <- TA_KEYWORDS[[ta]]
    if (any(sapply(pats, function(p) grepl(p, txt, ignore.case = TRUE, perl = TRUE))))
      return(ta)
  }
  "Other"
}

classify_study_types <- function(meta) {
  # Observational handled separately
  if (meta$study_type_raw == "OBSERVATIONAL")
    return("Observational / Registry")

  corpus <- meta$text_corpus
  matched <- character(0)

  for (stype in names(STUDY_TYPE_PATTERNS)) {
    pats <- STUDY_TYPE_PATTERNS[[stype]]
    if (any(sapply(pats, function(p) grepl(p, corpus, ignore.case = TRUE, perl = TRUE))))
      matched <- c(matched, stype)
  }

  if (length(matched) == 0) return("Other")
  paste(matched, collapse = " | ")
}

# ---------------------------------------------------------------------------
# Main analysis function
# ---------------------------------------------------------------------------

#' Classify a vector of NCT IDs and return a data frame.
#'
#' @param nct_ids  Character vector of NCT IDs.
#' @return data.frame with one row per study.
classify_studies <- function(nct_ids) {
  n <- length(nct_ids)
  message("Classifying ", n, " studies ...")
  rows <- vector("list", n)

  for (i in seq_along(nct_ids)) {
    if (i %% 10 == 0 || i == n)
      message("  ", i, "/", n, " ...")

    meta <- get_study_metadata(nct_ids[[i]])
    if (is.null(meta)) {
      rows[[i]] <- data.frame(
        nct_id = nct_ids[[i]], brief_title = NA, lead_sponsor = NA,
        status = NA, start_date = NA, phases = NA, phase_group = NA,
        therapeutic_area = NA, study_types = NA,
        healthy_volunteers = NA, conditions = NA,
        interventions = NA, doc_types_available = NA,
        stringsAsFactors = FALSE
      )
      next
    }

    rows[[i]] <- data.frame(
      nct_id              = meta$nct_id,
      brief_title         = meta$brief_title,
      lead_sponsor        = meta$lead_sponsor,
      status              = meta$status,
      start_date          = meta$start_date,
      phases              = meta$phases,
      phase_group         = classify_phase(meta$phases_raw),
      therapeutic_area    = classify_therapeutic_area(meta),
      study_types         = classify_study_types(meta),
      healthy_volunteers  = meta$healthy_volunteers,
      conditions          = meta$conditions,
      interventions       = meta$interventions,
      doc_types_available = meta$doc_types,
      stringsAsFactors    = FALSE
    )
    Sys.sleep(0.4)
  }

  do.call(rbind, rows)
}

#' Search for a sponsor's studies with documents and classify them.
#'
#' @param sponsor    Character. Sponsor name, e.g. "Pfizer".
#' @param doc_types  Character vector. "protocol", "sap", "icf".
#' @param max_studies Integer or Inf.
#' @return data.frame of classified studies.
#'
#' @examples
#' df <- analyze_sponsor("Pfizer")
#' print_summary(df)
#' export_results(df, "pfizer_analysis.csv")
analyze_sponsor <- function(sponsor,
                            doc_types    = c("protocol", "sap", "icf"),
                            max_studies  = Inf) {
  message("\nSearching for ", sponsor, " studies with documents ...")
  studies <- search_studies_with_documents(
    sponsor     = sponsor,
    doc_types   = doc_types,
    max_studies = max_studies
  )
  if (length(studies) == 0) {
    message("No studies found.")
    return(invisible(NULL))
  }
  nct_ids <- sapply(studies, `[[`, "nct_id")
  classify_studies(nct_ids)
}

# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------

.tbl <- function(x, title) {
  cat("\n", title, "\n", strrep("-", nchar(title)), "\n", sep = "")
  t <- sort(table(x), decreasing = TRUE)
  for (nm in names(t)) cat(sprintf("  %-45s %d\n", nm, t[[nm]]))
}

#' Print a summary of the classification data frame.
print_summary <- function(df) {
  cat("\n========================================\n")
  cat(" CLINICAL TRIAL CLASSIFICATION SUMMARY\n")
  cat("========================================\n")
  cat("Total studies analysed:", nrow(df), "\n")

  .tbl(df$phase_group,      "Studies by Phase")
  .tbl(df$therapeutic_area, "Studies by Therapeutic Area")

  # Study types — each cell can have multiple pipe-separated values; expand them
  all_types <- unlist(strsplit(df$study_types[!is.na(df$study_types)], " \\| "))
  .tbl(all_types, "Studies by Study Type  (multi-label)")

  .tbl(df$status,           "Studies by Status")
  cat("\n")
  invisible(df)
}

#' Export classification results to CSV (and optionally Excel).
#'
#' @param df        data.frame from classify_studies() or analyze_sponsor().
#' @param file      Output file path (CSV). An .xlsx is also written if writexl is installed.
export_results <- function(df, file = "study_classification.csv") {
  # Drop internal text columns before export
  out <- df[, !names(df) %in% c("cond_text", "text_corpus"), drop = FALSE]
  write.csv(out, file, row.names = FALSE)
  message("CSV saved: ", normalizePath(file))

  xlsx <- sub("\\.csv$", ".xlsx", file)
  if (requireNamespace("writexl", quietly = TRUE)) {
    writexl::write_xlsx(out, xlsx)
    message("Excel saved: ", normalizePath(xlsx))
  }
  invisible(out)
}

# ---------------------------------------------------------------------------
# Folder organisation by phase and study type
# ---------------------------------------------------------------------------

PHASE_FOLDERS <- c(
  "Phase 1" = "Phase_1",
  "Phase 2" = "Phase_2",
  "Phase 3" = "Phase_3",
  "Phase 4" = "Phase_4",
  "Other"   = "Other_Phase",
  "N/A"     = "Phase_NA"
)

STUDY_TYPE_FOLDERS <- c(
  "First-in-Human (FIH)"          = "FIH",
  "Single Ascending Dose (SAD)"   = "SAD",
  "Multiple Ascending Dose (MAD)" = "MAD",
  "Drug-Drug Interaction (DDI)"   = "DDI",
  "Hepatic Impairment"            = "Hepatic_Impairment",
  "Renal Impairment"              = "Renal_Impairment",
  "Food Effect"                   = "Food_Effect",
  "Bioequivalence / BA"           = "Bioequivalence_BA",
  "Mass Balance / ADME"           = "Mass_Balance_ADME",
  "QTc / Cardiac Safety"          = "QTc_Cardiac_Safety",
  "Dose Finding / Ranging"        = "Dose_Finding_Ranging",
  "Dose Escalation"               = "Dose_Escalation",
  "Pivotal / Confirmatory"        = "Pivotal_Confirmatory",
  "Proof of Concept (PoC)"        = "Proof_of_Concept",
  "Open-Label Extension (OLE)"    = "Open_Label_Extension",
  "Long-Term Safety"              = "Long_Term_Safety",
  "Pediatric"                     = "Pediatric",
  "Geriatric / Elderly"           = "Geriatric_Elderly",
  "Special Population"            = "Special_Population",
  "Phase 2 Efficacy"              = "Phase_2_Efficacy",
  "Phase 3 Efficacy"              = "Phase_3_Efficacy",
  "Observational / Registry"      = "Observational_Registry",
  "Other"                         = "Other_Study_Type"
)

.phase_folder <- function(phase_group) {
  PHASE_FOLDERS[[phase_group %||% "N/A"]] %||% "Phase_NA"
}

# Return the folder name for the primary (first) matched study type
.primary_type_folder <- function(study_types_str) {
  if (is.na(study_types_str) || !nchar(trimws(study_types_str)))
    return(STUDY_TYPE_FOLDERS[["Other"]])
  primary <- trimws(strsplit(study_types_str, " \\| ")[[1]][1])
  STUDY_TYPE_FOLDERS[[primary]] %||% gsub("[^A-Za-z0-9]", "_", primary)
}

#' Preview the folder structure that organize_by_classification() would create.
#'
#' @param df  data.frame from classify_studies() or analyze_sponsor().
preview_organization <- function(df) {
  tbl <- table(
    Phase      = sapply(df$phase_group,  .phase_folder),
    Study_Type = sapply(df$study_types, .primary_type_folder)
  )
  cat("\nFolder structure preview (Phase / Study Type — study count):\n")
  cat(strrep("-", 60), "\n")
  for (ph in rownames(tbl)) {
    ph_total <- sum(tbl[ph, ])
    cat(sprintf("  %s/  (%d studies)\n", ph, ph_total))
    for (st in colnames(tbl)) {
      if (tbl[ph, st] > 0)
        cat(sprintf("    %-40s %d\n", paste0(st, "/"), tbl[ph, st]))
    }
  }
  invisible(tbl)
}

#' Copy downloaded PDFs into Phase/StudyType/NCT_ID folder hierarchy.
#'
#' @param df         data.frame from classify_studies() or analyze_sponsor().
#' @param source_dir Directory where PDFs were saved by search_and_download()
#'                   (contains one sub-folder per NCT ID).
#' @param output_dir Root of the organised output tree.
#' @param copy       TRUE = copy files (safe); FALSE = move files (faster).
#' @return Invisibly, a data.frame log of every file operation.
#'
#' @examples
#' df <- analyze_sponsor("Pfizer")
#' organize_by_classification(df, source_dir = "./pfizer_docs",
#'                                output_dir  = "./pfizer_organized")
organize_by_classification <- function(df,
                                       source_dir,
                                       output_dir = "./organized_docs",
                                       copy       = TRUE) {
  source_dir <- normalizePath(source_dir, mustWork = FALSE)
  output_dir <- normalizePath(output_dir, mustWork = FALSE)
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

  log_rows <- list()
  n_files  <- 0L
  n_skip   <- 0L

  for (i in seq_len(nrow(df))) {
    row    <- df[i, ]
    nct_id <- row$nct_id
    if (is.na(nct_id) || !nchar(nct_id)) next

    src_dir <- file.path(source_dir, nct_id)
    if (!dir.exists(src_dir)) {
      n_skip <- n_skip + 1L
      log_rows[[length(log_rows) + 1]] <- data.frame(
        nct_id = nct_id, file = NA, phase_folder = NA,
        type_folder = NA, status = "no_source_folder", stringsAsFactors = FALSE
      )
      next
    }

    ph_folder  <- .phase_folder(row$phase_group)
    typ_folder <- .primary_type_folder(row$study_types)
    dst_dir    <- file.path(output_dir, ph_folder, typ_folder, nct_id)
    dir.create(dst_dir, recursive = TRUE, showWarnings = FALSE)

    files <- list.files(src_dir, full.names = TRUE, recursive = FALSE)
    for (f in files) {
      dst_file <- file.path(dst_dir, basename(f))
      ok <- if (copy) file.copy(f, dst_file, overwrite = TRUE)
            else      file.rename(f, dst_file)
      n_files <- n_files + 1L
      log_rows[[length(log_rows) + 1]] <- data.frame(
        nct_id      = nct_id,
        file        = basename(f),
        phase_folder = ph_folder,
        type_folder  = typ_folder,
        status       = if (ok) "ok" else "failed",
        stringsAsFactors = FALSE
      )
    }
  }

  # Write index with classification + destination path
  index <- merge(
    df[, c("nct_id","brief_title","lead_sponsor","phase_group",
           "therapeutic_area","study_types","status","conditions",
           "doc_types_available")],
    data.frame(
      nct_id       = sapply(df$nct_id, identity),
      phase_folder = sapply(df$phase_group,  .phase_folder),
      type_folder  = sapply(df$study_types, .primary_type_folder),
      stringsAsFactors = FALSE
    ),
    by = "nct_id", all.x = TRUE
  )
  index$destination_path <- file.path(
    output_dir, index$phase_folder, index$type_folder, index$nct_id
  )
  index_file <- file.path(output_dir, "study_index.csv")
  write.csv(index, index_file, row.names = FALSE)

  op <- if (copy) "copied" else "moved"
  message("\nOrganisation complete.")
  message("  Files ", op, ":          ", n_files)
  message("  Studies skipped        ", n_skip, "  (not yet downloaded)")
  message("  Output directory:      ", output_dir)
  message("  Index CSV:             ", index_file)

  invisible(do.call(rbind, log_rows))
}
