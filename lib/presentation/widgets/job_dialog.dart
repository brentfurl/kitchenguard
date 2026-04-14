import 'package:flutter/material.dart';

class JobDialogResult {
  const JobDialogResult({
    required this.name,
    this.scheduledDate,
    this.clearScheduledDate = false,
    this.address,
    this.clearAddress = false,
    this.city,
    this.clearCity = false,
    this.accessType,
    this.clearAccessType = false,
    this.accessNotes,
    this.clearAccessNotes = false,
    this.hasAlarm,
    this.clearHasAlarm = false,
    this.alarmCode,
    this.clearAlarmCode = false,
    this.hoodCount,
    this.clearHoodCount = false,
    this.fanCount,
    this.clearFanCount = false,
    this.contactNotes = const [],
  });

  final String name;
  final DateTime? scheduledDate;
  final bool clearScheduledDate;
  final String? address;
  final bool clearAddress;
  final String? city;
  final bool clearCity;
  final String? accessType;
  final bool clearAccessType;
  final String? accessNotes;
  final bool clearAccessNotes;
  final bool? hasAlarm;
  final bool clearHasAlarm;
  final String? alarmCode;
  final bool clearAlarmCode;
  final int? hoodCount;
  final bool clearHoodCount;
  final int? fanCount;
  final bool clearFanCount;
  final List<String> contactNotes;
}

const accessTypeLabels = <String, String>{
  'no-key': 'No key — meet after closing',
  'get-key-from-shop': 'Get key from shop',
  'key-hidden': 'Key hidden',
  'lockbox': 'Lockbox',
};

String toYyyyMmDd(DateTime dt) {
  final y = dt.year.toString().padLeft(4, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

String formatDateLabel(String yyyyMmDd) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  const weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  final dt = DateTime.tryParse(yyyyMmDd);
  if (dt == null) return yyyyMmDd;
  final weekday = weekdays[dt.weekday - 1];
  final month = months[dt.month - 1];
  return '$weekday, $month ${dt.day}, ${dt.year}';
}

Future<JobDialogResult?> showJobDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String? initialName,
  DateTime? initialDate,
  String? initialAddress,
  String? initialCity,
  String? initialAccessType,
  String? initialAccessNotes,
  bool? initialHasAlarm,
  String? initialAlarmCode,
  int? initialHoodCount,
  int? initialFanCount,
  List<String>? existingContacts,
  bool isEdit = false,
}) async {
  final nameController = TextEditingController(text: initialName ?? '');
  final addressController = TextEditingController(text: initialAddress ?? '');
  final cityController = TextEditingController(text: initialCity ?? '');
  final accessNotesController = TextEditingController(
    text: initialAccessNotes ?? '',
  );
  final alarmCodeController = TextEditingController(
    text: initialAlarmCode ?? '',
  );
  final hoodCountController = TextEditingController(
    text: initialHoodCount != null ? '$initialHoodCount' : '',
  );
  final fanCountController = TextEditingController(
    text: initialFanCount != null ? '$initialFanCount' : '',
  );
  final contactController = TextEditingController();
  final dialogScrollController = ScrollController();

  DateTime? selectedDate = initialDate;
  String? accessType = initialAccessType;
  bool hasAlarm = initialHasAlarm ?? false;
  final contactNotes = <String>[...?existingContacts];

  final result = await showDialog<JobDialogResult>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final theme = Theme.of(dialogContext);
          final colorScheme = theme.colorScheme;

          final bool hasAddressData =
              addressController.text.isNotEmpty ||
              cityController.text.isNotEmpty;
          final bool hasAccessData = accessType != null || hasAlarm;
          final bool hasUnitData =
              hoodCountController.text.isNotEmpty ||
              fanCountController.text.isNotEmpty;

          final needsAccessNotes =
              accessType == 'key-hidden' || accessType == 'lockbox';
          final accessNotesLabel = accessType == 'lockbox'
              ? 'Lockbox code / location'
              : 'Key description';

          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                controller: dialogScrollController,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // --- Top section: always visible ---
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Restaurant name',
                      ),
                      autofocus: true,
                    ),
                    const SizedBox(height: 16),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: dialogContext,
                          initialDate: selectedDate ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (picked != null) {
                          setDialogState(() => selectedDate = picked);
                        }
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Scheduled date',
                          suffixIcon: selectedDate != null
                              ? IconButton(
                                  icon: const Icon(Icons.close, size: 18),
                                  onPressed: () {
                                    setDialogState(() => selectedDate = null);
                                  },
                                )
                              : const Icon(Icons.calendar_today, size: 18),
                        ),
                        child: Text(
                          selectedDate != null
                              ? formatDateLabel(toYyyyMmDd(selectedDate!))
                              : 'Not scheduled',
                          style: TextStyle(
                            color: selectedDate != null
                                ? null
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // --- Expandable: Address ---
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Row(
                        children: [
                          const Text('Address'),
                          if (hasAddressData) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.check_circle,
                              size: 16,
                              color: colorScheme.primary,
                            ),
                          ],
                        ],
                      ),
                      initiallyExpanded: hasAddressData,
                      children: [
                        TextField(
                          controller: addressController,
                          decoration: const InputDecoration(
                            labelText: 'Street address',
                            floatingLabelBehavior: FloatingLabelBehavior.always,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: cityController,
                          decoration: const InputDecoration(
                            labelText: 'City',
                            floatingLabelBehavior: FloatingLabelBehavior.always,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),

                    // --- Expandable: Access Info ---
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Row(
                        children: [
                          const Text('Access Info'),
                          if (hasAccessData) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.check_circle,
                              size: 16,
                              color: colorScheme.primary,
                            ),
                          ],
                        ],
                      ),
                      initiallyExpanded: hasAccessData,
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: accessType,
                          decoration: const InputDecoration(
                            labelText: 'Access type',
                            floatingLabelBehavior: FloatingLabelBehavior.always,
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: null,
                              child: Text('Not set'),
                            ),
                            ...accessTypeLabels.entries.map(
                              (e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(e.value),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            setDialogState(() => accessType = value);
                          },
                        ),
                        if (needsAccessNotes) ...[
                          const SizedBox(height: 8),
                          TextField(
                            controller: accessNotesController,
                            decoration: InputDecoration(
                              labelText: accessNotesLabel,
                              floatingLabelBehavior:
                                  FloatingLabelBehavior.always,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Alarm'),
                          value: hasAlarm,
                          onChanged: (v) {
                            setDialogState(() => hasAlarm = v);
                          },
                        ),
                        if (hasAlarm) ...[
                          TextField(
                            controller: alarmCodeController,
                            decoration: const InputDecoration(
                              labelText: 'Alarm code',
                              floatingLabelBehavior:
                                  FloatingLabelBehavior.always,
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ),

                    // --- Expandable: Contacts ---
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Row(
                        children: [
                          const Text('Contacts'),
                          if (contactNotes.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.check_circle,
                              size: 16,
                              color: colorScheme.primary,
                            ),
                          ],
                        ],
                      ),
                      children: [
                        for (var ci = 0; ci < contactNotes.length; ci++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () {
                                      final editCtrl = TextEditingController(
                                        text: contactNotes[ci],
                                      );
                                      showDialog<String>(
                                        context: dialogContext,
                                        builder: (ctx) => AlertDialog(
                                          title: const Text('Edit Contact'),
                                          content: TextField(
                                            controller: editCtrl,
                                            autofocus: true,
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.of(ctx).pop(),
                                              child: const Text('Cancel'),
                                            ),
                                            FilledButton(
                                              onPressed: () => Navigator.of(
                                                ctx,
                                              ).pop(editCtrl.text.trim()),
                                              child: const Text('Save'),
                                            ),
                                          ],
                                        ),
                                      ).then((edited) {
                                        if (edited != null &&
                                            edited.isNotEmpty) {
                                          setDialogState(
                                            () => contactNotes[ci] = edited,
                                          );
                                        }
                                      });
                                    },
                                    child: Text(
                                      contactNotes[ci],
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close, size: 16),
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () {
                                    setDialogState(
                                      () => contactNotes.removeAt(ci),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: contactController,
                                decoration: const InputDecoration(
                                  hintText: 'Name (Role) Phone',
                                  isDense: true,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add),
                              onPressed: () {
                                final text = contactController.text.trim();
                                if (text.isNotEmpty) {
                                  setDialogState(() {
                                    contactNotes.add(text);
                                    contactController.clear();
                                  });
                                }
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),

                    // --- Expandable: Units ---
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      onExpansionChanged: (expanded) {
                        if (!expanded) return;
                        WidgetsBinding.instance.addPostFrameCallback((_) async {
                          // ExpansionTile animates its children open. Wait for that
                          // animation to finish so maxScrollExtent is accurate.
                          await Future<void>.delayed(
                            const Duration(milliseconds: 250),
                          );
                          if (!dialogScrollController.hasClients) return;
                          final target =
                              dialogScrollController.position.maxScrollExtent;
                          dialogScrollController.animateTo(
                            target,
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeOut,
                          );
                        });
                      },
                      title: Row(
                        children: [
                          const Text('Units'),
                          if (hasUnitData) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.check_circle,
                              size: 16,
                              color: colorScheme.primary,
                            ),
                          ],
                        ],
                      ),
                      initiallyExpanded: hasUnitData,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: hoodCountController,
                                decoration: const InputDecoration(
                                  labelText: 'Hoods',
                                  floatingLabelBehavior:
                                      FloatingLabelBehavior.always,
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: TextField(
                                controller: fanCountController,
                                decoration: const InputDecoration(
                                  labelText: 'Fans',
                                  floatingLabelBehavior:
                                      FloatingLabelBehavior.always,
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final hoodCount = int.tryParse(
                    hoodCountController.text.trim(),
                  );
                  final fanCount = int.tryParse(fanCountController.text.trim());
                  final address = addressController.text.trim();
                  final city = cityController.text.trim();
                  final notes = accessNotesController.text.trim();
                  final alarm = alarmCodeController.text.trim();

                  Navigator.of(dialogContext).pop(
                    JobDialogResult(
                      name: nameController.text,
                      scheduledDate: selectedDate,
                      clearScheduledDate: isEdit && selectedDate == null,
                      address: address.isNotEmpty ? address : null,
                      clearAddress:
                          isEdit && address.isEmpty && initialAddress != null,
                      city: city.isNotEmpty ? city : null,
                      clearCity: isEdit && city.isEmpty && initialCity != null,
                      accessType: accessType,
                      clearAccessType:
                          isEdit &&
                          accessType == null &&
                          initialAccessType != null,
                      accessNotes: notes.isNotEmpty ? notes : null,
                      clearAccessNotes:
                          isEdit && notes.isEmpty && initialAccessNotes != null,
                      hasAlarm: hasAlarm ? true : null,
                      clearHasAlarm:
                          isEdit && !hasAlarm && initialHasAlarm == true,
                      alarmCode: alarm.isNotEmpty ? alarm : null,
                      clearAlarmCode:
                          isEdit && alarm.isEmpty && initialAlarmCode != null,
                      hoodCount: hoodCount,
                      clearHoodCount:
                          isEdit &&
                          hoodCount == null &&
                          initialHoodCount != null,
                      fanCount: fanCount,
                      clearFanCount:
                          isEdit && fanCount == null && initialFanCount != null,
                      contactNotes: contactNotes,
                    ),
                  );
                },
                child: Text(confirmLabel),
              ),
            ],
          );
        },
      );
    },
  );
  dialogScrollController.dispose();
  return result;
}
