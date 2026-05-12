import csv
import json
import logging
from pathlib import Path

from ct_api import build_pdf_url

logger = logging.getLogger(__name__)

METADATA_FIELDS = [
    "nct_id",
    "brief_title",
    "official_title",
    "status",
    "phases",
    "sponsor",
    "conditions",
    "interventions",
    "start_date",
    "primary_completion_date",
    "doc_types_available",
    "doc_filenames",
    "doc_urls",
    "download_status",
    "download_paths",
]


def _doc_matches(type_abbrev: str, doc_types_filter: set[str]) -> bool:
    # Match compound typeAbbrevs like "Prot_SAP" if any requested type is a substring
    return any(t in type_abbrev for t in doc_types_filter)


def extract_metadata(study: dict, doc_types_filter: set[str]) -> dict | None:
    proto = study.get("protocolSection", {})
    ident = proto.get("identificationModule", {})
    status = proto.get("statusModule", {})
    design = proto.get("designModule", {})
    spons = proto.get("sponsorCollaboratorsModule", {})
    conds = proto.get("conditionsModule", {})
    intrvs = proto.get("armsInterventionsModule", {})
    all_docs = (
        study.get("documentSection", {})
        .get("largeDocumentModule", {})
        .get("largeDocs", [])
    )

    nct_id = ident.get("nctId", "")
    filtered_docs = [d for d in all_docs if _doc_matches(d.get("typeAbbrev", ""), doc_types_filter)]

    if not filtered_docs:
        return None

    filenames = [d.get("filename", "") for d in filtered_docs]
    type_abbrevs = [d.get("typeAbbrev", "") for d in filtered_docs]
    urls = [build_pdf_url(nct_id, fn) for fn in filenames]

    brief = ident.get("briefTitle", "")
    official = ident.get("officialTitle", "") or brief

    return {
        "nct_id": nct_id,
        "brief_title": brief,
        "official_title": official,
        "status": status.get("overallStatus", ""),
        "phases": "|".join(design.get("phases", [])),
        "sponsor": spons.get("leadSponsor", {}).get("name", ""),
        "conditions": "|".join(conds.get("conditions", [])),
        "interventions": "|".join(
            i.get("name", "") for i in intrvs.get("interventions", [])
        ),
        "start_date": status.get("startDateStruct", {}).get("date", ""),
        "primary_completion_date": status.get("primaryCompletionDateStruct", {}).get("date", ""),
        "doc_types_available": "|".join(type_abbrevs),
        "doc_filenames": "|".join(filenames),
        "doc_urls": "|".join(urls),
        "download_status": "pending",
        "download_paths": "",
    }


def write_csv(records: list[dict], output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w", newline="", encoding="utf-8-sig") as f:
        writer = csv.DictWriter(f, fieldnames=METADATA_FIELDS)
        writer.writeheader()
        writer.writerows(records)
    logger.info("Wrote CSV: %s", output_path)


def write_json(records: list[dict], output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(records, f, indent=2, ensure_ascii=False)
    logger.info("Wrote JSON: %s", output_path)
