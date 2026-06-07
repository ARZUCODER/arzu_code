import 'dart:convert';
import 'package:http/http.dart' as http;

/// One streamed chunk from the Arzu Cloud gateway. The gateway proxies Ollama's
/// `/api/chat` ndjson 1:1, so the shape matches Ollama's stream.
class CloudChunk {
  final String? text;
  final List<dynamic>? toolCalls;
  final int? inputTokens;
  final int? outputTokens;

  CloudChunk({this.text, this.toolCalls, this.inputTokens, this.outputTokens});
}

/// Talks to the Arzu Cloud gateway (`ilm_ai` backend → Ollama on the droplet).
/// Replaces the old localhost Ollama client: no local daemon needed, the model
/// (gemma today, qwen-coder tomorrow) lives entirely on the server.
class ArzuCloudService {
  final String baseUrl;
  final String apiKey;

  ArzuCloudService({required this.baseUrl, required this.apiKey});

  Uri get _chatUri {
    final root = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$root/api/v1/arzuai/chat');
  }

  Stream<CloudChunk> streamChat({
    required String model,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> tools = const [],
    double? temperature,
    bool Function()? isCancelled,
  }) async* {
    if (apiKey.trim().isEmpty) {
      throw Exception('Arzu Cloud key is missing. Add it in Settings → Arzu Cloud.');
    }

    final request = http.Request('POST', _chatUri);
    request.headers['Content-Type'] = 'application/json';
    request.headers['X-Arzu-Key'] = apiKey;
    request.body = jsonEncode({
      'model': model,
      'messages': messages,
      if (tools.isNotEmpty) 'tools': tools,
      if (temperature != null) 'options': {'temperature': temperature},
      'stream': true,
    });

    final client = http.Client();
    try {
      final response = await client.send(request);

      if (response.statusCode != 200) {
        final errorBody = await response.stream.bytesToString();
        throw Exception('Arzu Cloud error (${response.statusCode}): $errorBody');
      }

      await for (final line in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (isCancelled?.call() ?? false) break;
        if (line.trim().isEmpty) continue;

        final data = jsonDecode(line);
        // Surface upstream model errors (e.g. "this model requires a subscription").
        if (data is Map && data['error'] != null) {
          throw Exception(data['error'].toString());
        }
        final message = data['message'];

        yield CloudChunk(
          text: message != null ? (message['content'] as String?) : (data['response'] as String?),
          toolCalls: message != null ? (message['tool_calls'] as List<dynamic>?) : null,
          inputTokens: data['prompt_eval_count'] as int?,
          outputTokens: data['eval_count'] as int?,
        );

        if (data['done'] == true) break;
      }
    } catch (e) {
      throw Exception('Arzu Cloud connection failed: $e');
    } finally {
      client.close();
    }
  }
}
