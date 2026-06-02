import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../firebase_options.dart';
import '../models/app_config.dart';

class DocumentChunk {
  final String filePath;
  final String content;
  final List<double> embedding;
  final int lastModified;

  DocumentChunk({
    required this.filePath,
    required this.content,
    required this.embedding,
    required this.lastModified,
  });

  Map<String, dynamic> toJson() => {
    'filePath': filePath,
    'content': content,
    'embedding': embedding,
    'lastModified': lastModified,
  };

  factory DocumentChunk.fromJson(Map<String, dynamic> json) => DocumentChunk(
    filePath: json['filePath'] as String,
    content: json['content'] as String,
    embedding: (json['embedding'] as List).cast<double>(),
    lastModified: json['lastModified'] as int,
  );
}

class _FileEntry {
  final File file;
  final String relativePath;
  final int lastModified;
  _FileEntry(this.file, this.relativePath, this.lastModified);
}

class _PendingChunk {
  final String text;
  final String filePath;
  final int lastModified;
  _PendingChunk(this.text, this.filePath, this.lastModified);
}

class _SyncResult {
  final List<DocumentChunk> chunks;
  final int filesFound;
  final int newChunks;
  final int embedded;
  final int failed;
  final bool authFailed;
  _SyncResult({
    required this.chunks,
    required this.filesFound,
    required this.newChunks,
    required this.embedded,
    required this.failed,
    required this.authFailed,
  });
}

class RagService {
  static const String _indexFileName = '.arzu_rag_index.json';
  static const int _maxChunkSize = 2500;
  static const int _maxFileBytes = 400 * 1024;
  static const int _maxFiles = 1500;
  static const int _maxNewChunks = 600;
  static const int _batchSize = 50;

  static const String _location = 'us-central1';
  static const String _scope = 'https://www.googleapis.com/auth/cloud-platform';
  static const String _embeddingModel = 'text-embedding-004';

  AutoRefreshingAuthClient? _authClient;
  String? _authError;

  static const _validExtensions = {
    '.dart', '.go', '.js', '.ts', '.tsx', '.jsx', '.py', '.java', '.kt',
    '.swift', '.rs', '.rb', '.php', '.c', '.cpp', '.cc', '.h', '.hpp', '.cs',
    '.html', '.css', '.scss', '.vue', '.json', '.yaml', '.yml', '.toml',
    '.xml', '.md', '.txt', '.sh', '.sql', '.gradle',
  };

  static const _ignoredDirs = {
    '.git', 'node_modules', 'build', 'dist', 'out', '.dart_tool', '.pub-cache',
    'ios', 'android', 'macos', 'windows', 'linux', 'web', '.idea', '.gradle',
    'Pods', '.symlinks', 'ephemeral', '.next', '.nuxt', 'vendor', 'target',
    'bin', 'obj', 'DerivedData', '__pycache__', '.venv', 'venv',
    '.mypy_cache', '.pytest_cache', 'coverage', '.fvm',
  };

  Future<List<String>> semanticSearch(
      String workspace,
      String query, {
        int topK = 5,
        AppConfig? config,
      }) async {
    final indexFile = File(p.join(workspace, _indexFileName));
    List<DocumentChunk> existing = [];
    if (indexFile.existsSync()) {
      try {
        final list = jsonDecode(await indexFile.readAsString()) as List;
        existing = list.map((e) => DocumentChunk.fromJson(e)).toList();
      } catch (_) {
        existing = [];
      }
    }

    final sync = await _syncIndex(workspace, existing, config);

    if (sync.filesFound == 0) {
      return ['No indexable source files were found in "$workspace". Make sure the folder contains code and is an allowed folder.'];
    }

    final indexed = sync.chunks.where((c) => c.embedding.isNotEmpty).toList();

    if (indexed.isNotEmpty) {
      final qv = await _embedQuery(query, config);
      if (qv != null) {
        final scored = indexed
            .map((c) => MapEntry(c, _cosineSimilarity(qv, c.embedding)))
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final top = scored.take(topK).map((e) =>
        '--- FILE: ${e.key.filePath} (Similarity: ${(e.value * 100).toStringAsFixed(1)}%) ---\n${e.key.content}');
        return [
          '[RAG: ${sync.filesFound} files, ${indexed.length} chunks indexed · Vertex text-embedding-004]',
          ...top,
        ];
      }
    }

    final lexical = _lexicalSearch(workspace, query, topK);
    final reason = sync.authFailed
        ? 'Vertex embeddings unavailable (${_authError ?? "no credentials"}). Add a service-account JSON at ~/.arzu_code/service_account.json or run `gcloud auth application-default login`. Showing keyword matches instead.'
        : 'Semantic ranking unavailable right now. Showing keyword matches instead.';
    return ['[RAG fallback: $reason]', ...lexical];
  }

  Future<_SyncResult> _syncIndex(
      String workspace,
      List<DocumentChunk> existing,
      AppConfig? config,
      ) async {
    if (!Directory(workspace).existsSync()) {
      return _SyncResult(chunks: const [], filesFound: 0, newChunks: 0, embedded: 0, failed: 0, authFailed: false);
    }

    final existingByPath = <String, List<DocumentChunk>>{};
    for (final c in existing) {
      existingByPath.putIfAbsent(c.filePath, () => []).add(c);
    }

    final files = _collectFiles(workspace);
    final result = <DocumentChunk>[];
    final pending = <_PendingChunk>[];

    for (final f in files) {
      final cached = existingByPath[f.relativePath];
      if (cached != null && cached.isNotEmpty && cached.first.lastModified == f.lastModified) {
        result.addAll(cached);
        continue;
      }
      if (pending.length >= _maxNewChunks) continue;
      String content;
      try {
        content = await f.file.readAsString();
      } catch (_) {
        continue;
      }
      if (content.trim().isEmpty) continue;
      if (_looksMinified(content)) continue;

      for (final chunk in _smartAstChunk(content, p.extension(f.relativePath))) {
        if (pending.length >= _maxNewChunks) break;
        pending.add(_PendingChunk(chunk, f.relativePath, f.lastModified));
      }
    }

    var embedded = 0;
    var failed = 0;
    var authFailed = false;

    if (pending.isNotEmpty) {
      final client = await _ensureClient(config);
      if (client == null) {
        authFailed = true;
      } else {
        for (var i = 0; i < pending.length; i += _batchSize) {
          final slice = pending.sublist(i, min(i + _batchSize, pending.length));
          final vectors = await _embedBatch(client, slice.map((e) => e.text).toList(), 'RETRIEVAL_DOCUMENT');
          for (var j = 0; j < slice.length; j++) {
            final v = (j < vectors.length) ? vectors[j] : null;
            if (v != null && v.isNotEmpty) {
              result.add(DocumentChunk(
                filePath: slice[j].filePath,
                content: slice[j].text,
                embedding: v,
                lastModified: slice[j].lastModified,
              ));
              embedded++;
            } else {
              failed++;
            }
          }
        }
      }
    }

    if (result.any((c) => c.embedding.isNotEmpty)) {
      try {
        await File(p.join(workspace, _indexFileName)).writeAsString(
            jsonEncode(result.where((c) => c.embedding.isNotEmpty).map((e) => e.toJson()).toList()));
      } catch (_) {}
    }

    return _SyncResult(
      chunks: result,
      filesFound: files.length,
      newChunks: pending.length,
      embedded: embedded,
      failed: failed,
      authFailed: authFailed,
    );
  }

  List<_FileEntry> _collectFiles(String workspace) {
    final out = <_FileEntry>[];

    void walk(Directory dir) {
      if (out.length >= _maxFiles) return;
      List<FileSystemEntity> entries;
      try {
        entries = dir.listSync(followLinks: false);
      } catch (_) {
        return;
      }
      for (final e in entries) {
        if (out.length >= _maxFiles) return;
        final base = p.basename(e.path);
        if (e is Directory) {
          if (_ignoredDirs.contains(base) || base.startsWith('.')) continue;
          walk(e);
        } else if (e is File) {
          if (base == _indexFileName) continue;
          final ext = p.extension(base).toLowerCase();
          if (!_validExtensions.contains(ext)) continue;
          FileStat st;
          try {
            st = e.statSync();
          } catch (_) {
            continue;
          }
          if (st.size > _maxFileBytes || st.size == 0) continue;
          out.add(_FileEntry(e, p.relative(e.path, from: workspace), st.modified.millisecondsSinceEpoch));
        }
      }
    }

    walk(Directory(workspace));
    return out;
  }

  bool _looksMinified(String content) {
    final firstNl = content.indexOf('\n');
    final firstLineLen = firstNl == -1 ? content.length : firstNl;
    return firstLineLen > 5000;
  }

  String get _projectId => DefaultFirebaseOptions.currentPlatform.projectId;

  String get _predictUrl => 'https://$_location-aiplatform.googleapis.com/v1/projects/$_projectId/locations/$_location/publishers/google/models/$_embeddingModel:predict';

  Future<AutoRefreshingAuthClient?> _ensureClient(AppConfig? config) async {
    if (_authClient != null) return _authClient;

    final candidates = <String>[
      if (config != null && config.serviceAccountPath.trim().isNotEmpty) config.serviceAccountPath.trim(),
      p.join(Platform.environment['HOME'] ?? '', '.arzu_code', 'service_account.json'),
    ];

    for (final path in candidates) {
      try {
        final file = File(path);
        if (!file.existsSync()) continue;
        final creds = ServiceAccountCredentials.fromJson(jsonDecode(await file.readAsString()));
        _authClient = await clientViaServiceAccount(creds, [_scope]);
        _authError = null;
        return _authClient;
      } catch (e) {
        _authError = 'service account error: $e';
      }
    }

    try {
      _authClient = await clientViaApplicationDefaultCredentials(scopes: [_scope]);
      _authError = null;
      return _authClient;
    } catch (e) {
      _authError = _authError ?? 'no service account JSON found and Application Default Credentials are not configured';
      return null;
    }
  }

  Future<List<double>?> _embedQuery(String text, AppConfig? config) async {
    final client = await _ensureClient(config);
    if (client == null) return null;
    final r = await _embedBatch(client, [text], 'RETRIEVAL_QUERY');
    return r.isNotEmpty ? r.first : null;
  }

  Future<List<List<double>?>> _embedBatch(http.Client client, List<String> texts, String taskType) async {
    final body = jsonEncode({
      'instances': [
        for (final t in texts) {'task_type': taskType, 'content': t},
      ],
    });

    var backoff = 600;
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        final resp = await client.post(Uri.parse(_predictUrl), headers: {'Content-Type': 'application/json'}, body: body).timeout(const Duration(seconds: 30));

        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body) as Map<String, dynamic>;
          final preds = (data['predictions'] as List?) ?? const [];
          final out = <List<double>?>[];
          for (final pred in preds) {
            final values = (pred as Map)['embeddings']?['values'] as List?;
            out.add(values?.map((e) => (e as num).toDouble()).toList());
          }
          while (out.length < texts.length) out.add(null);
          return out;
        }

        if ([429, 500, 502, 503, 504].contains(resp.statusCode) && attempt < 3) {
          await Future.delayed(Duration(milliseconds: backoff));
          backoff *= 2;
          continue;
        }
        _authError = 'Vertex predict HTTP ${resp.statusCode}';
        return List<List<double>?>.filled(texts.length, null);
      } catch (e) {
        if (attempt < 3) {
          await Future.delayed(Duration(milliseconds: backoff));
          backoff *= 2;
          continue;
        }
        _authError = 'Vertex predict error: $e';
        return List<List<double>?>.filled(texts.length, null);
      }
    }
    return List<List<double>?>.filled(texts.length, null);
  }

  List<String> _lexicalSearch(String workspace, String query, int topK) {
    final terms = query.toLowerCase().split(RegExp(r'[^a-z0-9_]+')).where((t) => t.length > 2).toSet();
    if (terms.isEmpty) return ['No searchable terms in query.'];

    final scored = <MapEntry<String, double>>[];
    for (final f in _collectFiles(workspace)) {
      String content;
      try { content = f.file.readAsStringSync(); } catch (_) { continue; }
      final lower = content.toLowerCase();
      final nameLower = f.relativePath.toLowerCase();
      double score = 0;
      for (final t in terms) {
        final inName = nameLower.contains(t);
        final count = t.allMatches(lower).length;
        score += count.toDouble() + (inName ? 5 : 0);
      }
      if (score > 0) {
        final snippet = content.length > 800 ? content.substring(0, 800) : content;
        scored.add(MapEntry('--- FILE: ${f.relativePath} (keyword score: ${score.toStringAsFixed(0)}) ---\n$snippet', score));
      }
    }
    scored.sort((a, b) => b.value.compareTo(a.value));
    if (scored.isEmpty) return ['No keyword matches for "$query" in the workspace.'];
    return scored.take(topK).map((e) => e.key).toList();
  }

  List<String> _smartAstChunk(String text, String extension) {
    final cFamily = {'.dart', '.go', '.js', '.ts', '.java', '.c', '.cpp', '.cs', '.php', '.css'};
    if (cFamily.contains(extension)) return _chunkByScopes(text);
    else if (extension == '.py') return _chunkByIndentation(text);
    else return _fallbackChunkText(text);
  }

  List<String> _chunkByScopes(String text) {
    List<String> chunks = [];
    StringBuffer currentChunk = StringBuffer();
    int braceDepth = 0;
    bool inString = false;
    String stringChar = '';
    bool inComment = false;
    bool inMultilineComment = false;

    for (int i = 0; i < text.length; i++) {
      String char = text[i];
      String nextChar = i + 1 < text.length ? text[i + 1] : '';
      currentChunk.write(char);

      if (!inComment && !inMultilineComment) {
        if (char == '"' || char == "'" || char == '`') {
          if (!inString) {
            inString = true;
            stringChar = char;
          } else if (stringChar == char) {
            int backslashCount = 0;
            for (int j = i - 1; j >= 0; j--) {
              if (text[j] == '\\') backslashCount++;
              else break;
            }
            if (backslashCount % 2 == 0) inString = false;
          }
        }
      }

      if (!inString && !inMultilineComment && char == '/' && nextChar == '/') inComment = true;
      if (inComment && (char == '\n' || char == '\r')) inComment = false;

      if (!inString && !inComment && char == '/' && nextChar == '*') inMultilineComment = true;
      if (inMultilineComment && char == '*' && nextChar == '/') {
        inMultilineComment = false;
        currentChunk.write('/');
        i++;
        continue;
      }

      if (!inString && !inComment && !inMultilineComment) {
        if (char == '{') braceDepth++;
        if (char == '}') {
          braceDepth--;
          if (braceDepth <= 0) {
            braceDepth = 0;
            String chunkStr = currentChunk.toString().trim();
            if (chunkStr.isNotEmpty) chunks.addAll(_splitIfTooLarge(chunkStr));
            currentChunk.clear();
          }
        }
      }
    }

    String remainder = currentChunk.toString().trim();
    if (remainder.isNotEmpty) chunks.addAll(_splitIfTooLarge(remainder));
    return chunks.isEmpty ? [text] : chunks;
  }

  List<String> _chunkByIndentation(String text) {
    List<String> chunks = [];
    final regex = RegExp(r'\n(?=def |class |async def )');
    final parts = text.split(regex);
    for (var p in parts) {
      if (p.trim().isNotEmpty) chunks.addAll(_splitIfTooLarge(p.trim()));
    }
    return chunks;
  }

  List<String> _splitIfTooLarge(String text) {
    if (text.length <= _maxChunkSize) return [text];
    return _fallbackChunkText(text);
  }

  List<String> _fallbackChunkText(String text) {
    if (text.length <= _maxChunkSize) return [text];
    final chunks = <String>[];
    int start = 0;
    const overlap = 200;
    while (start < text.length) {
      int end = start + _maxChunkSize;
      if (end > text.length) end = text.length;
      chunks.add(text.substring(start, end));
      start += _maxChunkSize - overlap;
    }
    return chunks;
  }

  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;
    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;
    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA == 0 || normB == 0) return 0.0;
    return dotProduct / (sqrt(normA) * sqrt(normB));
  }
}