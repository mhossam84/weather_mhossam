import json
import logging

import anthropic

logger = logging.getLogger(__name__)

_SYSTEM_PROMPT = """\
You are a clinical trials search assistant. Extract structured search parameters from natural language queries.

Return ONLY a valid JSON object with exactly these keys:
- "condition": the disease, condition, or medical term to search (string or null)
- "intervention": the drug, treatment, or intervention to search (string or null)
- "sponsor": the lead organization, company, or sponsor to search (string or null)

Use null for any field not mentioned. Extract the most specific, relevant term for each field.
Do not include explanations — only the JSON object.\
"""


def parse_search_query(query: str) -> dict[str, str | None]:
    """Use Claude to extract condition, intervention, and sponsor from a natural language query.

    The system prompt is cached with prompt caching to reduce latency and cost on
    repeated calls (the system prompt is always identical across requests).
    """
    client = anthropic.Anthropic()

    response = client.messages.create(
        model="claude-opus-4-7",
        max_tokens=256,
        system=[
            {
                "type": "text",
                "text": _SYSTEM_PROMPT,
                "cache_control": {"type": "ephemeral"},  # stable prefix — cache it
            }
        ],
        messages=[
            {
                "role": "user",
                "content": f"Extract search parameters from this query: {query}",
            }
        ],
    )

    logger.debug(
        "Query parser usage: input=%d cache_read=%d cache_write=%d",
        response.usage.input_tokens,
        getattr(response.usage, "cache_read_input_tokens", 0),
        getattr(response.usage, "cache_creation_input_tokens", 0),
    )

    text = next(b.text for b in response.content if b.type == "text").strip()

    # Strip markdown code fences if the model wrapped the JSON
    if text.startswith("```"):
        lines = text.splitlines()
        text = "\n".join(lines[1:-1] if lines[-1] == "```" else lines[1:])

    parsed = json.loads(text)
    return {
        "condition": parsed.get("condition") or None,
        "intervention": parsed.get("intervention") or None,
        "sponsor": parsed.get("sponsor") or None,
    }
