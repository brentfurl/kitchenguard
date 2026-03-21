import 'package:flutter/material.dart';

class ToolsScreen extends StatefulWidget {
  const ToolsScreen({
    super.key,
    required this.onPrecleanLayout,
    required this.onNotes,
    required this.onExitVideos,
    required this.onOtherVideos,
    required this.preCleanLayoutCount,
    required this.notesCount,
    required this.exitVideosCount,
    required this.otherVideosCount,
  });

  final Future<void> Function() onPrecleanLayout;
  final Future<void> Function() onNotes;
  final Future<void> Function() onExitVideos;
  final Future<void> Function() onOtherVideos;
  final int Function() preCleanLayoutCount;
  final int Function() notesCount;
  final int Function() exitVideosCount;
  final int Function() otherVideosCount;

  @override
  State<ToolsScreen> createState() => _ToolsScreenState();
}

class _ToolsScreenState extends State<ToolsScreen> {
  bool _isOpening = false;

  Future<void> _openAndRefresh(Future<void> Function() open) async {
    if (_isOpening) return;
    setState(() => _isOpening = true);
    try {
      await open();
      if (!mounted) return;
      setState(() {});
    } finally {
      if (mounted) {
        setState(() => _isOpening = false);
      } else {
        _isOpening = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final preCleanLayoutCount = widget.preCleanLayoutCount();
    final notesCount = widget.notesCount();
    final exitVideosCount = widget.exitVideosCount();
    final otherVideosCount = widget.otherVideosCount();

    return Scaffold(
      appBar: AppBar(title: const Text('Tools')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
        children: [
          _SectionLabel('Setup'),
          _ToolTile(
            title: 'Pre-clean Layout ($preCleanLayoutCount)',
            subtitle: 'Capture and review initial setup layout',
            icon: Icons.grid_view_outlined,
            onTap: () => _openAndRefresh(widget.onPrecleanLayout),
          ),
          const SizedBox(height: 14),
          _SectionLabel('Documentation'),
          _ToolTile(
            title: 'Notes ($notesCount)',
            subtitle: 'Review or add job-level notes',
            icon: Icons.sticky_note_2_outlined,
            onTap: () => _openAndRefresh(widget.onNotes),
          ),
          const SizedBox(height: 14),
          _SectionLabel('Closeout'),
          _ToolTile(
            title: 'Exit Videos ($exitVideosCount)',
            subtitle: 'Manage exit recording and files',
            icon: Icons.videocam_outlined,
            onTap: () => _openAndRefresh(widget.onExitVideos),
          ),
          const SizedBox(height: 8),
          _ToolTile(
            title: 'Other Videos ($otherVideosCount)',
            subtitle: 'Manage additional video files',
            icon: Icons.video_collection_outlined,
            onTap: () => _openAndRefresh(widget.onOtherVideos),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.labelLarge),
    );
  }
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Icon(icon),
        title: Text(title, style: theme.textTheme.titleMedium),
        subtitle: Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
