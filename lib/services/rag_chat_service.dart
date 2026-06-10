import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

class RagChatService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Initialize the Gemini Model
  // (Make sure to inject your API key securely, e.g., via String.fromEnvironment)
  final GenerativeModel _geminiModel = GenerativeModel(
    model: 'gemini-1.5-flash',
    apiKey: const String.fromEnvironment('GEMINI_API_KEY'),
  );

  /// Executes the entire pipeline: Vector Search -> Document Fetch -> LLM Generation
  Future<String> askChatbot(String userQuestion) async {
    try {
      // Step 1: Submit the natural language query to the extension's tracking collection
      DocumentReference queryRef = await _db
          .collection('_firestore-vector-search')
          .doc('index')
          .collection('queries')
          .add({
        'query': userQuestion,
      });

      // Step 2: Poll/Wait until the extension flips the state to COMPLETED
      String? matchedDocId = await _waitForVectorMatch(queryRef);

      if (matchedDocId == null) {
        return "I couldn't find any relevant documents to answer that question.";
      }

      // Step 3: Fetch the raw text content using the retrieved Document ID (e.g., 'eco_plus_feature')
      DocumentSnapshot docSpec = await _db
          .collection('knowledge_base')
          .doc(matchedDocId)
          .get();

      if (!docSpec.exists) {
        return "Matched document reference found, but the source text is missing.";
      }

      Map<String, dynamic> docData = docSpec.data() as Map<String, dynamic>;
      String knowledgeContext = docData['content'] ?? "";

      // Step 4: Construct the augmented prompt and feed it to Gemini
      String aiResponse = await _generateAiAnswer(userQuestion, knowledgeContext);
      return aiResponse;

    } catch (e) {
      print("RAG Error: $e");
      return "Sorry, an error occurred while processing your request.";
    }
  }

  /// Internal helper to wait for the Firestore extension to compute the vector match
  Future<String?> _waitForVectorMatch(DocumentReference ref) async {
    int attempts = 0;
    while (attempts < 10) {
      await Future.delayed(const Duration(milliseconds: 800));
      DocumentSnapshot snapshot = await ref.get();

      if (snapshot.exists) {
        Map<String, dynamic> data = snapshot.data() as Map<String, dynamic>;

        // Dig into the status map structure we saw in Postman
        Map<String, dynamic>? status = data['status']?['textQuery'];
        if (status != null && status['state'] == 'COMPLETED') {
          List<dynamic>? ids = data['result']?['ids'];
          if (ids != null && ids.isNotEmpty) {
            return ids.first.toString(); // Returns 'eco_plus_feature'
          }
          return null; // Completed, but zero semantic matches found
        }
      }
      attempts++;
    }
    throw Exception("Vector search timed out.");
  }

  /// Internal helper to prompt Gemini using the fetched context
  Future<String> _generateAiAnswer(String question, String context) async {
    final prompt = '''
You are a helpful smart home assistant. Answer the user's question accurately using ONLY the provided context from the knowledge base. If the context doesn't contain the answer, politely explain that you don't know.

Context:
$context

User Question:
$question
''';

    final content = [Content.text(prompt)];
    final response = await _geminiModel.generateContent(content);
    return response.text ?? "The model failed to generate a text response.";
  }
}