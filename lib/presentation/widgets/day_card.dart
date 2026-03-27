import 'package:flutter/material.dart';

import '../../domain/models/day_note.dart';
import '../../domain/models/day_schedule.dart';
import '../../storage/job_scanner.dart';
import 'job_dialog.dart';

class DayCard extends StatelessWidget {
  const DayCard({
    super.key,
    required this.date,
    required this.jobs,
    required this.shiftNotes,
    this.daySchedule,
    required this.onReorder,
    required this.onArrivalTimesTap,
    required this.onShiftNotesTap,
    required this.onAddShiftNote,
    required this.jobCardBuilder,
    this.isManager = false,
    this.onTogglePublish,
  });

  final String date;
  final List<JobScanResult> jobs;
  final List<DayNote> shiftNotes;
  final DaySchedule? daySchedule;
  final void Function(int oldIndex, int newIndex) onReorder;
  final VoidCallback onArrivalTimesTap;
  final VoidCallback onShiftNotesTap;
  final VoidCallback onAddShiftNote;
  final Widget Function(BuildContext context, int index) jobCardBuilder;
  final bool isManager;
  final VoidCallback? onTogglePublish;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final allComplete =
        jobs.isNotEmpty && jobs.every((r) => r.job.isComplete);
    final isToday = date == toYyyyMmDd(DateTime.now());
    final isDraft = daySchedule == null || !daySchedule!.isPublished;

    final Color headerColor;
    final Color headerForeground;
    if (allComplete) {
      headerColor = colorScheme.surfaceContainerHigh;
      headerForeground = colorScheme.onSurfaceVariant;
    } else if (isToday) {
      headerColor = colorScheme.primary;
      headerForeground = colorScheme.onPrimary;
    } else {
      headerColor = colorScheme.primaryContainer;
      headerForeground = colorScheme.onPrimaryContainer;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ColoredBox(
            color: headerColor,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    allComplete ? Icons.check_circle : Icons.calendar_today,
                    size: 18,
                    color: headerForeground,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      formatDateLabel(date),
                      style: textTheme.titleMedium?.copyWith(
                        color: headerForeground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (isManager && isDraft)
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: headerForeground.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: headerForeground.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        'DRAFT',
                        style: textTheme.labelSmall?.copyWith(
                          color: headerForeground,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  if (isToday && !allComplete)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.onPrimary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'TODAY',
                        style: textTheme.labelSmall?.copyWith(
                          color: headerForeground,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  if (isManager && onTogglePublish != null)
                    SizedBox(
                      width: 32,
                      height: 32,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        iconSize: 20,
                        tooltip: isDraft ? 'Publish day' : 'Unpublish day',
                        icon: Icon(
                          isDraft ? Icons.publish : Icons.unpublished_outlined,
                          color: headerForeground,
                        ),
                        onPressed: onTogglePublish,
                      ),
                    ),
                ],
              ),
            ),
          ),
          _ArrivalTimesSection(
            schedule: daySchedule,
            shiftNotes: shiftNotes,
            onArrivalTimesTap: onArrivalTimesTap,
            onShiftNotesTap: onShiftNotesTap,
            onAddShiftNote: onAddShiftNote,
          ),
          const Divider(height: 1),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: jobs.length,
            onReorder: (oldIndex, newIndex) {
              if (newIndex > oldIndex) newIndex--;
              onReorder(oldIndex, newIndex);
            },
            itemBuilder: jobCardBuilder,
          ),
        ],
      ),
    );
  }
}

class _ArrivalTimesSection extends StatelessWidget {
  const _ArrivalTimesSection({
    this.schedule,
    required this.shiftNotes,
    required this.onArrivalTimesTap,
    required this.onShiftNotesTap,
    required this.onAddShiftNote,
  });

  final DaySchedule? schedule;
  final List<DayNote> shiftNotes;
  final VoidCallback onArrivalTimesTap;
  final VoidCallback onShiftNotesTap;
  final VoidCallback onAddShiftNote;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hasShopTime = schedule?.shopMeetupTime != null;
    final hasArrival = schedule?.firstArrivalTime != null;
    final hasAnyTime = hasShopTime || hasArrival;

    return ColoredBox(
      color: colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: InkWell(
                onTap: onArrivalTimesTap,
                child: hasAnyTime
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (hasShopTime)
                            Row(
                              children: [
                                Icon(Icons.store_outlined,
                                    size: 16, color: colorScheme.onSurfaceVariant),
                                const SizedBox(width: 6),
                                Text(
                                  'Shop meetup: ${schedule!.shopMeetupTime}',
                                  style: textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          if (hasArrival) ...[
                            if (hasShopTime) const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.restaurant_outlined,
                                    size: 16, color: colorScheme.onSurfaceVariant),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '${schedule!.firstRestaurantName ?? "First restaurant"} arrival: ${schedule!.firstArrivalTime}',
                                    style: textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      )
                    : Row(
                        children: [
                          Icon(Icons.schedule_outlined,
                              size: 16, color: colorScheme.onSurfaceVariant),
                          const SizedBox(width: 6),
                          Text(
                            'Add arrival times',
                            style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: shiftNotes.isNotEmpty
                      ? onShiftNotesTap
                      : onAddShiftNote,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.assignment_outlined,
                            size: 16, color: colorScheme.onSurfaceVariant),
                        if (shiftNotes.isNotEmpty) ...[
                          const SizedBox(width: 2),
                          Text(
                            '${shiftNotes.length}',
                            style: textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ] else ...[
                          const SizedBox(width: 2),
                          Icon(Icons.add, size: 14, color: colorScheme.onSurfaceVariant),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows the arrival time editing dialog. Returns the user's inputs,
/// or null if cancelled.
Future<ArrivalTimeDialogResult?> showArrivalTimeDialog(
  BuildContext context, {
  DaySchedule? existing,
  String? firstJobRestaurantName,
}) async {
  final arrivalController = TextEditingController(
    text: existing?.firstArrivalTime ?? '',
  );
  final shopController = TextEditingController(
    text: existing?.shopMeetupTime ?? '',
  );
  final restaurantName =
      existing?.firstRestaurantName ??
      firstJobRestaurantName ??
      '';

  final result = await showDialog<Map<String, String?>>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Arrival Times'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: arrivalController,
              decoration: InputDecoration(
                labelText: restaurantName.isNotEmpty
                    ? '$restaurantName arrival'
                    : 'First restaurant arrival',
                hintText: 'e.g. 9:45',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: shopController,
              decoration: const InputDecoration(
                labelText: 'Shop meetup time',
                hintText: 'e.g. 9:15 (optional)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          if (existing != null && !existing.isEmpty)
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop({
                'clear': 'true',
              }),
              child: const Text('Clear'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop({
              'arrival': arrivalController.text.trim(),
              'shop': shopController.text.trim(),
              'restaurant': restaurantName,
            }),
            child: const Text('Save'),
          ),
        ],
      );
    },
  );

  if (result == null) return null;

  if (result.containsKey('clear')) {
    return const ArrivalTimeDialogResult(clear: true);
  }

  return ArrivalTimeDialogResult(
    arrivalTime: result['arrival'],
    shopMeetupTime: result['shop'],
    restaurantName: result['restaurant'],
  );
}

class ArrivalTimeDialogResult {
  const ArrivalTimeDialogResult({
    this.clear = false,
    this.arrivalTime,
    this.shopMeetupTime,
    this.restaurantName,
  });

  final bool clear;
  final String? arrivalTime;
  final String? shopMeetupTime;
  final String? restaurantName;
}
