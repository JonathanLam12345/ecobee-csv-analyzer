import { genkit } from 'genkit';
import { vertexAI } from '@genkit-ai/vertexai';

export const ai = genkit({
  plugins: [
    vertexAI({
      location: 'northamerica-northeast1', // Updated to Montréal
    }),
  ],
});