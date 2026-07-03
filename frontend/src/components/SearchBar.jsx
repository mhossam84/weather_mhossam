export default function SearchBar({ value, onChange }) {
  return (
    <div className="search-bar">
      <input
        type="search"
        inputMode="search"
        placeholder="Search a match, team, or tournament..."
        value={value}
        onChange={(e) => onChange(e.target.value)}
        aria-label="Search matches"
      />
    </div>
  );
}
