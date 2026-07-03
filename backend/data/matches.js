/**
 * Seed data for the prototype.
 *
 * These are real, historical World Cup matches (not the 2026 tournament) chosen
 * deliberately: their scores/lineups are settled facts we can state confidently,
 * and they cover multiple tournaments, which satisfies the "broad tournament
 * coverage" goal from the spec without fabricating unplayed 2026 fixtures/results.
 *
 * Each entry doubles as a fallback in case the live Wikipedia scrape (see
 * services/scraper.js) fails or times out, so the app always has something
 * to show. `lineups` lists notable/key players rather than full starting
 * XIs, to keep the seed data low-risk and easy to verify.
 */

const matches = [
  {
    id: "wc2022-final",
    tournament: "2022 FIFA World Cup",
    stage: "Final",
    homeTeam: "Argentina",
    awayTeam: "France",
    date: "2022-12-18",
    venue: "Lusail Stadium, Lusail, Qatar",
    score: { home: 3, away: 3, note: "Argentina won 4-2 on penalties" },
    summary:
      "One of the most dramatic finals in World Cup history. Lionel Messi and " +
      "Angel Di Maria put Argentina 2-0 up, but Kylian Mbappe's hat-trick " +
      "(including two goals in 97 seconds late in normal time) forced extra " +
      "time. Messi scored again, Mbappe completed his hat-trick from the spot, " +
      "and Argentina won the resulting penalty shootout 4-2, with goalkeeper " +
      "Emiliano Martinez the shootout hero.",
    lineups: {
      home: ["Lionel Messi", "Angel Di Maria", "Julian Alvarez", "Emiliano Martinez (GK)"],
      away: ["Kylian Mbappe", "Olivier Giroud", "Antoine Griezmann", "Hugo Lloris (GK)"],
    },
    commentary:
      "Widely described by pundits as the greatest World Cup final ever played, " +
      "capping Messi's career with his first World Cup title.",
    wikipediaUrl: "https://en.wikipedia.org/wiki/2022_FIFA_World_Cup_final",
    youtubeQuery: "Argentina vs France 2022 World Cup Final highlights",
  },
  {
    id: "wc2018-final",
    tournament: "2018 FIFA World Cup",
    stage: "Final",
    homeTeam: "France",
    awayTeam: "Croatia",
    date: "2018-07-15",
    venue: "Luzhniki Stadium, Moscow, Russia",
    score: { home: 4, away: 2, note: null },
    summary:
      "France won their second World Cup title in an entertaining final that " +
      "featured the first VAR-awarded penalty in a World Cup final. An own " +
      "goal from Mario Mandzukic opened the scoring, Ivan Perisic equalised, " +
      "then Antoine Griezmann's penalty and goals from Paul Pogba and Kylian " +
      "Mbappe put France in control before Mandzukic's second goal made the " +
      "final score 4-2.",
    lineups: {
      home: ["Antoine Griezmann", "Kylian Mbappe", "Paul Pogba", "Hugo Lloris (GK, captain)"],
      away: ["Luka Modric (Golden Ball)", "Ivan Perisic", "Mario Mandzukic"],
    },
    commentary:
      "Luka Modric won the Golden Ball as tournament's best player despite Croatia's loss.",
    wikipediaUrl: "https://en.wikipedia.org/wiki/2018_FIFA_World_Cup_final",
    youtubeQuery: "France vs Croatia 2018 World Cup Final highlights",
  },
  {
    id: "wc2010-final",
    tournament: "2010 FIFA World Cup",
    stage: "Final",
    homeTeam: "Spain",
    awayTeam: "Netherlands",
    date: "2010-07-11",
    venue: "Soccer City, Johannesburg, South Africa",
    score: { home: 1, away: 0, note: "after extra time" },
    summary:
      "A tense, foul-heavy final settled deep into extra time. Andres Iniesta " +
      "struck the winning goal in the 116th minute to give Spain their first " +
      "ever World Cup title, capping a golden generation built around the " +
      "Barcelona/tiki-taka core of the national side.",
    lineups: {
      home: ["Andres Iniesta (match winner)", "Xavi", "Iker Casillas (GK, captain)"],
      away: ["Wesley Sneijder", "Arjen Robben", "Robin van Persie"],
    },
    commentary:
      "Iniesta's goal is remembered as one of the iconic moments in Spanish football history.",
    wikipediaUrl: "https://en.wikipedia.org/wiki/2010_FIFA_World_Cup_final",
    youtubeQuery: "Spain vs Netherlands 2010 World Cup Final highlights",
  },
  {
    id: "wc2014-semifinal",
    tournament: "2014 FIFA World Cup",
    stage: "Semi-final",
    homeTeam: "Brazil",
    awayTeam: "Germany",
    date: "2014-07-08",
    venue: "Estadio Mineirao, Belo Horizonte, Brazil",
    score: { home: 1, away: 7, note: null },
    summary:
      "Host nation Brazil, already without the injured Neymar and suspended " +
      "captain Thiago Silva, collapsed in stunning fashion. Germany scored " +
      "five goals in the first 29 minutes, including two from Toni Kroos in " +
      "69 seconds, on the way to a 7-1 rout that remains the heaviest defeat " +
      "in Brazilian World Cup history.",
    lineups: {
      home: ["David Luiz (captain)", "Julio Cesar (GK)"],
      away: ["Thomas Muller", "Miroslav Klose (record-breaking goal)", "Toni Kroos", "Sami Khedira"],
    },
    commentary:
      "The match, nicknamed the 'Mineirazo', is considered one of the biggest shocks in World Cup history.",
    wikipediaUrl: "https://en.wikipedia.org/wiki/Brazil_v_Germany_(2014_FIFA_World_Cup)",
    youtubeQuery: "Brazil vs Germany 7-1 2014 World Cup highlights",
  },
  {
    id: "wc2014-final",
    tournament: "2014 FIFA World Cup",
    stage: "Final",
    homeTeam: "Germany",
    awayTeam: "Argentina",
    date: "2014-07-13",
    venue: "Maracana, Rio de Janeiro, Brazil",
    score: { home: 1, away: 0, note: "after extra time" },
    summary:
      "A tight, chance-starved final was decided by a moment of quality: " +
      "substitute Mario Gotze controlled Andre Schurrle's cross on his chest " +
      "and volleyed home in the 113th minute to win Germany their fourth " +
      "World Cup title, with Lionel Messi's Argentina left empty-handed " +
      "despite Messi winning the tournament's Golden Ball.",
    lineups: {
      home: ["Mario Gotze (match winner)", "Manuel Neuer (GK)", "Philipp Lahm (captain)"],
      away: ["Lionel Messi (Golden Ball)", "Javier Mascherano", "Sergio Romero (GK)"],
    },
    commentary:
      "Gotze's winning goal is remembered as one of the great World Cup final moments.",
    wikipediaUrl: "https://en.wikipedia.org/wiki/2014_FIFA_World_Cup_final",
    youtubeQuery: "Germany vs Argentina 2014 World Cup Final highlights",
  },
];

module.exports = matches;
