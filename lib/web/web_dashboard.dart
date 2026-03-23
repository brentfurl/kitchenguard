import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_role_provider.dart';
import 'screens/web_job_detail_screen.dart';
import 'screens/web_schedule_screen.dart';
import 'screens/web_users_screen.dart';

enum _WebPage { schedule, users }

/// Sidebar-driven management dashboard for the web.
class WebDashboard extends ConsumerStatefulWidget {
  const WebDashboard({super.key});

  @override
  ConsumerState<WebDashboard> createState() => _WebDashboardState();
}

class _WebDashboardState extends ConsumerState<WebDashboard> {
  _WebPage _page = _WebPage.schedule;
  String? _selectedJobId;

  void _openJobDetail(String jobId) {
    setState(() => _selectedJobId = jobId);
  }

  void _closeJobDetail() {
    setState(() => _selectedJobId = null);
  }

  Future<void> _signOut() async {
    await ref.read(appRoleProvider.notifier).clearRole();
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      body: Row(
        children: [
          // --- Sidebar ---
          Container(
            width: 240,
            color: cs.surface,
            child: Column(
              children: [
                // Brand header
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                  child: Row(
                    children: [
                      Icon(Icons.shield_outlined,
                          size: 28, color: cs.primary),
                      const SizedBox(width: 10),
                      Text(
                        'KitchenGuard',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: cs.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                const SizedBox(height: 8),
                _NavItem(
                  icon: Icons.calendar_month_outlined,
                  label: 'Schedule',
                  selected: _page == _WebPage.schedule && _selectedJobId == null,
                  onTap: () => setState(() {
                    _page = _WebPage.schedule;
                    _selectedJobId = null;
                  }),
                ),
                _NavItem(
                  icon: Icons.people_outline,
                  label: 'Users',
                  selected: _page == _WebPage.users,
                  onTap: () => setState(() {
                    _page = _WebPage.users;
                    _selectedJobId = null;
                  }),
                ),
                const Spacer(),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: cs.primaryContainer,
                        child: Text(
                          (user?.email ?? '?')[0].toUpperCase(),
                          style: TextStyle(
                            color: cs.onPrimaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          user?.email ?? '',
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.logout, size: 20),
                        tooltip: 'Sign out',
                        onPressed: _signOut,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Sidebar border
          VerticalDivider(width: 1, thickness: 1, color: cs.outlineVariant),
          // --- Content area ---
          Expanded(
            child: _selectedJobId != null
                ? WebJobDetailScreen(
                    jobId: _selectedJobId!,
                    onBack: _closeJobDetail,
                  )
                : _buildPage(),
          ),
        ],
      ),
    );
  }

  Widget _buildPage() {
    switch (_page) {
      case _WebPage.schedule:
        return WebScheduleScreen(onJobTap: _openJobDetail);
      case _WebPage.users:
        return const WebUsersScreen();
    }
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: selected ? cs.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    color:
                        selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
