import '../models/tool_call.dart';
import 'permissions_service.dart';
import 'rag_service.dart';
import 'tool_executor.dart';

ToolExecutor makeExecutor(PermissionsService perms, RagService ragService) => _WebToolExecutor();

class _WebToolExecutor implements ToolExecutor {
  @override
  bool get supportsLocalTools => false;

  @override
  Future<ToolResult> invoke(
      String name,
      Map<String, Object?> args, {
        bool Function()? isCancelled,
      }) async {
    return const ToolResult(
      ok: false,
      error: 'Local tools are only available in the Arzu Code desktop app. '
          'This web build is a chat-only preview.',
    );
  }
}