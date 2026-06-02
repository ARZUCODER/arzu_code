import 'dart:convert';
import 'package:http/http.dart' as http;

class OllamaChunk {
  final String? text;
  final List<dynamic>? toolCalls;
  final int? inputTokens;
  final int? outputTokens;

  OllamaChunk({this.text, this.toolCalls, this.inputTokens, this.outputTokens});
}

class OllamaService {
  static const String baseUrl = 'http://127.0.0.1:11434/api/chat';

  Stream<OllamaChunk> streamChat({
    required String model,
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> tools,
    double? temperature,
    bool Function()? isCancelled,
  }) async* {
    final request = http.Request('POST', Uri.parse(baseUrl));
    request.headers['Content-Type'] = 'application/json';
    request.body = jsonEncode({
      'model': model,
      'messages': messages,
      'tools': tools.isEmpty ? null : tools,
      if (temperature != null) 'options': {'temperature': temperature},
      'stream': true,
    });

    final client = http.Client();
    try {
      final response = await client.send(request);

      if (response.statusCode != 200) {
        final errorBody = await response.stream.bytesToString();
        throw Exception('Ollama API Error (${response.statusCode}): $errorBody');
      }

      await for (final line in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (isCancelled?.call() ?? false) {
          break;
        }
        if (line.isEmpty) continue;

        final data = jsonDecode(line);
        final message = data['message'];

        yield OllamaChunk(
          text: message != null ? (message['content'] as String?) : null,
          toolCalls: message != null ? (message['tool_calls'] as List<dynamic>?) : null,
          inputTokens: data['prompt_eval_count'] as int?,
          outputTokens: data['eval_count'] as int?,
        );

        if (data['done'] == true) {
          break;
        }
      }
    } catch (e) {
      throw Exception('Local Ollama Error: $e');
    } finally {
      client.close();
    }
  }
}