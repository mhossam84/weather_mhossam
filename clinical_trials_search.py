#!/usr/bin/env python3
"""Search ClinicalTrials.gov and export protocols and Investigator's Brochures."""

import argparse
import logging
import sys
from pathlib import Path

import ct_api
import ct_downloader
import ct_exporter


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Search ClinicalTrials.gov and export study documents (protocols, IBs).",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s -c "breast cancer" --max-studies 50
  %(prog)s -i pembrolizumab -c "lung cancer" -o ./lung_trials
  %(prog)s -s Pfizer --doc-types Prot,IB --max-studies 100
  %(prog)s -c diabetes --no-download
        """,
    )
    parser.add_argument("-c", "--condition", help="Disease or condition to search for")
    parser.add_argument("-i", "--intervention", help="Drug or intervention to search for")
    parser.add_argument("-s", "--sponsor", help="Lead sponsor or organization")
    parser.add_argument(
        "-o", "--output-dir",
        default="./clinical_trials_output",
        help="Output directory (default: ./clinical_trials_output)",
    )
    parser.add_argument(
        "--max-studies",
        type=int,
        default=100,
        help="Maximum number of studies to retrieve (default: 100)",
    )
    parser.add_argument(
        "--doc-types",
        default="Prot,IB",
        help="Comma-separated document types to download: Prot, IB, SAP, ICF (default: Prot,IB)",
    )
    parser.add_argument(
        "--no-download",
        action="store_true",
        help="Skip PDF downloads; export metadata only",
    )
    parser.add_argument(
        "--log-level",
        default="INFO",
        choices=["DEBUG", "INFO", "WARNING", "ERROR"],
        help="Logging verbosity (default: INFO)",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    logging.basicConfig(
        level=getattr(logging, args.log_level),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
        datefmt="%H:%M:%S",
        stream=sys.stderr,
    )
    logger = logging.getLogger("clinical_trials_search")

    if not any([args.condition, args.intervention, args.sponsor]):
        print(
            "Error: at least one of --condition, --intervention, or --sponsor is required.",
            file=sys.stderr,
        )
        sys.exit(1)

    doc_types: set[str] = {t.strip() for t in args.doc_types.split(",") if t.strip()}
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    # Print search summary
    print("\n=== ClinicalTrials.gov Search ===")
    if args.condition:
        print(f"  Condition:    {args.condition}")
    if args.intervention:
        print(f"  Intervention: {args.intervention}")
    if args.sponsor:
        print(f"  Sponsor:      {args.sponsor}")
    print(f"  Doc types:    {', '.join(sorted(doc_types))}")
    print(f"  Max studies:  {args.max_studies}")
    print(f"  Output dir:   {output_dir.resolve()}")
    print()

    session = ct_api.make_session()

    # Search
    print("Searching ClinicalTrials.gov...")
    try:
        raw_studies = ct_api.search_studies(
            session=session,
            condition=args.condition,
            intervention=args.intervention,
            sponsor=args.sponsor,
            max_studies=args.max_studies,
            doc_types=doc_types,
        )
    except Exception as exc:
        logger.error("Search failed: %s", exc)
        sys.exit(1)

    print(f"Retrieved {len(raw_studies)} studies from API.")

    # Extract metadata and filter to studies with matching documents
    records: list[dict] = []
    for study in raw_studies:
        record = ct_exporter.extract_metadata(study, doc_types)
        if record is not None:
            records.append(record)

    print(f"Found {len(records)} studies with matching documents ({', '.join(sorted(doc_types))}).")

    if not records:
        print("No studies with matching documents found. Try broadening your search.")
        # Write empty outputs for consistency
        ct_exporter.write_csv([], output_dir / "metadata.csv")
        ct_exporter.write_json([], output_dir / "metadata.json")
        sys.exit(0)

    # Write initial metadata
    csv_path = output_dir / "metadata.csv"
    json_path = output_dir / "metadata.json"
    ct_exporter.write_csv(records, csv_path)
    ct_exporter.write_json(records, json_path)

    # Download PDFs
    if not args.no_download:
        print("\nDownloading documents...")
        try:
            records = ct_downloader.download_documents(records, output_dir, session)
        except PermissionError as exc:
            logger.error("Cannot write to output directory: %s", exc)
            sys.exit(1)

        # Re-write metadata with final download status
        ct_exporter.write_csv(records, csv_path)
        ct_exporter.write_json(records, json_path)
    else:
        for r in records:
            r["download_status"] = "skipped"
        ct_exporter.write_csv(records, csv_path)
        ct_exporter.write_json(records, json_path)

    # Final summary
    status_counts: dict[str, int] = {}
    for r in records:
        s = r["download_status"]
        status_counts[s] = status_counts.get(s, 0) + 1

    print("\n=== Summary ===")
    print(f"  Studies with documents: {len(records)}")
    if not args.no_download:
        for status, count in sorted(status_counts.items()):
            print(f"  Downloads {status}: {count}")
    print(f"  Metadata CSV:  {csv_path.resolve()}")
    print(f"  Metadata JSON: {json_path.resolve()}")
    if not args.no_download:
        print(f"  Documents dir: {(output_dir / 'documents').resolve()}")
    print()


if __name__ == "__main__":
    main()
