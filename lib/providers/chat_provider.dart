import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_config.dart';
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
  // Per-session so multiple sessions (each with its own model) can run at once.
  final Set<String> runningSessionIds;
  final Map<String, PendingApproval> pendingApprovals;
  final int tick;

  const ChatState({
    this.sessions = const [],
    this.activeId,
    this.runningSessionIds = const {},
    this.pendingApprovals = const {},
    this.tick = 0,
  });

  ChatSession? get active {
    for (final s in sessions) {
      if (s.id == activeId) return s;
    }
    return null;
  }

  List<ChatMessage> get messages => active?.messages ?? const [];

  // Convenience views for the *active* session (composer + permission banner).
  bool get isRunning => activeId != null && runningSessionIds.contains(activeId);
  bool isSessionRunning(String id) => runningSessionIds.contains(id);
  PendingApproval? get pendingApproval => activeId == null ? null : pendingApprovals[activeId];

  ChatState copyWith({
    List<ChatSession>? sessions,
    String? activeId,
    Set<String>? runningSessionIds,
    Map<String, PendingApproval>? pendingApprovals,
    int? tick,
  }) {
    return ChatState(
      sessions: sessions ?? this.sessions,
      activeId: activeId ?? this.activeId,
      runningSessionIds: runningSessionIds ?? this.runningSessionIds,
      pendingApprovals: pendingApprovals ?? this.pendingApprovals,
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
  final Set<String> _cancelled = {}; // session ids the user asked to stop
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

  void stop([String? sessionId]) {
    final sid = sessionId ?? state.activeId;
    if (sid == null) return;
    _cancelled.add(sid);
    final pending = state.pendingApprovals[sid];
    if (pending != null && !pending.completer.isCompleted) pending.completer.complete(false);
    state = state.copyWith(
      runningSessionIds: {...state.runningSessionIds}..remove(sid),
      pendingApprovals: {...state.pendingApprovals}..remove(sid),
    );
    _bump();
  }

  void resolveApproval(bool approved, {bool always = false}) {
    final sid = state.activeId;
    if (sid == null) return;
    final pending = state.pendingApprovals[sid];
    if (pending == null) return;
    // Folder-access grant: add the requested folder to the allowed list.
    if (approved && pending.toolCall.name == '__grant_folder') {
      final folder = pending.toolCall.args['folder'] as String?;
      if (folder != null && folder.isNotEmpty) {
        ref.read(configControllerProvider.notifier).addFolder(folder);
      }
    }
    if (always && approved) {
      ref.read(configControllerProvider.notifier).allowAlways(pending.toolCall.ruleSignature);
    }
    if (!pending.completer.isCompleted) pending.completer.complete(approved);
    state = state.copyWith(pendingApprovals: {...state.pendingApprovals}..remove(sid));
    _bump();
  }

  Future<void> sendImage(String path) async {
    return send('', attachments: [path]);
  }

  Future<void> send(String text, {List<String> attachments = const []}) async {
    if (text.trim().isEmpty && attachments.isEmpty) return;

    final session = _ensureSession(text);
    final sid = session.id;
    if (state.isSessionRunning(sid)) return; // this session is busy; other sessions may still run
    _cancelled.remove(sid);

    final config = ref.read(configControllerProvider);

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
      model: config.activeModel,
      streaming: true,
      startedAt: DateTime.now(),
    );

    final prior = List<ChatMessage>.from(session.messages);
    final isFirstTurn = prior.isEmpty;
    session.messages.add(userMsg);
    session.messages.add(assistant);
    state = state.copyWith(runningSessionIds: {...state.runningSessionIds, sid});
    _bump();

    final agent = ref.read(agentServiceProvider);

    try {
      await agent.runTurn(
        config: config,
        userText: text.trim(),
        priorMessages: prior,
        assistant: assistant,
        attachments: List<String>.from(attachments),
        onUpdate: _bump,
        isCancelled: () => _cancelled.contains(sid),
        requestApproval: (tc) {
          final completer = Completer<bool>();
          state = state.copyWith(pendingApprovals: {...state.pendingApprovals, sid: PendingApproval(tc, completer)});
          return completer.future;
        },
      );
      // Give the session a smart, short, AI-generated title after the first turn.
      if (isFirstTurn && !_cancelled.contains(sid)) {
        unawaited(_maybeGenerateTitle(session, config, text.trim()));
      }
    } catch (e) {
      assistant.error = _friendlyError(e);
      assistant.thinking = null;
    } finally {
      assistant.streaming = false;
      assistant.completedAt = DateTime.now();
      state = state.copyWith(
        runningSessionIds: {...state.runningSessionIds}..remove(sid),
        pendingApprovals: {...state.pendingApprovals}..remove(sid),
      );
      _bump();
    }
  }

  Future<void> _maybeGenerateTitle(ChatSession session, AppConfig config, String firstUserMsg) async {
    try {
      final title = await ref.read(agentServiceProvider).quickTitle(config, firstUserMsg);
      if (title != null && title.trim().isNotEmpty) {
        session.title = title.trim();
        _bump();
      }
    } catch (_) {/* keep the fallback title */}
  }

  String _friendlyError(Object e) {
    final s = e.toString();
    final low = s.toLowerCase();
    if (low.contains('resource exhausted') || low.contains('resource_exhausted')) {
      return '⏳ Vertex kvotasi tugadi (429 — Resource exhausted). Gemini 3.1 Pro PREVIEW model kvotasi past. '
          'Biroz kuting, yoki barqaror "Gemini 2.5 Pro (Vertex)"ga o\'ting (kvotasi yuqori).';
    }
    if (low.contains('usage limit') || low.contains('429') || (low.contains('upgrade') && low.contains('ollama'))) {
      return '⏳ Ollama Cloud bepul limiti tugadi (429). Biroz kutib qayta urinib ko\'ring, '
          'yoki ollama.com/upgrade orqali limitni oshiring. Ayni damda Gemini 2.5 Pro (Vertex) '
          'yoki gemma4 ga o\'tib ishlashda davom etishingiz mumkin.';
    }
    if (s.contains('requires a subscription')) {
      return 'Bu model Ollama obunasini talab qiladi (ollama.com/upgrade). Boshqa modelni tanlang.';
    }
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