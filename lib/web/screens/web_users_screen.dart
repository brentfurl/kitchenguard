import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/app_role.dart';
import '../web_providers.dart';

/// User management screen for the web dashboard.
///
/// Lists all users from the Firestore `users` collection and allows managers
/// to assign or change roles via the `setUserRole` Cloud Function.
class WebUsersScreen extends ConsumerWidget {
  const WebUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final usersAsync = ref.watch(webUsersProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
          child: Row(
            children: [
              Text('Users',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _showInviteDialog(context, ref),
                icon: const Icon(Icons.person_add, size: 20),
                label: const Text('Add User'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // User list
        Expanded(
          child: usersAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (users) {
              if (users.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.people_outline,
                          size: 48, color: Colors.grey[400]),
                      const SizedBox(height: 12),
                      Text('No users found',
                          style:
                              TextStyle(color: Colors.grey[600], fontSize: 16)),
                      const SizedBox(height: 4),
                      Text(
                        'Users appear here after they sign in.',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    ],
                  ),
                );
              }

              return ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                children: [
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: cs.outlineVariant),
                    ),
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Email')),
                        DataColumn(label: Text('Name')),
                        DataColumn(label: Text('Role')),
                        DataColumn(label: Text('Last Login')),
                        DataColumn(label: Text('Actions')),
                      ],
                      rows: users.map((u) => _userRow(context, ref, u, cs)).toList(),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  DataRow _userRow(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> user,
    ColorScheme cs,
  ) {
    final email = user['email'] as String? ?? '';
    final name = user['displayName'] as String? ?? '-';
    final role = user['role'] as String? ?? 'none';
    final lastLogin = user['lastLoginAt'] as String? ?? '';
    final uid = user['uid'] as String? ?? '';
    final isSelf = uid == FirebaseAuth.instance.currentUser?.uid;

    String lastLoginDisplay;
    try {
      final utc = DateTime.parse(lastLogin);
      final dt = utc.subtract(const Duration(hours: 5));
      final hour24 = dt.hour;
      final hour12 = hour24 == 0 ? 12 : (hour24 > 12 ? hour24 - 12 : hour24);
      final amPm = hour24 < 12 ? 'AM' : 'PM';
      lastLoginDisplay =
          '${dt.month}/${dt.day}/${dt.year} $hour12:${dt.minute.toString().padLeft(2, '0')} $amPm';
    } catch (_) {
      lastLoginDisplay = '-';
    }

    return DataRow(cells: [
      DataCell(Text(email)),
      DataCell(
        InkWell(
          onTap: () => _editName(context, ref, uid, name),
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name),
                const SizedBox(width: 4),
                Icon(Icons.edit, size: 14, color: Colors.grey[400]),
              ],
            ),
          ),
        ),
      ),
      DataCell(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: role == 'manager'
                ? cs.primaryContainer
                : role == 'technician'
                    ? cs.secondaryContainer
                    : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            role == 'none' ? 'No Role' : role[0].toUpperCase() + role.substring(1),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: role == 'manager'
                  ? cs.onPrimaryContainer
                  : role == 'technician'
                      ? cs.onSecondaryContainer
                      : cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
      DataCell(Text(lastLoginDisplay,
          style: const TextStyle(fontSize: 13))),
      DataCell(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PopupMenuButton<String>(
              itemBuilder: (_) => [
                const PopupMenuItem(
                    value: 'manager', child: Text('Set as Manager')),
                const PopupMenuItem(
                    value: 'technician', child: Text('Set as Technician')),
              ],
              onSelected: (newRole) =>
                  _changeRole(context, ref, uid, email, newRole),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Change Role',
                        style: TextStyle(
                            fontSize: 13, color: cs.primary)),
                    Icon(Icons.arrow_drop_down, size: 18, color: cs.primary),
                  ],
                ),
              ),
            ),
            if (!isSelf) ...[
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(Icons.delete_outline, size: 20, color: cs.error),
                tooltip: 'Remove User',
                onPressed: () => _removeUser(context, ref, uid, email),
              ),
            ],
          ],
        ),
      ),
    ]);
  }

  Future<void> _changeRole(
    BuildContext context,
    WidgetRef ref,
    String uid,
    String email,
    String newRole,
  ) async {
    final appRole = AppRole.fromStorageString(newRole);
    if (appRole == null) return;

    try {
      final authService = ref.read(webAuthServiceProvider);
      await authService.setRole(role: appRole, uid: uid);
      // Update Firestore user doc
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'role': newRole,
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$email is now a $newRole.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update role: $e')),
        );
      }
    }
  }

  Future<void> _removeUser(
    BuildContext context,
    WidgetRef ref,
    String uid,
    String email,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove User'),
        content: Text('Remove $email from the user list?\n\n'
            'This removes the user record from Firestore. '
            'The user can re-appear by signing in again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).delete();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$email has been removed.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove user: $e')),
        );
      }
    }
  }

  Future<void> _editName(
    BuildContext context,
    WidgetRef ref,
    String uid,
    String currentName,
  ) async {
    final controller = TextEditingController(
      text: currentName == '-' ? '' : currentName,
    );
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Name'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 350),
          child: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Display Name'),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({'displayName': newName});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Name updated to $newName.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update name: $e')),
        );
      }
    }
  }

  void _showInviteDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add User'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: const Text(
            'New users can self-register from the mobile app or web sign-in screen. '
            'Once they sign in and select a role, they will appear in this list.\n\n'
            'As a manager, you can then change their role if needed.',
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
