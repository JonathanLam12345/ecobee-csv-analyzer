import { genkit, z } from 'genkit';
import { googleAI } from '@genkit-ai/googleai';
import { startFlowServer } from '@genkit-ai/express';
import * as admin from 'firebase-admin';

// 1. Initialize Firebase Admin
admin.initializeApp();
const db = admin.firestore();

// 2. Initialize Genkit
const ai = genkit({
  plugins: [googleAI()],
});

// 3. Define the Chat Flow
export const ecobeeChatFlow = ai.defineFlow(
  {
    name: 'ecobeeChatFlow',
    inputSchema: z.string(),
    outputSchema: z.string(),
  },
  async (userInput) => {
    // A. Generate response from Gemini using the explicit string identifier
    const response = await ai.generate({
      model: 'googleai/gemini-2.5-flash',
      system: "You are an expert HVAC diagnostic assistant...",
      prompt: userInput,
    });

    // B. Save the conversation log to Firestore (wrapped safely in a try/catch)
    try {
      await db.collection('diagnostic_chats').add({
        prompt: userInput,
        response: response.text,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (dbError) {
      console.error("Firestore save failed, but keeping chat alive:", dbError);
    }

    // C. Return the string answer back to Flutter
    return response.text;
  }
);

// 4. Start the Express flow server
startFlowServer({
  flows: [ecobeeChatFlow],
  port: process.env.PORT ? parseInt(process.env.PORT) : 3400,
  cors: { origin: "*" }
});