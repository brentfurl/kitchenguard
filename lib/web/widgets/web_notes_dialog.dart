import 'package:flutter/material.dart';

/// Lightweight note descriptor used by [WebNotesDialog].
class WebNoteItem {
  final String id;
  final String text;
  const WebNoteItem(this.id, this.text);
}

/// Reusable dialog for managing a list of notes (add, edit, soft-delete).
///
/// Used by the web schedule screen (shift notes, job notes) and the web job
/// detail screen (manager notes, field notes). Callers provide typed callbacks
/// for persistence; the dialog handles UI and refresh.
class WebNotesDialog extends StatefulWidget {
  const WebNotesDialog({
    super.key,
    required this.title,
    required this.initialNotes,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onRefresh,
  });

  final String title;
  final List<WebNoteItem> initialNotes;
  final Future<void> Function(String text) onAdd;
  final Future<void> Function(String id, String newText) onEdit;
  final Future<void> Function(String id) onDelete;
  final Future<List<WebNoteItem>> Function() onRefresh;

  @override
  State<WebNotesDialog> createState() => _WebNotesDialogState();
}

class _WebNotesDialogState extends State<WebNotesDialog> {
  late List<WebNoteItem> _notes;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _notes = List.of(widget.initialNotes);
  }

  Future<String?> _showInputDialog({String? initialText}) {
    final controller = TextEditingController(text: initialText ?? '');
    final isEdit = initialText != null;
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEdit ? 'Edit Note' : 'Add Note'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 6,
          textInputAction: TextInputAction.newline,
          decoration: const InputDecoration(hintText: 'Enter note'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(isEdit ? 'Save' : 'Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _refresh() async {
    final updated = await widget.onRefresh();
    if (mounted) setState(() => _notes = updated);
  }

  Future<void> _add() async {
    final text = await _showInputDialog();
    if (text == null || text.isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.onAdd(text);
      await _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(WebNoteItem note) async {
    final newText = await _showInputDialog(initialText: note.text);
    if (newText == null || newText.isEmpty || newText == note.text) return;
    setState(() => _busy = true);
    try {
      await widget.onEdit(note.id, newText);
      await _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteNote(WebNoteItem note) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove note?'),
        content: Text(note.text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _busy = true);
    try {
      await widget.onDelete(note.id);
      await _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(widget.title)),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add note',
            onPressed: _busy ? null : _add,
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        height: 400,
        child: _busy
            ? const Center(child: CircularProgressIndicator())
            : _notes.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.note_outlined,
                            size: 48, color: Colors.grey[400]),
                        const SizedBox(height: 12),
                        Text('No notes yet',
                            style: TextStyle(color: Colors.grey[500])),
                        const SizedBox(height: 16),
                        FilledButton.tonalIcon(
                          onPressed: _add,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add Note'),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: _notes.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final note = _notes[i];
                      return ListTile(
                        title: Text(note.text),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon:
                                  const Icon(Icons.edit_outlined, size: 20),
                              tooltip: 'Edit',
                              onPressed: () => _edit(note),
                            ),
                            IconButton(
                              icon:
                                  const Icon(Icons.delete_outline, size: 20),
                              tooltip: 'Delete',
                              onPressed: () => _deleteNote(note),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
