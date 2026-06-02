import 'tool_call.dart';

enum MessageRole { user, model, system }

class ChatMessage {
  final String id;
  final MessageRole role;
  String text;
  final List<ToolCall> toolCalls;

  final List<String> attachments;

  bool streaming;
  String? error;
  String? thinking;

  int inputTokens;
  int outputTokens;
  int thoughtTokens;
  int totalTokens;

  final DateTime startedAt;
  DateTime? completedAt;

  ChatMessage({
    required this.id,
    required this.role,
    this.text = '',
    List<ToolCall>? toolCalls,
    List<String>? attachments,
    this.streaming = false,
    this.error,
    this.thinking,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.thoughtTokens = 0,
    this.totalTokens = 0,
    DateTime? startedAt,
    this.completedAt,
  })  : toolCalls = toolCalls ?? [],
        attachments = attachments ?? [],
        startedAt = startedAt ?? DateTime.now();

  bool get isUser => role == MessageRole.user;

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role.name,
    'text': text,
    'toolCalls': toolCalls.map((t) => t.toJson()).toList(),
    'attachments': attachments,
    'streaming': streaming,
    'error': error,
    'thinking': thinking,
    'inputTokens': inputTokens,
    'outputTokens': outputTokens,
    'thoughtTokens': thoughtTokens,
    'totalTokens': totalTokens,
    'startedAt': startedAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String? ?? '',
      role: MessageRole.values.firstWhere(
            (e) => e.name == json['role'],
        orElse: () => MessageRole.user,
      ),
      text: json['text'] as String? ?? '',
      toolCalls: (json['toolCalls'] as List?)
          ?.map((e) => ToolCall.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      attachments: (json['attachments'] as List?)?.cast<String>(),
      streaming: json['streaming'] as bool? ?? false,
      error: json['error'] as String?,
      thinking: json['thinking'] as String?,
      inputTokens: json['inputTokens'] as int? ?? 0,
      outputTokens: json['outputTokens'] as int? ?? 0,
      thoughtTokens: json['thoughtTokens'] as int? ?? 0,
      totalTokens: json['totalTokens'] as int? ?? 0,
      startedAt: json['startedAt'] != null
          ? DateTime.parse(json['startedAt'])
          : DateTime.now(),
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'])
          : null,
    );
  }
}

class ChatSession {
  final String id;
  String title;
  final DateTime createdAt;
  List<ChatMessage> messages;

  ChatSession({
    required this.id,
    required this.title,
    required this.createdAt,
    List<ChatMessage>? messages,
  }) : messages = messages ?? [];

  int get totalInputTokens => messages.fold(0, (sum, m) => sum + m.inputTokens);
  int get totalOutputTokens => messages.fold(0, (sum, m) => sum + m.outputTokens);
  int get totalThoughtTokens => messages.fold(0, (sum, m) => sum + m.thoughtTokens);
  int get totalTokens => messages.fold(0, (sum, m) => sum + m.totalTokens);

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'messages': messages.map((m) => m.toJson()).toList(),
  };

  factory ChatSession.fromJson(Map<String, dynamic> json) {
    return ChatSession(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Untitled',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      messages: (json['messages'] as List?)
          ?.map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}