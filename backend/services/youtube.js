/**
 * YouTube integration for the prototype.
 *
 * We deliberately do NOT scrape YouTube's search results HTML and we do NOT
 * require a YouTube Data API key. Instead we use YouTube's own public embed
 * player search feature (listType=search&list=<query>), which is a
 * documented embed-player parameter, not a scrape -- the browser talks
 * directly to youtube.com inside the iframe, our server never touches
 * YouTube at all. This is the ToS-safe option flagged as an open question
 * in the spec.
 *
 * Trade-off: because there's no API key, we can't rank/filter results
 * server-side (view count, official channel, etc.) -- we just hand YouTube
 * a search query and let its own top result play. Good enough for a
 * prototype; a production version would likely upgrade to the YouTube Data
 * API for curated result picking.
 */

function buildEmbedSearchUrl(query) {
  const params = new URLSearchParams({
    listType: "search",
    list: query,
  });
  return `https://www.youtube.com/embed?${params.toString()}`;
}

function buildSearchUrl(query) {
  const params = new URLSearchParams({ search_query: query });
  return `https://www.youtube.com/results?${params.toString()}`;
}

module.exports = { buildEmbedSearchUrl, buildSearchUrl };
