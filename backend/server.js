// Local/dev entrypoint. In production (Vercel) the app is served via
// api/index.js as a serverless function instead of a long-running listener.
const app = require("./app");

const PORT = process.env.PORT || 4000;

app.listen(PORT, () => {
  console.log(`World Cup Highlights API listening on port ${PORT}`);
});
