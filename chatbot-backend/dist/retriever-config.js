import { defineFirestoreRetriever } from '@genkit-ai/firebase';
import { initializeApp, getApps } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { ai } from './genkit-config.js';
//import { vertexAI } from '@genkit-ai/vertexai';
if (getApps().length === 0) {
    initializeApp();
}
const db = getFirestore();
export const knowledgeRetriever = defineFirestoreRetriever(ai, {
    name: 'knowledgeRetriever',
    firestore: db,
    collection: 'knowledge_base',
    contentField: 'content',
    vectorField: 'embedding',
    // Pass the string reference directly so it inherits your 'ai' instance region
    embedder: 'vertexai/gemini-embedding-001',
});
