#!/usr/bin/env python3
"""
ClinicalTrials.gov Document Downloader

Searches ClinicalTrials.gov for studies with uploaded documents (protocols,
Statistical Analysis Plans, Informed Consent Forms) and downloads them.

Usage:
  # Download docs for a specific study:
  python clinical_trials_downloader.py download NCT04280705

  # Search and list studies with protocols:
  python clinical_trials_downloader.py search --condition "diabetes" --doc-types protocol

  # Search and download:
  python clinical_trials_downloader.py search --condition "cancer" --doc-types protocol sap --download
"""

import os
import sys
import time
import argparse
import requests
from pathlib import Path
from typing import Optional, List, Dict

BASE_API_URL = "https://clinicaltrials.gov/api/v2/studies"
CDN_BASE_URL = "https://cdn.clinicaltrials.gov/large-docs"

HEADERS = {"User-Agent": "ClinicalTrialsDocDownloader/1.0 (research tool)"}

# Essie query expressions for filtering studies by document type
DOC_FILTERS = {
    "protocol": "AREA[LargeDocHasProtocol]true",
    "sap":      "AREA[LargeDocHasSAP]true",
    "icf":      "AREA[LargeDocHasICF]true",
}

DOC_TYPE_LABELS = {
    "Prot":         "Protocol",
    "SAP":          "Statistical Analysis Plan",
    "ICF":          "Informed Consent Form",
    "Prot_SAP":     "Protocol + SAP",
    "Prot_ICF":     "Protocol + ICF",
    "Prot_SAP_ICF": "Protocol + SAP + ICF",
}


def _parse_study(study: dict) -> dict:
    """Extract relevant fields from a raw API study record."""
    protocol = study.get("protocolSection", {})
    id_mod = protocol.get("identificationModule", {})
    sponsor_mod = protocol.get("sponsorCollaboratorsModule", {})
    docs_mod = protocol.get("largeDocumentModule", {})

    return {
        "nct_id":      id_mod.get("nctId", ""),
        "title":       id_mod.get("briefTitle", ""),
        "lead_sponsor": sponsor_mod.get("leadSponsor", {}).get("name", "Unknown"),
        "docs":        docs_mod.get("largeDocs", []),
    }


def search_studies_with_documents(
    condition: Optional[str] = None,
    intervention: Optional[str] = None,
    sponsor: Optional[str] = None,
    doc_types: Optional[List[str]] = None,
    max_studies: int = 10,
) -> List[Dict]:
    """
    Search ClinicalTrials.gov for studies that have uploaded documents.

    Args:
        condition:   Disease/condition (e.g. "lung cancer")
        intervention: Drug or intervention (e.g. "pembrolizumab")
        sponsor:     Sponsor name (e.g. "Pfizer")
        doc_types:   One or more of "protocol", "sap", "icf"
        max_studies: Cap on results returned

    Returns:
        List of parsed study dicts with 'nct_id', 'title', 'lead_sponsor', 'docs'.
    """
    if not doc_types:
        doc_types = ["protocol"]

    filter_exprs = [DOC_FILTERS[dt] for dt in doc_types if dt in DOC_FILTERS]
    advanced_filter = " OR ".join(filter_exprs)

    params: dict = {
        "format":           "json",
        "pageSize":         min(max_studies, 100),
        "filter.advanced":  advanced_filter,
    }

    if condition:
        params["query.cond"] = condition
    if intervention:
        params["query.intr"] = intervention
    if sponsor:
        params["query.spons"] = sponsor

    studies = []
    page_token: Optional[str] = None

    while len(studies) < max_studies:
        if page_token:
            params["pageToken"] = page_token

        try:
            resp = requests.get(BASE_API_URL, params=params, headers=HEADERS, timeout=30)
            resp.raise_for_status()
            data = resp.json()
        except requests.RequestException as exc:
            print(f"API error: {exc}")
            break

        for raw in data.get("studies", []):
            if len(studies) >= max_studies:
                break
            parsed = _parse_study(raw)
            if parsed["docs"]:
                studies.append(parsed)

        page_token = data.get("nextPageToken")
        if not page_token:
            break

        time.sleep(0.4)  # stay well under the ~50 req/min rate limit

    return studies


def get_study_by_nct_id(nct_id: str) -> Optional[Dict]:
    """Fetch document metadata for a single study by NCT ID."""
    url = f"{BASE_API_URL}/{nct_id}"
    try:
        resp = requests.get(url, params={"format": "json"}, headers=HEADERS, timeout=30)
        resp.raise_for_status()
        return _parse_study(resp.json())
    except requests.RequestException as exc:
        print(f"Failed to fetch {nct_id}: {exc}")
        return None


def _doc_matches_filter(type_abbrev: str, doc_type_filter: List[str]) -> bool:
    """Return True if the doc type matches any of the requested filter keys."""
    for dt in doc_type_filter:
        if dt == "protocol" and "Prot" in type_abbrev:
            return True
        if dt == "sap" and "SAP" in type_abbrev:
            return True
        if dt == "icf" and "ICF" in type_abbrev:
            return True
    return False


def download_document(nct_id: str, filename: str, dest_dir: Path) -> bool:
    """
    Download one document from the ClinicalTrials.gov CDN.

    URL pattern: https://cdn.clinicaltrials.gov/large-docs/{last2}/{NCTId}/{filename}
    """
    last2 = nct_id[-2:]
    url = f"{CDN_BASE_URL}/{last2}/{nct_id}/{filename}"
    dest = dest_dir / filename

    try:
        resp = requests.get(url, headers=HEADERS, timeout=120, stream=True)
        resp.raise_for_status()
        with open(dest, "wb") as fh:
            for chunk in resp.iter_content(chunk_size=8192):
                fh.write(chunk)
        size_kb = dest.stat().st_size // 1024
        print(f"    Saved: {dest}  ({size_kb} KB)")
        return True
    except requests.RequestException as exc:
        print(f"    Download failed for {filename}: {exc}")
        return False


def download_study_documents(
    study: Dict,
    output_dir: Path,
    doc_type_filter: Optional[List[str]] = None,
) -> int:
    """
    Download all matching documents for a study into output_dir/{nct_id}/.

    Returns the number of files successfully downloaded.
    """
    nct_id = study["nct_id"]
    docs = study.get("docs", [])

    if not docs:
        print(f"  No documents available for {nct_id}.")
        return 0

    study_dir = output_dir / nct_id
    study_dir.mkdir(parents=True, exist_ok=True)

    downloaded = 0
    for doc in docs:
        type_abbrev = doc.get("typeAbbrev", "")
        filename = doc.get("filename", "")
        label = doc.get("label", DOC_TYPE_LABELS.get(type_abbrev, type_abbrev))
        doc_date = doc.get("date", "N/A")

        if doc_type_filter and not _doc_matches_filter(type_abbrev, doc_type_filter):
            continue

        if not filename:
            print(f"  [{type_abbrev}] {label} — no filename, skipping")
            continue

        print(f"  [{type_abbrev}] {label}  (date: {doc_date})  -> {filename}")
        if download_document(nct_id, filename, study_dir):
            downloaded += 1

    return downloaded


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def cmd_download(args):
    nct_id = args.nct_id.strip().upper()
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    print(f"\nFetching metadata for {nct_id} ...")
    study = get_study_by_nct_id(nct_id)
    if not study:
        print("Study not found or API error.")
        sys.exit(1)

    print(f"\n  Title:   {study['title']}")
    print(f"  Sponsor: {study['lead_sponsor']}")
    print(f"  Docs:    {len(study['docs'])} record(s) found")

    if not study["docs"]:
        print("\nNo documents are available for this study.")
        sys.exit(0)

    print("\nAvailable documents:")
    for doc in study["docs"]:
        ta = doc.get("typeAbbrev", "?")
        label = doc.get("label", DOC_TYPE_LABELS.get(ta, ta))
        print(f"  [{ta}] {label}  ({doc.get('filename', 'no filename')})")

    print(f"\nDownloading to {output_dir / nct_id}/ ...")
    n = download_study_documents(study, output_dir, args.doc_types)
    print(f"\n{n} file(s) downloaded.")


def cmd_search(args):
    output_dir = Path(args.output_dir)

    print("\nSearching ClinicalTrials.gov ...")
    if args.condition:
        print(f"  Condition:    {args.condition}")
    if args.intervention:
        print(f"  Intervention: {args.intervention}")
    if args.sponsor:
        print(f"  Sponsor:      {args.sponsor}")
    print(f"  Doc types:    {', '.join(args.doc_types)}")
    print(f"  Max studies:  {args.max_studies}")

    studies = search_studies_with_documents(
        condition=args.condition,
        intervention=args.intervention,
        sponsor=args.sponsor,
        doc_types=args.doc_types,
        max_studies=args.max_studies,
    )

    if not studies:
        print("\nNo matching studies found.")
        return

    print(f"\nFound {len(studies)} study/studies with documents:\n")
    for i, study in enumerate(studies, 1):
        print(f"{i}. {study['nct_id']}: {study['title']}")
        print(f"   Sponsor: {study['lead_sponsor']}")
        for doc in study["docs"]:
            ta = doc.get("typeAbbrev", "?")
            label = doc.get("label", DOC_TYPE_LABELS.get(ta, ta))
            print(f"   [{ta}] {label}  ({doc.get('filename', 'no filename')})")
        print()

    if args.download:
        output_dir.mkdir(parents=True, exist_ok=True)
        print(f"Downloading to {output_dir}/ ...")
        total = 0
        for study in studies:
            print(f"\n{study['nct_id']} - {study['title']}")
            total += download_study_documents(study, output_dir, args.doc_types)
        print(f"\nTotal files downloaded: {total}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Download study documents from ClinicalTrials.gov",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    sub = parser.add_subparsers(dest="command", metavar="COMMAND")

    # --- download subcommand ---
    dl = sub.add_parser("download", help="Download documents for a specific NCT ID")
    dl.add_argument("nct_id", help="NCT identifier, e.g. NCT04280705")
    dl.add_argument(
        "--doc-types", nargs="+", choices=["protocol", "sap", "icf"], default=None,
        help="Limit downloads to these types (default: all available)",
    )
    dl.add_argument("--output-dir", default="./clinical_trial_docs",
                    help="Directory to save files (default: ./clinical_trial_docs)")

    # --- search subcommand ---
    sr = sub.add_parser("search", help="Search for studies that have uploaded documents")
    sr.add_argument("--condition",    help="Disease/condition (e.g. 'lung cancer')")
    sr.add_argument("--intervention", help="Drug/intervention (e.g. 'pembrolizumab')")
    sr.add_argument("--sponsor",      help="Sponsor name (e.g. 'Pfizer')")
    sr.add_argument(
        "--doc-types", nargs="+", choices=["protocol", "sap", "icf"],
        default=["protocol"],
        help="Document types to search for (default: protocol)",
    )
    sr.add_argument("--max-studies", type=int, default=5,
                    help="Max studies to return (default: 5)")
    sr.add_argument("--download", action="store_true",
                    help="Download the documents after listing them")
    sr.add_argument("--output-dir", default="./clinical_trial_docs",
                    help="Directory to save files when --download is used")

    return parser


def main():
    parser = build_parser()
    args = parser.parse_args()

    if args.command == "download":
        cmd_download(args)
    elif args.command == "search":
        cmd_search(args)
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
