import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' as intl;
import 'package:study_organizer/core/bloc/app_bloc.dart';
import 'package:study_organizer/core/bloc/app_event.dart';
import 'package:study_organizer/core/widgets/glass.dart';
import 'package:study_organizer/core/widgets/atext.dart';
import 'package:study_organizer/features/subjects/data/models/subject.dart';
import 'package:study_organizer/features/notes/data/models/subject_note.dart';

class SubjectNotesTab extends StatelessWidget {
  final Subject subject;
  final List<SubjectNote> notes;

  const SubjectNotesTab({
    super.key,
    required this.subject,
    required this.notes,
  });

  @override
  Widget build(BuildContext context) {
    return _notesTab(context, notes);
  }

    Widget _notesTab(BuildContext ctx, List<SubjectNote> notes) {
    final categories = <String>{};
    for (final n in notes) categories.add(n.category);
    if (categories.isEmpty) categories.add('General');
    final sortedCats = categories.toList()..sort();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ElevatedButton.icon(
          onPressed: () => _showAddNote(ctx),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add Note'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Color(subject.color),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (notes.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(
                    Icons.note_add_rounded,
                    size: 48,
                    color: Colors.grey.withOpacity(0.3),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'No notes yet',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ...sortedCats.map((cat) {
          final catNotes = notes.where((n) => n.category == cat).toList();
          if (catNotes.isEmpty) return const SizedBox.shrink();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8, top: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: cat == 'exam_mistake'
                            ? Colors.redAccent.withOpacity(0.15)
                            : Color(subject.color).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        cat == 'exam_mistake'
                            ? '❌ Exam Mistakes (NOVA Strategy)'
                            : cat,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: cat == 'exam_mistake'
                              ? Colors.redAccent
                              : Color(subject.color),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${catNotes.length} note${catNotes.length > 1 ? 's' : ''}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              ...catNotes.map((note) {
                final isMistake = note.category == 'exam_mistake';
                return Glass(
                  padding: const EdgeInsets.all(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _showEditNote(ctx, note),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (isMistake)
                              const Padding(
                                padding: EdgeInsets.only(right: 8.0),
                                child: Icon(
                                  Icons.warning_amber_rounded,
                                  color: Colors.redAccent,
                                  size: 18,
                                ),
                              ),
                            Expanded(
                              child: Text(
                                note.title,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: isMistake
                                      ? Colors.redAccent
                                      : Colors.white,
                                ),
                              ),
                            ),
                            PopupMenuButton<String>(
                              icon: const Icon(
                                Icons.more_vert_rounded,
                                size: 18,
                                color: Colors.grey,
                              ),
                              onSelected: (action) {
                                if (action == 'edit') _showEditNote(ctx, note);
                                if (action == 'delete')
                                  _confirmDeleteNote(ctx, note);
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.edit_rounded,
                                        size: 16,
                                        color: Colors.blue,
                                      ),
                                      SizedBox(width: 8),
                                      Text('Edit'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.delete_rounded,
                                        size: 16,
                                        color: Colors.red,
                                      ),
                                      SizedBox(width: 8),
                                      Text('Delete'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (note.content.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            note.content.length > 250
                                ? '${note.content.substring(0, 250)}...'
                                : note.content,
                            style: TextStyle(
                              fontSize: 13,
                              color: isMistake
                                  ? Colors.red.shade200
                                  : Colors.grey[600],
                              height: 1.4,
                            ),
                          ),
                        ],
                        if (note.updatedAt != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Updated ${intl.DateFormat('MMM d, h:mm a').format(note.updatedAt!)}',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey[400],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }).toList(),
            ],
          );
        }),
      ],
    );
  }

  // ═══════════════ ALL OTHER TABS (unchanged) ════════════════════════════════


    void _showAddNote(BuildContext ctx) {
    final titleC = TextEditingController();
    final contentC = TextEditingController();
    final categoryC = TextEditingController(text: 'General');
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) {
          final d = Theme.of(c).brightness == Brightness.dark;
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(c).viewInsets.bottom,
            ),
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(c).size.height * 0.85,
              ),
              decoration: BoxDecoration(
                color: d ? const Color(0xFF12122A) : Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Center(
                      child: Text(
                        'Add Note',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: titleC,
                      decoration: const InputDecoration(
                        labelText: 'Title',
                        prefixIcon: Icon(Icons.title_rounded),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: categoryC,
                      decoration: const InputDecoration(
                        labelText: 'Category',
                        prefixIcon: Icon(Icons.category_rounded),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children:
                          ['General', 'Lecture', 'Lab', 'Exam', 'Important']
                              .map(
                                (cat) => GestureDetector(
                                  onTap: () => setS(() => categoryC.text = cat),
                                  child: Chip(
                                    label: Text(
                                      cat,
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    backgroundColor: categoryC.text == cat
                                        ? Color(subject.color).withOpacity(0.2)
                                        : null,
                                    side: BorderSide(
                                      color: categoryC.text == cat
                                          ? Color(subject.color)
                                          : Colors.grey.withOpacity(0.3),
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: contentC,
                      maxLines: 6,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        labelText: 'Content',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () {
                        if (titleC.text.trim().isEmpty) {
                          ScaffoldMessenger.of(c).showSnackBar(
                            const SnackBar(content: Text('Enter a title')),
                          );
                          return;
                        }
                        ctx.read<AppBloc>().add(
                          AddSubjectNote(
                            SubjectNote(
                              subjectId: subject.id!,
                              title: titleC.text.trim(),
                              category: categoryC.text.trim().isEmpty
                                  ? 'General'
                                  : categoryC.text.trim(),
                              content: contentC.text.trim(),
                            ),
                          ),
                        );
                        Navigator.pop(c);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(subject.color),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Save Note'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showEditNote(BuildContext ctx, SubjectNote note) {
    final titleC = TextEditingController(text: note.title);
    final contentC = TextEditingController(text: note.content);
    final categoryC = TextEditingController(text: note.category);
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) {
          final d = Theme.of(c).brightness == Brightness.dark;
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(c).viewInsets.bottom,
            ),
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(c).size.height * 0.85,
              ),
              decoration: BoxDecoration(
                color: d ? const Color(0xFF12122A) : Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Center(
                      child: Text(
                        'Edit Note',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: titleC,
                      decoration: const InputDecoration(
                        labelText: 'Title',
                        prefixIcon: Icon(Icons.title_rounded),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: categoryC,
                      decoration: const InputDecoration(
                        labelText: 'Category',
                        prefixIcon: Icon(Icons.category_rounded),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: contentC,
                      maxLines: 8,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        labelText: 'Content',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () {
                        if (titleC.text.trim().isEmpty) return;
                        ctx.read<AppBloc>().add(
                          UpdateSubjectNote(
                            note.copyWith(
                              title: titleC.text.trim(),
                              category: categoryC.text.trim().isEmpty
                                  ? 'General'
                                  : categoryC.text.trim(),
                              content: contentC.text.trim(),
                              updatedAt: DateTime.now(),
                            ),
                          ),
                        );
                        Navigator.pop(c);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(subject.color),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Save Changes'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _confirmDeleteNote(BuildContext ctx, SubjectNote note) {
    showDialog(
      context: ctx,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Note?'),
        content: Text('Delete "${note.title}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              ctx.read<AppBloc>().add(DeleteSubjectNote(note.id!));
              Navigator.pop(c);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

}
