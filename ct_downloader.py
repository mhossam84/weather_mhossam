import logging
import time
from pathlib import Path

import requests
from tqdm import tqdm

logger = logging.getLogger(__name__)


def make_output_dirs(output_dir: Path, nct_id: str) -> Path:
    doc_dir = output_dir / "documents" / nct_id
    doc_dir.mkdir(parents=True, exist_ok=True)
    return doc_dir


def download_documents(
    records: list[dict],
    output_dir: Path,
    session: requests.Session,
) -> list[dict]:
    total_docs = sum(len(r["doc_filenames"].split("|")) for r in records if r["doc_filenames"])
    logger.info("Downloading documents for %d studies (%d documents total)", len(records), total_docs)

    for record in records:
        nct_id = record["nct_id"]
        filenames = [f for f in record["doc_filenames"].split("|") if f]
        urls = [u for u in record["doc_urls"].split("|") if u]
        type_abbrevs = [t for t in record["doc_types_available"].split("|") if t]

        if not filenames:
            record["download_status"] = "skipped"
            continue

        doc_dir = make_output_dirs(output_dir, nct_id)
        statuses: list[str] = []
        local_paths: list[str] = []

        # Track per-typeAbbrev index to handle filename collisions
        type_counts: dict[str, int] = {}

        for idx, (url, filename, type_abbrev) in enumerate(
            zip(urls, filenames, type_abbrevs)
        ):
            type_counts[type_abbrev] = type_counts.get(type_abbrev, 0) + 1
            count = type_counts[type_abbrev]

            stem = f"{nct_id}_{type_abbrev}"
            if count > 1:
                stem = f"{stem}_{count}"
            local_path = doc_dir / f"{stem}.pdf"

            if local_path.exists():
                logger.debug("Skipping existing file: %s", local_path)
                statuses.append("exists")
                local_paths.append(str(local_path))
                continue

            status = _download_file(session, url, local_path)
            statuses.append(status)
            if status in ("success",):
                local_paths.append(str(local_path))
            else:
                local_paths.append("")

        # Summarise per-record status
        if all(s == "exists" for s in statuses):
            record["download_status"] = "exists"
        elif all(s in ("success", "exists") for s in statuses):
            record["download_status"] = "success"
        elif any(s in ("success", "exists") for s in statuses):
            record["download_status"] = "partial"
        elif all(s == "unavailable" for s in statuses):
            record["download_status"] = "unavailable"
        else:
            record["download_status"] = "failed"

        record["download_paths"] = "|".join(p for p in local_paths if p)

    return records


def _download_file(session: requests.Session, url: str, local_path: Path) -> str:
    part_path = local_path.with_suffix(".part")
    backoff = 1

    for attempt in range(3):
        try:
            resp = session.get(url, stream=True, timeout=60)

            if resp.status_code == 404:
                logger.warning("Document not found (404): %s", url)
                return "unavailable"

            if resp.status_code == 429:
                retry_after = int(resp.headers.get("Retry-After", backoff))
                logger.warning("Rate limited — sleeping %ds", retry_after)
                time.sleep(retry_after)
                backoff *= 2
                continue

            if resp.status_code in (500, 502, 503, 504):
                logger.warning("HTTP %d on attempt %d: %s", resp.status_code, attempt + 1, url)
                time.sleep(backoff)
                backoff *= 2
                continue

            resp.raise_for_status()

            total = int(resp.headers.get("Content-Length", 0)) or None
            with (
                open(part_path, "wb") as f,
                tqdm(
                    total=total,
                    unit="B",
                    unit_scale=True,
                    unit_divisor=1024,
                    desc=local_path.name,
                    leave=False,
                ) as bar,
            ):
                for chunk in resp.iter_content(chunk_size=8192):
                    f.write(chunk)
                    bar.update(len(chunk))

            part_path.rename(local_path)
            logger.debug("Downloaded: %s", local_path)
            return "success"

        except (requests.exceptions.ConnectionError, requests.exceptions.Timeout) as exc:
            logger.warning("Network error on attempt %d: %s — retrying in %ds", attempt + 1, exc, backoff)
            time.sleep(backoff)
            backoff *= 2
        except OSError as exc:
            logger.warning("Disk error writing %s: %s", local_path, exc)
            _cleanup_part(part_path)
            return "failed"

    _cleanup_part(part_path)
    logger.warning("Failed after 3 attempts: %s", url)
    return "failed"


def _cleanup_part(part_path: Path) -> None:
    try:
        if part_path.exists():
            part_path.unlink()
    except OSError:
        pass
