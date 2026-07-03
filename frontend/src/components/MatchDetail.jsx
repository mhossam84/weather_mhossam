export default function MatchDetail({ match, loading, error, onBack }) {
  return (
    <div className="match-detail">
      <button className="back-button" onClick={onBack}>
        &larr; Back to matches
      </button>

      {loading && <p className="status-text">Loading match...</p>}
      {error && <p className="status-text error">{error}</p>}

      {match && (
        <>
          <header className="match-header">
            <div className="match-header__meta">
              {match.tournament} &middot; {match.stage} &middot; {match.date}
            </div>
            <div className="match-header__teams">
              <span>{match.homeTeam}</span>
              <span className="match-header__score">
                {match.score.home} - {match.score.away}
              </span>
              <span>{match.awayTeam}</span>
            </div>
            {match.score.note && <div className="match-header__note">{match.score.note}</div>}
            <div className="match-header__venue">{match.venue}</div>
          </header>

          <section className="section">
            <h2>Highlights</h2>
            <div className="video-embed">
              <iframe
                src={match.video.embedUrl}
                title={`${match.homeTeam} vs ${match.awayTeam} highlights`}
                allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
                allowFullScreen
                loading="lazy"
              />
            </div>
            <a
              className="youtube-link"
              href={match.video.searchUrl}
              target="_blank"
              rel="noopener noreferrer"
            >
              More highlights on YouTube &rarr;
            </a>
          </section>

          <section className="section">
            <h2>Summary</h2>
            <p>{match.summary}</p>
          </section>

          <section className="section">
            <h2>Key players</h2>
            <div className="lineups">
              <div className="lineup-column">
                <h3>{match.homeTeam}</h3>
                <ul>
                  {match.lineups.home.map((player) => (
                    <li key={player}>{player}</li>
                  ))}
                </ul>
              </div>
              <div className="lineup-column">
                <h3>{match.awayTeam}</h3>
                <ul>
                  {match.lineups.away.map((player) => (
                    <li key={player}>{player}</li>
                  ))}
                </ul>
              </div>
            </div>
          </section>

          {match.commentary && (
            <section className="section">
              <h2>Post-match reaction</h2>
              <p>{match.commentary}</p>
            </section>
          )}

          <p className="source-note">
            Source:{" "}
            <a href={match.wikipediaUrl} target="_blank" rel="noopener noreferrer">
              Wikipedia
            </a>{" "}
            ({match.summarySource === "live" ? "live fetch" : "cached seed data"})
          </p>
        </>
      )}
    </div>
  );
}
