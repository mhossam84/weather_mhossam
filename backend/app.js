const express = require("express");
const cors = require("cors");

const matches = require("./data/matches");
const youtube = require("./services/youtube");
const { scrapeMatchRecap } = require("./services/scraper");

const app = express();

app.use(cors());
app.use(express.json());

function toListItem(match) {
  return {
    id: match.id,
    tournament: match.tournament,
    stage: match.stage,
    homeTeam: match.homeTeam,
    awayTeam: match.awayTeam,
    date: match.date,
    score: match.score,
  };
}

// GET /api/matches?q=argentina
app.get("/api/matches", (req, res) => {
  const q = (req.query.q || "").toLowerCase().trim();

  const results = !q
    ? matches
    : matches.filter((m) => {
        const haystack = [m.homeTeam, m.awayTeam, m.tournament, m.stage, m.date]
          .join(" ")
          .toLowerCase();
        return haystack.includes(q);
      });

  res.json(results.map(toListItem));
});

// GET /api/matches/:id
app.get("/api/matches/:id", async (req, res) => {
  const match = matches.find((m) => m.id === req.params.id);
  if (!match) {
    return res.status(404).json({ error: "Match not found" });
  }

  // Best-effort live enrichment; never blocks longer than the scraper's own
  // timeout, and always falls back to curated seed text on failure.
  const scraped = await scrapeMatchRecap(match.wikipediaUrl);

  res.json({
    ...match,
    summary: scraped.summary || match.summary,
    commentary: scraped.commentary || match.commentary,
    summarySource: scraped.summary ? "live" : "seed",
    commentarySource: scraped.commentary ? "live" : "seed",
    video: {
      embedUrl: youtube.buildEmbedSearchUrl(match.youtubeQuery),
      searchUrl: youtube.buildSearchUrl(match.youtubeQuery),
    },
  });
});

module.exports = app;
