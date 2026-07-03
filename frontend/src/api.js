const BASE_URL = import.meta.env.VITE_API_URL || "";

export async function fetchMatches(query) {
  const params = query ? `?q=${encodeURIComponent(query)}` : "";
  const res = await fetch(`${BASE_URL}/api/matches${params}`);
  if (!res.ok) throw new Error("Failed to load matches");
  return res.json();
}

export async function fetchMatchDetail(id) {
  const res = await fetch(`${BASE_URL}/api/matches/${encodeURIComponent(id)}`);
  if (!res.ok) throw new Error("Failed to load match detail");
  return res.json();
}
