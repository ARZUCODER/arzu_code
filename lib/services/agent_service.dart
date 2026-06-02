import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_ai/firebase_ai.dart' as fbai;
import 'package:google_generative_ai/google_generative_ai.dart' as gai;
import 'package:path/path.dart' as p;

import '../models/app_config.dart';
import '../models/chat_message.dart';
import '../models/tool_call.dart';
import 'environment_service.dart';
import 'ollama_service.dart';
import 'permissions_service.dart';
import 'tool_executor.dart';
import 'tool_registry.dart';

class AgentService {
  final ToolExecutor executor;
  final PermissionsService perms;
  final OllamaService ollama = OllamaService();

  static const int maxIterations = 15;

  AgentService({required this.executor, required this.perms});

  int _counter = 0;
  String _id() => '${DateTime.now().microsecondsSinceEpoch}_${_counter++}';

  String _getSystemPrompt(AppConfig config) {
    String prompt = kSystemPrompt;
    if (EnvironmentService.promptBlock != null) prompt += EnvironmentService.promptBlock!;
    if (config.allowedFolders.isNotEmpty) {
      prompt += '\n\n# CRITICAL: ALLOWED WORKSPACE PATHS\n';
      for (final f in config.allowedFolders) {
        prompt += '- $f\n';
      }
    }
    return prompt;
  }

  Future<void> runTurn({
    required AppConfig config,
    required String userText,
    required List<ChatMessage> priorMessages,
    required ChatMessage assistant,
    required void Function() onUpdate,
    required Future<bool> Function(ToolCall) requestApproval,
    bool Function()? isCancelled,
    List<String> attachments = const [],
  }) async {
    if (config.useLocalModel) {
      await _runOllamaTurn(config, userText, priorMessages, assistant, onUpdate, requestApproval, isCancelled);
      return;
    }

    String engine = config.customModelEngines[config.activeModel] ?? (kGoogleAiModels.contains(config.activeModel) ? 'google' : 'vertex');

    if (engine == 'google') {
      if (config.googleApiKey.trim().isEmpty) {
        assistant.error = 'Google Generative AI requires an API Key. Please add it in Settings.';
        onUpdate();
        return;
      }
      await _runGoogleAiTurn(config, userText, priorMessages, assistant, onUpdate, requestApproval, isCancelled, attachments);
    } else {
      await _runVertexTurn(config, userText, priorMessages, assistant, onUpdate, requestApproval, isCancelled, attachments);
    }
  }

  String _mimeForImage(String path) {
    switch (p.extension(path).toLowerCase()) {
      case '.png': return 'image/png';
      case '.jpg': case '.jpeg': return 'image/jpeg';
      case '.gif': return 'image/gif';
      case '.webp': return 'image/webp';
      default: return 'image/png';
    }
  }

  void _extractToolCallFromJson(ChatMessage assistant, List<dynamic> currentToolCalls) {
    if (currentToolCalls.isNotEmpty) return;
    String text = assistant.text.trim();
    if (text.isEmpty) return;
    if (text.contains('```json')) text = text.split('```json').last.split('```').first.trim();
    else if (text.contains('```')) text = text.split('```').last.split('```').first.trim();
    if (text.contains('"name"') && (text.contains('"arguments"') || text.contains('"args"'))) {
      String arrayText = text.replaceAll(RegExp(r'\}\s*\{'), '},{');
      if (!arrayText.startsWith('[')) arrayText = '[$arrayText]';
      if (!arrayText.endsWith(']')) arrayText = '$arrayText]';
      try {
        final parsedList = jsonDecode(arrayText);
        if (parsedList is List) {
          bool found = false;
          for (final item in parsedList) {
            if (item is Map && item.containsKey('name')) {
              currentToolCalls.add({'function': {'name': item['name'], 'arguments': item['arguments'] ?? item['args'] ?? {}}});
              found = true;
            }
          }
          if (found) assistant.text = '';
        }
      } catch (_) {}
    }
  }

  Future<void> _runOllamaTurn(AppConfig config, String userText, List<ChatMessage> priorMessages, ChatMessage assistant, void Function() onUpdate, Future<bool> Function(ToolCall) requestApproval, bool Function()? isCancelled) async {
    final history = <Map<String, dynamic>>[{'role': 'system', 'content': _getSystemPrompt(config)}];
    for (final m in priorMessages) {
      if (m.text.trim().isNotEmpty) history.add({'role': m.role == MessageRole.user ? 'user' : 'assistant', 'content': m.text});
      if (m.toolCalls.isNotEmpty) {
        history.add({'role': 'assistant', 'content': '', 'tool_calls': m.toolCalls.map((tc) => {'type': 'function', 'function': {'name': tc.name, 'arguments': tc.args}}).toList()});
        for (final tc in m.toolCalls) {
          if (tc.result != null) history.add({'role': 'tool', 'name': tc.name, 'content': tc.result!.output ?? tc.result!.error ?? ''});
        }
      }
    }
    history.add({'role': 'user', 'content': userText});
    final tools = buildOllamaTools();

    assistant.thinking = 'Thinking locally...';
    onUpdate();
    var iterations = 0;
    while (iterations++ < maxIterations) {
      if (isCancelled?.call() ?? false) { assistant.error = 'Stopped by user.'; onUpdate(); return; }
      List<dynamic> currentToolCalls = [];
      try {
        await for (final chunk in ollama.streamChat(model: config.localModel, messages: history, tools: tools, temperature: config.temperature, isCancelled: isCancelled)) {
          if (isCancelled?.call() ?? false) return;
          if (chunk.text != null && chunk.text!.isNotEmpty) {
            assistant.text += chunk.text!;
            onUpdate();
          }
          if (chunk.toolCalls != null) currentToolCalls.addAll(chunk.toolCalls!);

          if (chunk.inputTokens != null) assistant.inputTokens += chunk.inputTokens!;
          if (chunk.outputTokens != null) {
            assistant.outputTokens += chunk.outputTokens!;
            assistant.totalTokens += (chunk.inputTokens ?? 0) + chunk.outputTokens!;
            onUpdate();
          }
        }
      } catch (e) {
        assistant.error = e.toString(); assistant.thinking = null; onUpdate(); return;
      }
      _extractToolCallFromJson(assistant, currentToolCalls);

      if (currentToolCalls.isEmpty) break;

      history.add({'role': 'assistant', 'content': '', 'tool_calls': currentToolCalls});
      for (final call in currentToolCalls) {
        if (isCancelled?.call() ?? false) break;
        final func = call['function'];
        final tc = ToolCall(id: _id(), name: func['name'], args: Map<String, Object?>.from(func['arguments']), startedAt: DateTime.now());
        assistant.toolCalls.add(tc); assistant.thinking = tc.summary; onUpdate();

        bool approved = !(executor.supportsLocalTools && tc.isMutating && perms.requiresApproval(tc.name, tc.ruleSignature)) || await (() { tc.status = ToolStatus.pending; onUpdate(); return requestApproval(tc); })();
        if (!approved) {
          tc.status = ToolStatus.denied; tc.completedAt = DateTime.now(); tc.result = const ToolResult(ok: false, error: 'User denied.'); onUpdate();
          history.add({'role': 'tool', 'name': tc.name, 'content': 'User denied.'});
          continue;
        }
        tc.status = ToolStatus.running; onUpdate();
        final rawResult = await executor.invoke(tc.name, tc.args, isCancelled: isCancelled);
        tc.result = ToolResult(ok: rawResult.ok, error: rawResult.error, output: rawResult.output);
        tc.status = tc.result!.ok ? ToolStatus.done : ToolStatus.error; tc.completedAt = DateTime.now(); onUpdate();
        history.add({'role': 'tool', 'name': tc.name, 'content': tc.result!.output ?? tc.result!.error ?? ''});
      }
      assistant.thinking = 'Thinking locally...'; onUpdate();
    }
    assistant.thinking = null; onUpdate();
  }

  Future<void> _runGoogleAiTurn(AppConfig config, String userText, List<ChatMessage> prior, ChatMessage assistant, void Function() onUpdate, Future<bool> Function(ToolCall) requestApproval, bool Function()? isCancelled, List<String> attachments) async {
    final history = <gai.Content>[];

    // TOKEN SAVER: Eski chat tarixidan asboblarning katta loglarini yashiramiz!
    for (final m in prior) {
      if (m.text.trim().isEmpty && m.toolCalls.isEmpty) continue;

      if (m.role == MessageRole.user) {
        history.add(gai.Content.text(m.text));
      } else if (m.role == MessageRole.model) {
        String content = m.text;
        if (m.toolCalls.isNotEmpty) {
          final summaries = m.toolCalls.map((tc) => "[Tool used: ${tc.name}]").join(', ');
          content += "\n\n$summaries";
        }
        if (content.trim().isNotEmpty) {
          history.add(gai.Content.model([gai.TextPart(content.trim())]));
        }
      }
    }

    final parts = <gai.Part>[gai.TextPart(userText)];
    for (final path in attachments) {
      try { final file = File(path); if (file.existsSync()) parts.add(gai.DataPart(_mimeForImage(path), file.readAsBytesSync())); } catch (_) {}
    }
    history.add(gai.Content('user', parts));

    final model = gai.GenerativeModel(
      model: config.activeModel,
      apiKey: config.googleApiKey,
      tools: [gai.Tool(functionDeclarations: buildGoogleAiTools())],
      systemInstruction: gai.Content.system(_getSystemPrompt(config)),
      generationConfig: gai.GenerationConfig(temperature: config.temperature),
    );

    assistant.thinking = 'Thinking...'; onUpdate();

    var iterations = 0;

    while (iterations++ < maxIterations) {
      if (isCancelled?.call() ?? false) { assistant.error = 'Stopped.'; onUpdate(); return; }

      gai.GenerateContentResponse? response;
      try {
        response = await model.generateContent(history);

        final u = response.usageMetadata;
        if (u != null) {
          assistant.inputTokens += u.promptTokenCount ?? 0;
          assistant.outputTokens += u.candidatesTokenCount ?? 0;
          assistant.totalTokens += u.totalTokenCount ?? 0;
          final thought = (u.totalTokenCount ?? 0) - ((u.promptTokenCount ?? 0) + (u.candidatesTokenCount ?? 0));
          if (thought > 0) assistant.thoughtTokens += thought;
          onUpdate();
        }
      } catch (e) {
        assistant.error = e.toString(); assistant.thinking = null; onUpdate(); return;
      }

      if (response.text != null && response.text!.isNotEmpty) {
        if (assistant.text.isNotEmpty) assistant.text += '\n\n';
        assistant.text += response.text!;
        onUpdate();
      }

      final calls = response.functionCalls.toList();
      if (calls.isEmpty) break; // AI o'zi hamma ishni qilib tugatdi. O'chadi.

      final executedTools = <ToolCall>[];
      for (final call in calls) {
        if (isCancelled?.call() ?? false) break;
        final tc = ToolCall(id: _id(), name: call.name, args: Map<String, Object?>.from(call.args), startedAt: DateTime.now());
        assistant.toolCalls.add(tc); assistant.thinking = tc.summary; onUpdate();
        executedTools.add(tc);

        bool approved = !(executor.supportsLocalTools && tc.isMutating && perms.requiresApproval(tc.name, tc.ruleSignature)) || await (() { tc.status = ToolStatus.pending; onUpdate(); return requestApproval(tc); })();
        if (!approved) {
          tc.status = ToolStatus.denied; tc.completedAt = DateTime.now(); tc.result = const ToolResult(ok: false, error: 'Denied.'); onUpdate();
          continue;
        }
        tc.status = ToolStatus.running; onUpdate();
        final raw = await executor.invoke(tc.name, tc.args, isCancelled: isCancelled);
        tc.result = ToolResult(ok: raw.ok, error: raw.error, output: raw.output);
        tc.status = tc.result!.ok ? ToolStatus.done : ToolStatus.error; tc.completedAt = DateTime.now(); onUpdate();
      }

      assistant.thinking = 'Thinking...'; onUpdate();

      String modelText = response.text ?? '';
      history.add(gai.Content.model([
        if (modelText.isNotEmpty) gai.TextPart(modelText),
        ...calls.map((c) => gai.FunctionCall(c.name, c.args))
      ]));

      history.add(gai.Content('function', [
        ...executedTools.map((tc) => gai.FunctionResponse(tc.name, {
          'ok': tc.result!.ok,
          if (tc.result!.output != null) 'output': tc.result!.output,
          if (tc.result!.error != null) 'error': tc.result!.error
        }))
      ]));
    }
    assistant.thinking = null; onUpdate();
  }

  Future<void> _runVertexTurn(AppConfig config, String userText, List<ChatMessage> prior, ChatMessage assistant, void Function() onUpdate, Future<bool> Function(ToolCall) requestApproval, bool Function()? isCancelled, List<String> attachments) async {
    final history = <fbai.Content>[];

    // TOKEN SAVER
    for (final m in prior) {
      if (m.text.trim().isEmpty && m.toolCalls.isEmpty) continue;

      if (m.role == MessageRole.user) {
        history.add(fbai.Content.text(m.text));
      } else if (m.role == MessageRole.model) {
        String content = m.text;
        if (m.toolCalls.isNotEmpty) {
          final summaries = m.toolCalls.map((tc) => "[Tool used: ${tc.name}]").join(', ');
          content += "\n\n$summaries";
        }
        if (content.trim().isNotEmpty) {
          history.add(fbai.Content.model([fbai.TextPart(content.trim())]));
        }
      }
    }

    final parts = <fbai.Part>[fbai.TextPart(userText)];
    for (final path in attachments) {
      try { final file = File(path); if (file.existsSync()) parts.add(fbai.InlineDataPart(_mimeForImage(path), file.readAsBytesSync())); } catch (_) {}
    }
    history.add(fbai.Content('user', parts));

    final model = fbai.FirebaseAI.vertexAI().generativeModel(
      model: config.activeModel,
      tools: [fbai.Tool.functionDeclarations(buildVertexTools())],
      systemInstruction: fbai.Content.system(_getSystemPrompt(config)),
      generationConfig: fbai.GenerationConfig(temperature: config.temperature),
    );

    assistant.thinking = 'Thinking...'; onUpdate();

    var iterations = 0;

    while (iterations++ < maxIterations) {
      if (isCancelled?.call() ?? false) { assistant.error = 'Stopped.'; onUpdate(); return; }

      fbai.GenerateContentResponse? response;
      try {
        response = await model.generateContent(history);

        final u = response.usageMetadata;
        if (u != null) {
          assistant.inputTokens += u.promptTokenCount ?? 0;
          assistant.outputTokens += u.candidatesTokenCount ?? 0;
          assistant.totalTokens += u.totalTokenCount ?? 0;
          final thought = (u.totalTokenCount ?? 0) - ((u.promptTokenCount ?? 0) + (u.candidatesTokenCount ?? 0));
          if (thought > 0) assistant.thoughtTokens += thought;
          onUpdate();
        }
      } catch (e) {
        assistant.error = e.toString(); assistant.thinking = null; onUpdate(); return;
      }

      if (response.text != null && response.text!.isNotEmpty) {
        if (assistant.text.isNotEmpty) assistant.text += '\n\n';
        assistant.text += response.text!;
        onUpdate();
      }

      final calls = response.functionCalls.toList();
      if (calls.isEmpty) break; // AI ishlarni bitirsa toxtaydi

      final executedTools = <ToolCall>[];
      for (final call in calls) {
        if (isCancelled?.call() ?? false) break;
        final tc = ToolCall(id: _id(), name: call.name, args: Map<String, Object?>.from(call.args), startedAt: DateTime.now());
        assistant.toolCalls.add(tc); assistant.thinking = tc.summary; onUpdate();
        executedTools.add(tc);

        bool approved = !(executor.supportsLocalTools && tc.isMutating && perms.requiresApproval(tc.name, tc.ruleSignature)) || await (() { tc.status = ToolStatus.pending; onUpdate(); return requestApproval(tc); })();
        if (!approved) {
          tc.status = ToolStatus.denied; tc.completedAt = DateTime.now(); tc.result = const ToolResult(ok: false, error: 'Denied.'); onUpdate();
          continue;
        }
        tc.status = ToolStatus.running; onUpdate();
        final raw = await executor.invoke(tc.name, tc.args, isCancelled: isCancelled);
        tc.result = ToolResult(ok: raw.ok, error: raw.error, output: raw.output);
        tc.status = tc.result!.ok ? ToolStatus.done : ToolStatus.error; tc.completedAt = DateTime.now(); onUpdate();
      }

      assistant.thinking = 'Thinking...'; onUpdate();

      String modelText = response.text ?? '';
      history.add(fbai.Content.model([
        if (modelText.isNotEmpty) fbai.TextPart(modelText),
        ...calls.map((c) => fbai.FunctionCall(c.name, c.args))
      ]));

      history.add(fbai.Content('function', [
        ...executedTools.map((tc) => fbai.FunctionResponse(tc.name, {
          'ok': tc.result!.ok,
          if (tc.result!.output != null) 'output': tc.result!.output,
          if (tc.result!.error != null) 'error': tc.result!.error
        }))
      ]));
    }
    assistant.thinking = null; onUpdate();
  }
}