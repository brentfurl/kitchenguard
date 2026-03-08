import 'package:flutter/material.dart';

import '../../application/models/job_note.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({
    super.key,
    required this.loadNotes,
    required this.addNote,
    required this.softDeleteNote,
    this.onMutated,
  });

  final Future<List<JobNote>> Function() loadNotes;
  final Future<void> Function(String text) addNote;
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

  Future<String?> _showAddNoteDialog() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Note'),
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
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _addNoteFlow() async {
    final text = await _showAddNoteDialog();
    if (!mounted || text == null) return;
    if (text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Note cannot be empty')));
      return;
    }

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
      appBar: AppBar(title: const Text('Notes')),
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
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _removeNoteFlow(
                              noteId: note.noteId,
                              text: note.text,
                            ),
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
