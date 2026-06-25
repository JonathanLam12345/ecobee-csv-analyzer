const functions = require("firebase-functions");
const axios = require("axios");
const express = require("express");

const app = express();

// GET /temp endpoint
app.get("/temp", async (req, res) => {
  try {
    const response = await axios.get("http://<IP>:8005/temp");

    res.json(response.data);
  } catch (error) {
    res.status(500).json({
      error: "Failed to fetch temperature",
      details: error.message,
    });
  }
});

exports.api = functions.https.onRequest(app);