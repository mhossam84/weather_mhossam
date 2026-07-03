function formatScore(score) {
  if (!score) return "";
  return `${score.home} - ${score.away}`;
}

export default function MatchList({ matches, onSelect, loading, error }) {
  if (loading) return <p className="status-text">Loading matches...</p>;
  if (error) return <p className="status-text error">{error}</p>;
  if (matches.length === 0) {
    return <p className="status-text">No matches found. Try a different search.</p>;
  }

  return (
    <ul className="match-list">
      {matches.map((match) => (
        <li key={match.id}>
          <button className="match-card" onClick={() => onSelect(match.id)}>
            <div className="match-card__meta">
              {match.tournament} &middot; {match.stage}
            </div>
            <div className="match-card__teams">
              <span>{match.homeTeam}</span>
              <span className="match-card__score">{formatScore(match.score)}</span>
              <span>{match.awayTeam}</span>
            </div>
            <div className="match-card__date">{match.date}</div>
          </button>
        </li>
      ))}
    </ul>
  );
}
