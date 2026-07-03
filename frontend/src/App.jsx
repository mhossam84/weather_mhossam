import { useEffect, useState } from "react";
import "./App.css";
import SearchBar from "./components/SearchBar";
import MatchList from "./components/MatchList";
import MatchDetail from "./components/MatchDetail";
import { fetchMatches, fetchMatchDetail } from "./api";

export default function App() {
  const [query, setQuery] = useState("");
  const [matches, setMatches] = useState([]);
  const [listLoading, setListLoading] = useState(true);
  const [listError, setListError] = useState(null);

  const [selectedId, setSelectedId] = useState(null);
  const [match, setMatch] = useState(null);
  const [detailLoading, setDetailLoading] = useState(false);
  const [detailError, setDetailError] = useState(null);

  useEffect(() => {
    setListLoading(true);
    setListError(null);
    const handle = setTimeout(() => {
      fetchMatches(query)
        .then(setMatches)
        .catch(() => setListError("Couldn't load matches. Is the backend running?"))
        .finally(() => setListLoading(false));
    }, 200); // small debounce while typing
    return () => clearTimeout(handle);
  }, [query]);

  useEffect(() => {
    if (!selectedId) return;
    setDetailLoading(true);
    setDetailError(null);
    setMatch(null);
    fetchMatchDetail(selectedId)
      .then(setMatch)
      .catch(() => setDetailError("Couldn't load this match."))
      .finally(() => setDetailLoading(false));
  }, [selectedId]);

  if (selectedId) {
    return (
      <div className="app">
        <MatchDetail
          match={match}
          loading={detailLoading}
          error={detailError}
          onBack={() => setSelectedId(null)}
        />
      </div>
    );
  }

  return (
    <div className="app">
      <header className="app-header">
        <h1>World Cup Highlights</h1>
        <p className="app-subtitle">Scores, lineups, and highlights in one place</p>
      </header>
      <SearchBar value={query} onChange={setQuery} />
      <MatchList matches={matches} onSelect={setSelectedId} loading={listLoading} error={listError} />
    </div>
  );
}
