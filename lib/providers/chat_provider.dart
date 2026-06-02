import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/chat_message.dart';
import '../models/tool_call.dart';
import '../services/agent_service.dart';
import '../services/chat_store.dart';
import '../services/rag_service.dart';
import '../services/tool_executor.dart';
import 'config_provider.dart';

final ragServiceProvider = Provider<RagService>((ref) {
  return RagService();
});

final agentServiceProvider = Provider<AgentService>((ref) {
  final perms = ref.watch(permissionsServiceProvider);
  final rag = ref.watch(ragServiceProvider);
  final executor = ToolExecutor(perms, rag);
  return AgentService(executor: executor, perms: perms);
});

final localToolsAvailableProvider = Provider<bool>((ref) {
  final perms = ref.watch(permissionsServiceProvider);
  final rag = ref.watch(ragServiceProvider);
  return ToolExecutor(perms, rag).supportsLocalTools;
});

class PendingApproval {
  final ToolCall toolCall;
  final Completer<bool> completer;
  PendingApproval(this.toolCall, this.completer);
}

class ChatState {
  final List<ChatSession> sessions;
  final String? activeId;
  final bool isRunning;
  final PendingApproval? pendingApproval;
  final int tick;

  const ChatState({
    this.sessions = const [],
    this.activeId,
    this.isRunning = false,
    this.pendingApproval,
    this.tick = 0,
  });

  ChatSession? get active {
    for (final s in sessions) {
      if (s.id == activeId) return s;
    }
    return null;
  }

  List<ChatMessage> get messages => active?.messages ?? const [];

  ChatState copyWith({
    List<ChatSession>? sessions,
    String? activeId,
    bool? isRunning,
    PendingApproval? pendingApproval,
    bool clearPending = false,
    int? tick,
  }) {
    return ChatState(
      sessions: sessions ?? this.sessions,
      activeId: activeId ?? this.activeId,
      isRunning: isRunning ?? this.isRunning,
      pendingApproval: clearPending ? null : (pendingApproval ?? this.pendingApproval),
      tick: tick ?? this.tick,
    );
  }
}

final chatControllerProvider = StateNotifierProvider<ChatController, ChatState>((ref) {
  return ChatController(ref)..init();
});

class ChatController extends StateNotifier<ChatState> {
  final Ref ref;
  final _store = ChatStore();
  bool _cancel = false;
  int _idc = 0;

  ChatController(this.ref) : super(const ChatState());

  Future<void> init() async {
    final loaded = await _store.load();
    if (loaded.isNotEmpty) {
      state = state.copyWith(sessions: loaded, activeId: loaded.first.id);
    }
  }

  String _id() => '${DateTime.now().microsecondsSinceEpoch}_${_idc++}';

  void _bump() {
    state = state.copyWith(tick: state.tick + 1);
    _store.save(state.sessions);
  }

  ChatSession _ensureSession([String? firstText]) {
    if (state.active != null) return state.active!;
    final session = ChatSession(
      id: _id(),
      title: firstText == null || firstText.trim().isEmpty ? 'New session' : _titleFrom(firstText),
      createdAt: DateTime.now(),
    );
    state = state.copyWith(
      sessions: [session, ...state.sessions],
      activeId: session.id,
    );
    _store.save(state.sessions);
    return session;
  }

  String _titleFrom(String text) {
    final t = text.trim().replaceAll('\n', ' ');
    return t.length <= 42 ? t : '${t.substring(0, 42)}…';
  }

  void newSession() {
    if (state.active != null && state.active!.messages.isEmpty) return;
    final session = ChatSession(
      id: _id(),
      title: 'New session',
      createdAt: DateTime.now(),
    );
    state = state.copyWith(
      sessions: [session, ...state.sessions],
      activeId: session.id,
    );
    _store.save(state.sessions);
  }

  void selectSession(String id) => state = state.copyWith(activeId: id);

  void deleteSession(String id) {
    final remaining = state.sessions.where((s) => s.id != id).toList();
    state = state.copyWith(
      sessions: remaining,
      activeId: state.activeId == id ? (remaining.isEmpty ? null : remaining.first.id) : state.activeId,
    );
    _store.save(state.sessions);
  }

  void stop() {
    _cancel = true;
    final pending = state.pendingApproval;
    if (pending != null && !pending.completer.isCompleted) {
      pending.completer.complete(false);
    }
    state = state.copyWith(isRunning: false, clearPending: true);
    _bump();
  }

  void resolveApproval(bool approved, {bool always = false}) {
    final pending = state.pendingApproval;
    if (pending == null) return;
    if (always && approved) {
      ref.read(configControllerProvider.notifier).allowAlways(pending.toolCall.ruleSignature);
    }
    if (!pending.completer.isCompleted) pending.completer.complete(approved);
    state = state.copyWith(clearPending: true);
    _bump();
  }

  Future<void> sendImage(String path) async {
    return send('', attachments: [path]);
  }

  Future<void> send(String text, {List<String> attachments = const []}) async {
    if ((text.trim().isEmpty && attachments.isEmpty) || state.isRunning) return;
    _cancel = false;

    final session = _ensureSession(text);
    if (session.messages.isEmpty && session.title == 'New session') {
      session.title = _titleFrom(text.isEmpty ? 'Image request' : text);
    }

    final userMsg = ChatMessage(
      id: _id(),
      role: MessageRole.user,
      text: text.trim(),
      attachments: List<String>.from(attachments),
    );
    final assistant = ChatMessage(
      id: _id(),
      role: MessageRole.model,
      streaming: true,
      startedAt: DateTime.now(),
    );

    final prior = List<ChatMessage>.from(session.messages);
    session.messages.add(userMsg);
    session.messages.add(assistant);
    state = state.copyWith(isRunning: true);
    _bump();

    final agent = ref.read(agentServiceProvider);
    final config = ref.read(configControllerProvider);

    try {
      await agent.runTurn(
        config: config,
        userText: text.trim(),
        priorMessages: prior,
        assistant: assistant,
        attachments: List<String>.from(attachments),
        onUpdate: _bump,
        isCancelled: () => _cancel,
        requestApproval: (tc) {
          final completer = Completer<bool>();
          state = state.copyWith(pendingApproval: PendingApproval(tc, completer));
          return completer.future;
        },
      );
    } catch (e) {
      assistant.error = _friendlyError(e);
      assistant.thinking = null;
    } finally {
      assistant.streaming = false;
      assistant.completedAt = DateTime.now();
      state = state.copyWith(isRunning: false, clearPending: true);
      _bump();
    }
  }

  String _friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('Failed to fetch') || s.contains('ClientException') || s.contains('SocketException')) {
      return 'Network error reaching AI models. Check your connection. ($s)';
    }
    if (s.contains('not found') || s.contains('404')) {
      return 'Model not available. Check your API Key or custom model id. ($s)';
    }
    if (s.contains('API key not valid')) {
      return 'Invalid Google Generative AI API Key. Please check your Settings.';
    }
    if (s.contains('Rate limit exceeded')) {
      return 'API rate limit exceeded after multiple retries. Please wait a moment.';
    }
    return s;
  }
}