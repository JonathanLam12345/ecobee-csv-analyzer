import 'package:http/http.dart' as http;
import 'dart:convert';

// This function lives here, totally isolated from your buttons and colors
Future<String> askDiagnosticAssistant(String userMessage) async {
 // final url = Uri.parse('http://localhost:3400/ecobeeChatFlow');
  final url = Uri.parse('https://chatbot-backend-296794280928.northamerica-northeast2.run.app/ecobeeChatFlow');
  try {
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        "data": userMessage
      }),
    );

    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      return jsonResponse['result'];
    } else {
      return "Backend error: ${response.statusCode}";
    }
  } catch (e) {
    return "Failed to connect to the Genkit server: $e";
  }
}