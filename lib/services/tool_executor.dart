import '../models/tool_call.dart';
import 'permissions_service.dart';
import 'rag_service.dart';

import 'tool_executor_stub.dart'
if (dart.library.io) 'tool_executor_io.dart';

abstract class ToolExecutor {
  bool get supportsLocalTools;

  Future<ToolResult> invoke(
      String name,
      Map<String, Object?> args, {
        bool Function()? isCancelled,
      });

  factory ToolExecutor(PermissionsService perms, RagService ragService) => makeExecutor(perms, ragService);
}