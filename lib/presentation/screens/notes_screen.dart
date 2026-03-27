import 'package:flutter/material.dart';

import '../../domain/models/job_note.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({
    super.key,
    required this.loadNotes,
    required this.addNote,
    required this.editNote,
    required this.softDeleteNote,
    this.onMutated,
  });

  final Future<List<JobNote>> Function() loadNotes;
  final Future<void> Function(String text) addNote;
  final Future<void> Function(String noteId, String newText) editNote;
  final Future<void> Function(String noteId) softDeleteNote;
  final Future<void> Function()? onMutated;

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  bool _isLoading = true;
  List<JobNote> _notes = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _isLoading = true);
    try {
      final notes = await widget.loadNotes();
      if (!mounted) return;
      setState(() => _notes = notes);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<String?> _showNoteDialog({String? initialText}) {
    final controller = TextEditingController(text: initialText ?? '');
    final isEdit = initialText != null;
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
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
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: Text(isEdit ? 'Save' : 'Add'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _addNoteFlow() async {
    final text = await _showNoteDialog();
    if (!mounted || text == null || text.isEmpty) return;

    try {
      await widget.addNote(text);
      if (widget.onMutated != null) {
        await widget.onMutated!();
      }
      if (!mounted) return;
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Note added')));
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().replaceFirst(
        RegExp(r'^(StateError|ArgumentError|Exception):\s*'),
        '',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message.isEmpty ? 'Failed to add note' : message),
        ),
      );
    }
  }

  Future<void> _editNoteFlow({
    required String noteId,
    required String currentText,
  }) async {
    final newText = await _showNoteDialog(initialText: currentText);
    if (!mounted || newText == null || newText.isEmpty) return;
    if (newText == currentText) return;

    try {
      await widget.editNote(noteId, newText);
      if (widget.onMutated != null) await widget.onMutated!();
      if (!mounted) return;
      await _reload();
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().replaceFirst(
        RegExp(r'^(StateError|ArgumentError|Exception):\s*'),
        '',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message.isEmpty ? 'Failed to edit note' : message),
        ),
      );
    }
  }

  Future<void> _removeNoteFlow({
    required String noteId,
    required String text,
  }) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Remove note?'),
          content: Text(text),
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
        );
      },
    );

    if (confirm != true || !mounted) return;

    try {
      await widget.softDeleteNote(noteId);
      if (widget.onMutated != null) {
        await widget.onMutated!();
      }
      if (!mounted) return;
      await _reload();
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().replaceFirst(
        RegExp(r'^(StateError|ArgumentError|Exception):\s*'),
        '',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message.isEmpty ? 'Failed to remove note' : message),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Field Notes')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                  child: FilledButton.icon(
                    onPressed: _addNoteFlow,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Note'),
                  ),
                ),
                if (_notes.isEmpty)
                  const Expanded(child: Center(child: Text('No notes yet')))
                else
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: _notes.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final note = _notes[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(note.text),
                          subtitle: Text(note.createdAt),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                tooltip: 'Edit',
                                onPressed: () => _editNoteFlow(
                                  noteId: note.noteId,
                                  currentText: note.text,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                tooltip: 'Delete',
                                onPressed: () => _removeNoteFlow(
                                  noteId: note.noteId,
                                  text: note.text,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
    );
  }
}
