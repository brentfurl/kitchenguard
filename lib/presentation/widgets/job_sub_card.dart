import 'package:flutter/material.dart';

import '../../storage/job_scanner.dart';
import 'job_dialog.dart';

class JobSubCard extends StatelessWidget {
  const JobSubCard({
    super.key,
    required this.result,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleCompletion,
    this.onManagerNotes,
  });

  final JobScanResult result;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleCompletion;
  final VoidCallback? onManagerNotes;

  @override
  Widget build(BuildContext context) {
    final job = result.job;
    final restaurant =
        job.restaurantName.isNotEmpty ? job.restaurantName : 'Unknown';
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final hoodCount = job.hoodCount ?? job.units.where((u) => u.type == 'hood').length;
    final fanCount = job.fanCount ?? job.units.where((u) => u.type == 'fan').length;
    final unitSummaryParts = <String>[];
    if (hoodCount > 0) unitSummaryParts.add('$hoodCount ${hoodCount == 1 ? "hood" : "hoods"}');
    if (fanCount > 0) unitSummaryParts.add('$fanCount ${fanCount == 1 ? "fan" : "fans"}');
    final unitSummary = unitSummaryParts.join(', ');

    final accessLabel = job.accessType != null
        ? accessTypeLabels[job.accessType] ?? job.accessType!
        : null;

    final accessDetailParts = <String>[];
    if (accessLabel != null) {
      final accessWithNotes = (job.accessNotes != null && job.accessNotes!.isNotEmpty)
          ? '$accessLabel, ${job.accessNotes}'
          : accessLabel;
      accessDetailParts.add(accessWithNotes);
    }
    if (job.hasAlarm == true) {
      final alarmText = (job.alarmCode != null && job.alarmCode!.isNotEmpty)
          ? 'Alarm, ${job.alarmCode}'
          : 'Alarm';
      accessDetailParts.add(alarmText);
    }
    final accessDetail = accessDetailParts.join(' · ');

    final activeManagerNotes = job.managerNotes.where((n) => n.isActive);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (job.isComplete)
                Padding(
                  padding: const EdgeInsets.only(right: 8, top: 2),
                  child: Icon(
                    Icons.check_circle,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      restaurant,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: job.isComplete
                            ? colorScheme.onSurfaceVariant
                            : null,
                      ),
                    ),
                    if (job.address != null && job.address!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        job.city != null && job.city!.isNotEmpty
                            ? '${job.address!}, ${job.city!}'
                            : job.address!,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (unitSummary.isNotEmpty || accessDetail.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          if (unitSummary.isNotEmpty)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.grid_view_outlined,
                                    size: 14,
                                    color: colorScheme.onSurfaceVariant),
                                const SizedBox(width: 4),
                                Text(
                                  unitSummary,
                                  style: textTheme.labelSmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          if (accessDetail.isNotEmpty)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.key_outlined,
                                    size: 14,
                                    color: colorScheme.onSurfaceVariant),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    accessDetail,
                                    style: textTheme.labelSmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (activeManagerNotes.isNotEmpty && onManagerNotes != null)
                    GestureDetector(
                      onTap: onManagerNotes,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2, bottom: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.note_alt_outlined,
                                size: 18, color: colorScheme.onSurfaceVariant),
                            const SizedBox(width: 2),
                            Text(
                              '${activeManagerNotes.length}',
                              style: textTheme.labelMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  _JobOverflowMenu(
                    isComplete: job.isComplete,
                    onEdit: onEdit,
                    onDelete: onDelete,
                    onToggleCompletion: onToggleCompletion,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Simpler tile used in the unscheduled section.
class JobTile extends StatelessWidget {
  const JobTile({
    super.key,
    required this.result,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleCompletion,
  });

  final JobScanResult result;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleCompletion;

  @override
  Widget build(BuildContext context) {
    final job = result.job;
    final restaurant =
        job.restaurantName.isNotEmpty ? job.restaurantName : 'Unknown';
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            if (job.isComplete)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(
                  Icons.check_circle,
                  size: 18,
                  color: colorScheme.primary,
                ),
              ),
            Expanded(
              child: Text(
                restaurant,
                style: textTheme.bodyLarge?.copyWith(
                  color: job.isComplete
                      ? colorScheme.onSurfaceVariant
                      : null,
                ),
              ),
            ),
            _JobOverflowMenu(
              isComplete: job.isComplete,
              onEdit: onEdit,
              onDelete: onDelete,
              onToggleCompletion: onToggleCompletion,
            ),
          ],
        ),
      ),
    );
  }
}

class UnscheduledSection extends StatelessWidget {
  const UnscheduledSection({
    super.key,
    required this.jobs,
    required this.onJobTap,
    required this.onJobEdit,
    required this.onJobDelete,
    required this.onJobToggleCompletion,
  });

  final List<JobScanResult> jobs;
  final void Function(JobScanResult) onJobTap;
  final void Function(JobScanResult) onJobEdit;
  final void Function(JobScanResult) onJobDelete;
  final void Function(JobScanResult) onJobToggleCompletion;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ColoredBox(
            color: colorScheme.surfaceContainerHigh,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.schedule_outlined,
                    size: 18,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Unscheduled',
                    style: textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          for (final result in jobs)
            JobTile(
              result: result,
              onTap: () => onJobTap(result),
              onEdit: () => onJobEdit(result),
              onDelete: () => onJobDelete(result),
              onToggleCompletion: () => onJobToggleCompletion(result),
            ),
        ],
      ),
    );
  }
}

class _JobOverflowMenu extends StatelessWidget {
  const _JobOverflowMenu({
    required this.isComplete,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleCompletion,
  });

  final bool isComplete;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleCompletion;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (value) {
        switch (value) {
          case 'edit':
            onEdit();
          case 'delete':
            onDelete();
          case 'complete':
            onToggleCompletion();
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem<String>(
          value: 'edit',
          child: Text('Edit Job'),
        ),
        PopupMenuItem<String>(
          value: 'complete',
          child: Text(
            isComplete ? 'Reopen Job' : 'Mark Complete',
          ),
        ),
        const PopupMenuItem<String>(
          value: 'delete',
          child: Text('Delete Job'),
        ),
      ],
    );
  }
}
