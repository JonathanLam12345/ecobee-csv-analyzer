import express from "express";

import { z } from "zod";

import { initializeApp, getApps } from "firebase-admin/app";

import { getFirestore, FieldValue } from "firebase-admin/firestore";

import { ai } from "./genkit-config.js";

import { knowledgeRetriever } from "./retriever-config.js";

if (getApps().length === 0) {
  initializeApp();
}

const db = getFirestore();

const app = express();

app.use(express.json());

async function getChatHistory(limit: number = 3): Promise<string> {
  try {
    const snapshot = await db
      .collection("chats")

      .orderBy("timestamp", "desc")

      .limit(limit)

      .get();

    return snapshot.docs

      .map((doc) => {
        const data = doc.data();

        return `User: ${data.userQuery}\nBot: ${data.aiResponse}`;
      })

      .reverse()

      .join("\n");
  } catch (error) {
    console.error("Error fetching history:", error);

    return "No prior history available.";
  }
}

export const ecobeeChatFlow = ai.defineFlow(
  {
    name: "ecobeeChatFlow",

    inputSchema: z.object({ data: z.string() }),

    outputSchema: z.string(),
  },

  async (input) => {
    try {
      const userMessage = input.data;

      const docs = await ai.retrieve({
        retriever: knowledgeRetriever,

        query: userMessage,

        options: { limit: 3 },
      });

   // Changed to 'content' which is the standard Genkit field
         const knowledgeContext = docs.map((doc: any) => doc.content ? doc.content[0].text : doc.text).join('\n');

         // ==========================================
         // STAGE 1: DIAGNOSE RETRIEVER & PARSING
         // ==========================================
         console.log("=== RAG DIAGNOSTICS ===");
         console.log(`1. Number of documents found by retriever: ${docs?.length || 0}`);

         // Print the raw object layout from Firestore vector search to verify field names
         console.log("2. Raw Document Structure:", JSON.stringify(docs, null, 2));

         // Verify if anything survived the string conversion
         console.log(`3. Final parsed knowledgeContext length: ${knowledgeContext?.length || 0}`);
         console.log("4. Content passing to Gemini:\n", knowledgeContext || "⚠️ WARNING: CONTEXT IS COMPLETELY EMPTY!");
         console.log("=======================");

         const chatHistory = await getChatHistory(3);

         // STAGE 2: DIAGNOSE CHAT HISTORY
         console.log("=== CHAT HISTORY CONTEXT ===");
         console.log(chatHistory || "No history found.");
         console.log("=============================");

         console.log("Attempting to connect to Gemini with model: gemini-2.5-flash");

      // ADD THE LOG HERE

      console.log(
        "Attempting to connect to Gemini with model: gemini-2.5-flash",
      );

      const response = await ai.generate({
        // Corrected model version

        model: "vertexai/gemini-2.5-flash",

        prompt: `

You are an expert on ecobee thermostats.

Use the following background information and past conversation history to answer the user's question.



Background Knowledge:

${knowledgeContext}



Past Conversation History:

${chatHistory}



Question: ${userMessage}

`,
      });

      const answer = response.text || "I couldn't generate a response.";

      await db.collection("chats").add({
        userQuery: userMessage,

        aiResponse: answer,

        timestamp: FieldValue.serverTimestamp(),
      });

      return answer;
    } catch (error) {
      console.error("Error in flow:", error);

      throw error;
    }
  },
);

// UPDATED: Added /api/ prefix to match your Postman URL

app.post("/api/ecobeeChatFlow", async (req, res) => {
  try {
    const result = await ecobeeChatFlow(req.body);

    res.json({ result });
  } catch (error: any) {
    console.error("Endpoint error:", error);

    res
      .status(500)
      .json({ error: error.message || "Unknown Internal Server Error" });
  }
});

const port = parseInt(process.env.PORT || "8080");

app.listen(port, "0.0.0.0", () => {
  console.log(`Server listening on port ${port} and binding to 0.0.0.0`);
});
