/**
 * Best-effort scraper for match recap text, sourced from Wikipedia match
 * articles (see data/matches.js for why Wikipedia: it's the most reliably
 * scrapable, well-structured, and legally low-risk source we found for
 * historical World Cup match detail -- see README "Open questions" section
 * for the fuller rationale versus commercial sports news sites).
 *
 * This is intentionally an *enrichment* layer, not the source of truth:
 * every match already has curated summary/commentary text in
 * data/matches.js, so if a scrape fails (network blocked, page structure
 * changed, request times out) the app still renders correctly with the
 * seed content. Never let scraping failures block or slow down the demo.
 */

const cheerio = require("cheerio");
const fetch = require("node-fetch");
const cache = require("./cache");

const FETCH_TIMEOUT_MS = 4000;
const CACHE_TTL_MS = 6 * 60 * 60 * 1000; // 6 hours

// Wikipedia's parser output has changed over time; a heading can be
// rendered as `<h2 id="X">` (old skin) or wrapped in `<div class="mw-heading">`
// (new skin). We try a handful of candidate ids and both layouts.
const SUMMARY_HEADING_IDS = ["Summary", "Match_summary", "Summary_of_the_match"];
const COMMENTARY_HEADING_IDS = ["Reactions", "Aftermath", "Post-match"];

async function fetchHtml(url) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
  try {
    const res = await fetch(url, {
      signal: controller.signal,
      headers: {
        "User-Agent": "WorldCupHighlightsPrototype/0.1 (educational prototype)",
      },
    });
    if (!res.ok) return null;
    return await res.text();
  } catch (err) {
    return null;
  } finally {
    clearTimeout(timeout);
  }
}

function extractSection($, headingIds) {
  for (const id of headingIds) {
    const heading = $(`#${id}`).first();
    if (!heading.length) continue;

    const container = heading.closest(".mw-heading").length
      ? heading.closest(".mw-heading")
      : heading.closest("h2, h3").length
      ? heading.closest("h2, h3")
      : heading;

    const paragraphs = container.nextUntil("h2, h3, .mw-heading", "p");
    const text = paragraphs
      .map((_, el) => $(el).text())
      .get()
      .join(" ")
      .replace(/\[\d+\]/g, "") // strip Wikipedia footnote markers like [12]
      .replace(/\s+/g, " ")
      .trim();

    if (text) return text;
  }
  return null;
}

function extractLeadParagraphs($) {
  const paragraphs = $("#mw-content-text .mw-parser-output > p")
    .filter((_, el) => $(el).text().trim().length > 40)
    .slice(0, 2);
  const text = paragraphs
    .map((_, el) => $(el).text())
    .get()
    .join(" ")
    .replace(/\[\d+\]/g, "")
    .replace(/\s+/g, " ")
    .trim();
  return text || null;
}

/**
 * Attempts to enrich a seed match with freshly scraped text.
 * Returns { summary, commentary } where either field may be null if
 * scraping didn't find/confirm anything -- callers should fall back to
 * the seed data in that case.
 */
async function scrapeMatchRecap(wikipediaUrl) {
  if (!wikipediaUrl) return { summary: null, commentary: null };

  const cached = cache.get(wikipediaUrl);
  if (cached) return cached;

  const html = await fetchHtml(wikipediaUrl);
  if (!html) {
    return { summary: null, commentary: null };
  }

  let result;
  try {
    const $ = cheerio.load(html);
    const summary = extractSection($, SUMMARY_HEADING_IDS) || extractLeadParagraphs($);
    const commentary = extractSection($, COMMENTARY_HEADING_IDS);
    result = { summary, commentary };
  } catch (err) {
    result = { summary: null, commentary: null };
  }

  cache.set(wikipediaUrl, result, CACHE_TTL_MS);
  return result;
}

module.exports = { scrapeMatchRecap };
