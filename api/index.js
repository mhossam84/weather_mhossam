// Vercel serverless entrypoint: an Express app is itself a valid
// (req, res) request handler, so it can be exported directly here.
module.exports = require("../backend/app");
