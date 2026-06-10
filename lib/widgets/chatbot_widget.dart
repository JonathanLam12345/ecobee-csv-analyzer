import 'package:flutter/material.dart';

import '../services/rag_chat_service.dart';
// Make sure to import your new service file!

class ChatSessionManager {
  static final ChatSessionManager _instance = ChatSessionManager._internal();
  factory ChatSessionManager() => _instance;
  ChatSessionManager._internal();

  final List<ChatMessage> messages = [];
}

class ChatbotWidget extends StatefulWidget {
  const ChatbotWidget({super.key});

  @override
  State<ChatbotWidget> createState() => _ChatbotWidgetState();
}

class _ChatbotWidgetState extends State<ChatbotWidget> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ChatSessionManager _session = ChatSessionManager();

  // [NEW] Instantiate your RAG service instead of Genkit
  final RagChatService _ragService = RagChatService();

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();

    // If this is a brand new session, seed it with a helpful welcome message
    if (_session.messages.isEmpty) {
      _session.messages.add(ChatMessage(
        text: "Hello! I'm your ecobee AI Assistant. How can I help you analyze your thermostat runtime reports or troubleshoot HVAC setups today?",
        isUser: false,
      ));
    } else {
      // If returning to an existing open chat, smoothly snap to the bottom
      scrollToBottom();
    }
  }

  void scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleSubmitted(String text) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty || _isLoading) return;

    _textController.clear();

    setState(() {
      _session.messages.add(ChatMessage(text: cleanText, isUser: true));
      _isLoading = true;
    });

    scrollToBottom();

    try {
      // [NEW] Call the askChatbot method from your RagChatService
      final aiResponse = await _ragService.askChatbot(cleanText);

      setState(() {
        _session.messages.add(ChatMessage(text: aiResponse, isUser: false));
      });
    } catch (error) {
      setState(() {
        _session.messages.add(ChatMessage(
          text: "Sorry, I encountered an issue connecting to the database.",
          isUser: false,
        ));
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
      scrollToBottom();
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
      ),
      child: Column(
        children: [
          // Header with Close Button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.green.shade600,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "ecobee AI Assistant",
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // Chat Messages View
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: _session.messages.length + (_isLoading ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _session.messages.length && _isLoading) {
                  return const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.all(12.0),
                      child: SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.green),
                      ),
                    ),
                  );
                }
                return _buildBubble(_session.messages[index]);
              },
            ),
          ),

          // Input Tray
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    onSubmitted: _isLoading ? null : _handleSubmitted,
                    decoration: InputDecoration(
                      hintText: "Ask about HVAC types or reboots...",
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.send, color: _isLoading ? Colors.grey : Colors.green),
                  onPressed: _isLoading ? null : () => _handleSubmitted(_textController.text),
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildBubble(ChatMessage msg) {
    return Align(
      alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: msg.isUser ? Colors.green.shade100 : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(msg.text, style: const TextStyle(color: Colors.black87)),
      ),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  ChatMessage({required this.text, required this.isUser});
}