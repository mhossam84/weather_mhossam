"""Streamlit web UI for ClinicalTrials.gov document search and export."""

import csv
import io
import json
import logging
import os
import tempfile
import zipfile
from pathlib import Path

import pandas as pd
import streamlit as st

import ct_api
import ct_downloader
import ct_exporter
from ct_query_parser import parse_search_query

logging.basicConfig(level=logging.WARNING)

st.set_page_config(
    page_title="ClinicalTrials.gov Search",
    page_icon="🔬",
    layout="wide",
)

# ── helpers ──────────────────────────────────────────────────────────────────

def _to_csv_bytes(records: list[dict]) -> bytes:
    buf = io.StringIO()
    writer = csv.DictWriter(buf, fieldnames=ct_exporter.METADATA_FIELDS)
    writer.writeheader()
    writer.writerows(records)
    return buf.getvalue().encode("utf-8-sig")


def _to_json_bytes(records: list[dict]) -> bytes:
    return json.dumps(records, indent=2, ensure_ascii=False).encode("utf-8")


def _build_zip(records: list[dict], tmp_dir: str) -> bytes:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        for record in records:
            nct_id = record["nct_id"]
            for local_path in (p for p in record["download_paths"].split("|") if p):
                p = Path(local_path)
                if p.exists():
                    zf.write(str(p), f"{nct_id}/{p.name}")
    buf.seek(0)
    return buf.getvalue()


def _status_emoji(status: str) -> str:
    return {"success": "✅", "exists": "✅", "partial": "⚠️", "failed": "❌",
            "unavailable": "🚫", "skipped": "—", "pending": "⏳"}.get(status, status)


# ── session state init ────────────────────────────────────────────────────────

for _k, _v in {
    "records": None,
    "extracted_params": None,
    "csv_bytes": None,
    "json_bytes": None,
    "zip_bytes": None,
    "api_key_ok": None,
}.items():
    if _k not in st.session_state:
        st.session_state[_k] = _v

# ── page header ───────────────────────────────────────────────────────────────

st.title("🔬 ClinicalTrials.gov Document Search")
st.markdown(
    "Describe what you're looking for in plain language. "
    "The tool will extract search parameters, query ClinicalTrials.gov, "
    "and download any publicly available study documents (protocols, IBs)."
)

# ── API key check ─────────────────────────────────────────────────────────────

if not os.environ.get("ANTHROPIC_API_KEY"):
    st.error(
        "**ANTHROPIC_API_KEY is not set.**  \n"
        "Set the environment variable before starting the app:  \n"
        "```\nexport ANTHROPIC_API_KEY=sk-ant-...\nstreamlit run app.py\n```"
    )
    st.stop()

# ── search form ───────────────────────────────────────────────────────────────

with st.form("search_form"):
    query = st.text_area(
        "Describe what you're looking for:",
        placeholder=(
            "e.g. 'Find pembrolizumab trials for lung cancer from Merck'\n"
            "or 'Protocols for CRISPR gene therapy studies in sickle cell disease'"
        ),
        height=110,
    )

    col1, col2, col3 = st.columns(3)
    with col1:
        max_studies = st.number_input(
            "Max studies to retrieve", min_value=1, max_value=1000, value=50
        )
    with col2:
        doc_types_selected = st.multiselect(
            "Document types to download",
            options=["Prot", "IB", "SAP", "ICF"],
            default=["Prot", "IB"],
            help=(
                "Prot = Protocol  |  IB = Investigator's Brochure  |  "
                "SAP = Statistical Analysis Plan  |  ICF = Informed Consent Form"
            ),
        )
    with col3:
        download_pdfs = st.checkbox("Download PDFs", value=True)

    submitted = st.form_submit_button("🔍 Search", type="primary")

# ── handle form submission ────────────────────────────────────────────────────

if submitted:
    if not query.strip():
        st.warning("Please enter a search query.")
        st.stop()
    if not doc_types_selected:
        st.warning("Please select at least one document type.")
        st.stop()

    doc_types = set(doc_types_selected)

    # Reset previous results
    st.session_state.records = None
    st.session_state.csv_bytes = None
    st.session_state.json_bytes = None
    st.session_state.zip_bytes = None
    st.session_state.extracted_params = None

    # ── step 1: NLP extraction ────────────────────────────────────────────────
    with st.spinner("Analyzing your query with Claude…"):
        try:
            params = parse_search_query(query)
        except Exception as exc:
            st.error(f"Query analysis failed: {exc}")
            st.stop()

    st.session_state.extracted_params = params

    if not any(params.values()):
        st.warning(
            "Could not extract any search terms. "
            "Try being more specific (e.g. mention a drug name, disease, or sponsor)."
        )
        st.stop()

    # ── step 2: API search ────────────────────────────────────────────────────
    with st.spinner("Searching ClinicalTrials.gov…"):
        try:
            session = ct_api.make_session()
            raw_studies = ct_api.search_studies(
                session=session,
                condition=params.get("condition"),
                intervention=params.get("intervention"),
                sponsor=params.get("sponsor"),
                max_studies=int(max_studies),
                doc_types=doc_types,
            )
        except Exception as exc:
            st.error(f"Search failed: {exc}")
            st.stop()

    # ── step 3: extract metadata ──────────────────────────────────────────────
    records: list[dict] = [
        r
        for study in raw_studies
        if (r := ct_exporter.extract_metadata(study, doc_types)) is not None
    ]

    if not records:
        st.info(
            f"Found {len(raw_studies)} studies but none had "
            f"**{', '.join(sorted(doc_types))}** documents available. "
            "Try different search terms or document types."
        )
        st.stop()

    # ── step 4: download PDFs ─────────────────────────────────────────────────
    if download_pdfs:
        total_docs = sum(len(r["doc_filenames"].split("|")) for r in records if r["doc_filenames"])
        with st.spinner(f"Downloading {total_docs} documents for {len(records)} studies…"):
            try:
                with tempfile.TemporaryDirectory() as tmp_dir:
                    records = ct_downloader.download_documents(
                        records, Path(tmp_dir), session
                    )
                    st.session_state.zip_bytes = _build_zip(records, tmp_dir)
            except Exception as exc:
                st.warning(f"PDF download encountered errors: {exc}")

    # ── step 5: build export bytes ────────────────────────────────────────────
    st.session_state.csv_bytes = _to_csv_bytes(records)
    st.session_state.json_bytes = _to_json_bytes(records)
    st.session_state.records = records

# ── results panel ─────────────────────────────────────────────────────────────

if st.session_state.records is not None:
    records = st.session_state.records
    params = st.session_state.extracted_params or {}

    # Extracted parameters
    st.markdown("---")
    st.subheader("Extracted search parameters")
    p_col1, p_col2, p_col3 = st.columns(3)
    p_col1.metric("Condition", params.get("condition") or "—")
    p_col2.metric("Intervention", params.get("intervention") or "—")
    p_col3.metric("Sponsor", params.get("sponsor") or "—")

    # Results table
    st.markdown("---")
    st.subheader(f"Results — {len(records)} studies with documents")

    df = pd.DataFrame(records)
    # Build a clickable URL column
    df.insert(0, "link", df["nct_id"].apply(
        lambda x: f"https://clinicaltrials.gov/study/{x}"
    ))
    # Friendly download status
    if "download_status" in df.columns:
        df["download_status"] = df["download_status"].apply(_status_emoji)

    display_cols = ["link", "brief_title", "status", "phases", "sponsor",
                    "conditions", "doc_types_available", "download_status"]
    display_cols = [c for c in display_cols if c in df.columns]

    st.dataframe(
        df[display_cols],
        use_container_width=True,
        hide_index=True,
        column_config={
            "link": st.column_config.LinkColumn("NCT ID", display_text=r"NCT\d+"),
            "brief_title": st.column_config.TextColumn("Title", width="large"),
            "status": "Status",
            "phases": "Phase(s)",
            "sponsor": "Lead Sponsor",
            "conditions": "Conditions",
            "doc_types_available": "Doc Types",
            "download_status": "Download",
        },
    )

    # Download buttons
    st.markdown("---")
    st.subheader("Export")
    d1, d2, d3 = st.columns(3)

    with d1:
        if st.session_state.csv_bytes:
            st.download_button(
                "⬇️ Metadata CSV",
                data=st.session_state.csv_bytes,
                file_name="clinical_trials_metadata.csv",
                mime="text/csv",
                use_container_width=True,
            )

    with d2:
        if st.session_state.json_bytes:
            st.download_button(
                "⬇️ Metadata JSON",
                data=st.session_state.json_bytes,
                file_name="clinical_trials_metadata.json",
                mime="application/json",
                use_container_width=True,
            )

    with d3:
        if st.session_state.zip_bytes:
            pdf_count = sum(
                1
                for r in records
                if _status_emoji(r.get("download_status", "")) in ("✅",)
                # count actual files in the zip
            )
            st.download_button(
                "⬇️ All PDFs (ZIP)",
                data=st.session_state.zip_bytes,
                file_name="clinical_trials_documents.zip",
                mime="application/zip",
                use_container_width=True,
            )
        elif submitted and download_pdfs:
            st.info("No PDFs were downloaded.")

    # Download summary stats
    if any(r.get("download_status") not in (None, "skipped", "pending") for r in records):
        raw_statuses = [r.get("download_status", "unknown") for r in records]
        status_counts: dict[str, int] = {}
        for s in raw_statuses:
            status_counts[s] = status_counts.get(s, 0) + 1

        st.markdown("**Download summary:**")
        stat_cols = st.columns(len(status_counts))
        for idx, (status, count) in enumerate(sorted(status_counts.items())):
            stat_cols[idx].metric(f"{_status_emoji(status)} {status.title()}", count)

# ── footer ────────────────────────────────────────────────────────────────────

st.markdown("---")
st.caption(
    "Data sourced from [ClinicalTrials.gov](https://clinicaltrials.gov) via the public API v2. "
    "Query parsing powered by Claude (Anthropic)."
)
