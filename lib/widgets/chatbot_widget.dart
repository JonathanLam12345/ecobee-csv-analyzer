import 'package:flutter/material.dart';
import 'package:genkit/client.dart';

class ChatbotWidget extends StatefulWidget {
  const ChatbotWidget({super.key});

  @override
  State<ChatbotWidget> createState() => _ChatbotWidgetState();
}

class _ChatbotWidgetState extends State<ChatbotWidget> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  late final RemoteAction<String, String> _chatFlow;

  @override
  void initState() {
    super.initState();
    _chatFlow = defineRemoteAction<String, String>(
      url: 'http://localhost:3400/ecobeeAgentAssistant',
      fromResponse: (data) => data as String,
      fromStreamChunk: (chunk) => chunk as String,
    );
    _messages.add(ChatMessage(text: "Hi team. I'm loaded with ecobee manuals. What can I help you find?", isUser: false));
  }

  Future<void> _handleSubmitted(String text) async {
    if (text.trim().isEmpty) return;
    _textController.clear();
    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
      _isLoading = true;
      _messages.add(ChatMessage(text: "", isUser: false));
    });

    try {
      final responseStream = _chatFlow.stream(input: text);
      await for (final chunk in responseStream) {
        setState(() {
          final last = _messages.length - 1;
          _messages[last] = ChatMessage(text: _messages[last].text + chunk, isUser: false);
        });
      }
    } catch (e) {
      setState(() {
        _messages.last = ChatMessage(text: "Error: Could not connect to backend.", isUser: false);
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 400,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.blueGrey.shade100)),
      child: Column(
        children: [
          Expanded(child: ListView.builder(itemCount: _messages.length, itemBuilder: (c, i) => _buildBubble(_messages[i]))),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(children: [
              Expanded(child: TextField(controller: _textController, onSubmitted: _handleSubmitted, decoration: const InputDecoration(hintText: "Ask a question..."))),
              IconButton(icon: const Icon(Icons.send), onPressed: () => _handleSubmitted(_textController.text))
            ]),
          )
        ],
      ),
    );
  }

  Widget _buildBubble(ChatMessage msg) => ListTile(title: Text(msg.text, style: TextStyle(color: msg.isUser ? Colors.green : Colors.black)));
}

class ChatMessage {
  final String text; final bool isUser;
  ChatMessage({required this.text, required this.isUser});
}