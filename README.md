# World Cup Highlights — Prototype

A mobile-first web app for browsing World Cup matches: final score, key
players, an embedded highlight video, a text summary, and post-match
reaction — built per the prototype spec (no paid sports APIs, no database).

## Stack

- **Backend**: Node.js + Express (`backend/`). Serves a small REST API over
  a hardcoded match list, enriched at request time with a best-effort
  Wikipedia scrape, plus YouTube embed URLs.
- **Frontend**: React + Vite (`frontend/`). Single-page, no router — a
  search/list view and a match detail view, mobile-first CSS.
- **No database.** Match metadata lives in `backend/data/matches.js`;
  scrape results are cached in-memory with a TTL (`backend/services/cache.js`).

## Running it locally

```bash
# terminal 1 — API on :4000
cd backend
npm install
npm run dev

# terminal 2 — frontend on :5173 (proxies /api to :4000, see vite.config.js)
cd frontend
npm install
npm run dev
```

Open http://localhost:5173 on your phone or a mobile viewport in devtools.

## How it works

- `GET /api/matches?q=...` — returns the match list, optionally filtered by
  team/tournament/stage/date substring.
- `GET /api/matches/:id` — returns full match detail: score, key players,
  and summary/commentary text, plus a YouTube embed URL. The summary/commentary
  are enriched from a live Wikipedia scrape when it succeeds (`summarySource:
  "live"`), and otherwise fall back to the curated seed text (`"seed"`) —
  the scrape has a 4s timeout and never blocks the response.

## Open questions from the spec — decisions made

**1. Best legal/ToS-safe way to pull YouTube highlights: embed vs. scrape?**
Embed, and specifically without scraping YouTube's search results HTML or
requiring a Data API key. `backend/services/youtube.js` builds a URL using
YouTube's own embed-player search parameter
(`https://www.youtube.com/embed?listType=search&list=<query>`) — this is a
documented embed feature, so the browser talks to YouTube directly and our
server never touches youtube.com. Trade-off: we can't rank results
server-side (view count, official channel) without the paid-tier-adjacent
Data API, so the embedded video is just YouTube's own top search hit. That's
an acceptable prototype trade-off; a production version would likely
upgrade to the Data API for curated picks.

**2. Which web sources are most reliably scrapable for match data?**
Wikipedia, not commercial sports news sites. Reasoning: commercial sites
change markup often, are the most likely to have scraping-hostile ToS, and
vary wildly in structure site-to-site. Wikipedia's football-match articles
use a consistent template (infobox + `Summary`/`Reactions` sections), the
content is CC BY-SA licensed, and `robots.txt` allows it. Because even
Wikipedia's markup shifts over time, `backend/services/scraper.js` treats
scraping as a best-effort **enrichment** layer, not the source of truth:
every seed match already has curated summary/commentary text, so a failed
or malformed scrape just falls back silently instead of breaking the page.

**3. Hardcode 2026 matches, or fetch the fixture list dynamically?**
Hardcoded, but not with 2026 fixtures. `backend/data/matches.js` seeds the
prototype with five real, settled historical World Cup matches (2010/2014
x2/2018/2022 finals and semis) instead of inventing 2026 results, so every
score/summary/lineup shown is a verifiable fact rather than a guess. The
data shape is intentionally the same shape a real fixture feed would use,
so swapping in an official 2026 fixture list (dates/teams/venues first,
scores/recaps populated post-match via the same scraper) is a data change,
not an architecture change.

## Known limitations

- **Lineups are "key players," not full starting XIs** — deliberately, to
  keep the seed data low-risk to state as fact.
- **No caching persistence** — the in-memory cache resets on server
  restart, per the spec's "no database" constraint.
- **Sandboxed dev environments may block outbound requests to Wikipedia** —
  if `backend/services/scraper.js` can't reach `en.wikipedia.org` (e.g. a
  restrictive network policy), it fails closed and the app silently serves
  the seed summary/commentary instead. This does not affect the YouTube
  embed, which loads directly in the end user's browser, not from the
  server.
