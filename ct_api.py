import logging
import time

import requests

BASE_URL = "https://clinicaltrials.gov/api/v2/studies"
CDN_BASE = "https://cdn.clinicaltrials.gov/large-docs"
REQUEST_DELAY = 0.5  # seconds between paginated requests
MAX_PAGE_SIZE = 1000
SESSION_TIMEOUT = 30
USER_AGENT = "clinical-trials-search/1.0 (research tool)"

logger = logging.getLogger(__name__)


def build_pdf_url(nct_id: str, filename: str) -> str:
    suffix = nct_id[-2:]
    return f"{CDN_BASE}/{suffix}/{nct_id}/{filename}"


def search_studies(
    session: requests.Session,
    condition: str | None,
    intervention: str | None,
    sponsor: str | None,
    max_studies: int,
    doc_types: set[str],
) -> list[dict]:
    params: dict = {
        "format": "json",
        "pageSize": min(max_studies, MAX_PAGE_SIZE),
    }
    if condition:
        params["query.cond"] = condition
    if intervention:
        params["query.intr"] = intervention
    if sponsor:
        params["query.lead"] = sponsor
    # Pre-filter server-side to studies that have protocol docs when requested
    if "Prot" in doc_types:
        params["aggFilters"] = "docs:prot"

    studies: list[dict] = []
    seen: set[str] = set()
    page_token: str | None = None
    page_num = 0

    while len(studies) < max_studies:
        if page_token:
            params["pageToken"] = page_token
        elif "pageToken" in params:
            del params["pageToken"]

        logger.debug("Fetching page %d (collected %d studies)", page_num + 1, len(studies))
        data = _make_request(session, BASE_URL, params)

        for study in data.get("studies", []):
            nct_id = (
                study.get("protocolSection", {})
                .get("identificationModule", {})
                .get("nctId", "")
            )
            if nct_id and nct_id not in seen:
                seen.add(nct_id)
                studies.append(study)
            if len(studies) >= max_studies:
                break

        page_token = data.get("nextPageToken")
        page_num += 1

        if not page_token or len(studies) >= max_studies:
            break

        time.sleep(REQUEST_DELAY)

    logger.info("Retrieved %d studies from API", len(studies))
    return studies


def _make_request(session: requests.Session, url: str, params: dict) -> dict:
    backoff = 1
    last_exc: Exception | None = None

    for attempt in range(3):
        try:
            resp = session.get(url, params=params, timeout=SESSION_TIMEOUT)

            if resp.status_code == 429:
                retry_after = int(resp.headers.get("Retry-After", backoff))
                logger.warning("Rate limited — sleeping %ds", retry_after)
                time.sleep(retry_after)
                backoff *= 2
                continue

            if resp.status_code in (500, 502, 503, 504):
                logger.warning(
                    "HTTP %d on attempt %d — retrying in %ds",
                    resp.status_code, attempt + 1, backoff,
                )
                time.sleep(backoff)
                backoff *= 2
                continue

            if resp.status_code == 404:
                raise ValueError(f"404 Not Found: {url}")

            resp.raise_for_status()
            return resp.json()

        except (requests.exceptions.ConnectionError, requests.exceptions.Timeout) as exc:
            last_exc = exc
            logger.warning("Network error on attempt %d: %s — retrying in %ds", attempt + 1, exc, backoff)
            time.sleep(backoff)
            backoff *= 2

    raise RuntimeError(f"Failed after 3 attempts: {url}") from last_exc


def make_session() -> requests.Session:
    session = requests.Session()
    session.headers.update({"User-Agent": USER_AGENT})
    return session
