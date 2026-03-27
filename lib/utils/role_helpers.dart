import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/app_role.dart';
import '../providers/app_role_provider.dart';

extension RoleCheck on AppRole? {
  bool get isManager => this == AppRole.manager;
  bool get isTechnician => this == AppRole.technician;
}

/// Renders [child] only when the current user is a manager.
/// Returns [SizedBox.shrink] otherwise.
class ManagerOnly extends ConsumerWidget {
  const ManagerOnly({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(appRoleProvider);
    if (!role.isManager) return const SizedBox.shrink();
    return child;
  }
}
