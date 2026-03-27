import 'package:flutter/material.dart';

import '../../domain/models/day_note.dart';

/// Shows a text input dialog for adding or editing a shift note.
/// Returns the trimmed text, or null if cancelled.
Future<String?> showShiftNoteDialog(
  BuildContext context, {
  String? initialText,
}) {
  final controller = TextEditingController(text: initialText ?? '');
  final isEdit = initialText != null;
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(isEdit ? 'Edit Shift Note' : 'Add Shift Note'),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(hintText: 'Enter note'),
        autofocus: true,
        minLines: 3,
        maxLines: 6,
        textInputAction: TextInputAction.newline,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(controller.text.trim()),
          child: Text(isEdit ? 'Save' : 'Add'),
        ),
      ],
    ),
  );
}

/// Opens a draggable bottom sheet displaying shift notes with
/// add, edit, and delete actions.
void openShiftNotesSheet(
  BuildContext context, {
  required List<DayNote> notes,
  required Future<void> Function() onAdd,
  required Future<void> Function(String noteId, String currentText) onEdit,
  required Future<void> Function(String noteId, String noteText) onDelete,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          return DraggableScrollableSheet(
            initialChildSize: 0.5,
            minChildSize: 0.3,
            maxChildSize: 0.85,
            expand: false,
            builder: (_, scrollController) {
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                    child: Row(
                      children: [
                        Text(
                          'Shift Notes',
                          style: Theme.of(sheetContext).textTheme.titleMedium,
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: () async {
                            await onAdd();
                            if (sheetContext.mounted) {
                              Navigator.of(sheetContext).pop();
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(sheetContext).pop(),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: notes.isEmpty
                        ? const Center(child: Text('No shift notes'))
                        : ListView.builder(
                            controller: scrollController,
                            itemCount: notes.length,
                            padding: const EdgeInsets.all(16),
                            itemBuilder: (_, i) {
                              final note = notes[i];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(note.text),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                          Icons.edit_outlined,
                                          size: 18),
                                      onPressed: () async {
                                        await onEdit(
                                          note.noteId,
                                          note.text,
                                        );
                                        if (sheetContext.mounted) {
                                          Navigator.of(sheetContext).pop();
                                        }
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                          Icons.delete_outline,
                                          size: 18),
                                      onPressed: () async {
                                        await onDelete(
                                          note.noteId,
                                          note.text,
                                        );
                                        if (sheetContext.mounted) {
                                          Navigator.of(sheetContext).pop();
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          );
        },
      );
    },
  );
}

/// Shows a confirmation dialog for deleting a shift note.
/// Returns true if the user confirmed deletion.
Future<bool> confirmDeleteShiftNote(
  BuildContext context,
  String noteText,
) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Remove shift note?'),
      content: Text(noteText),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Remove'),
        ),
      ],
    ),
  );
  return confirm == true;
}
