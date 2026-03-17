// class SubjectDetailPage extends StatelessWidget {
//   final Subject subject;
//   const SubjectDetailPage({super.key, required this.subject});
//
//   @override
//   Widget build(BuildContext context) {
//     return DefaultTabController(
//       length: 3,
//       child: Scaffold(
//         appBar: AppBar(
//           title: Text(subject.name),
//           bottom: TabBar(
//             indicatorColor: Color(subject.color),
//             labelColor: Color(subject.color),
//             tabs: const [
//               Tab(text: 'Attendance', icon: Icon(Icons.event_busy_rounded, size: 20)),
//               Tab(text: 'Marks', icon: Icon(Icons.grade_rounded, size: 20)),
//               Tab(text: 'Tasks', icon: Icon(Icons.task_rounded, size: 20)),
//             ],
//           ),
//         ),
//         body: BlocBuilder<AppBloc, AppState>(
//           builder: (ctx, state) {
//             final abs = state.absences.where((a) => a['subjectId'] == subject.id).toList();
//             final marks = state.marks.where((m) => m.subjectId == subject.id).toList();
//             final tasks = state.tasks.where((t) => t.subjectId == subject.id).toList();
//             final lCount = abs.where((a) => a['type'] == 'lecture').length;
//             final sCount = abs.where((a) => a['type'] == 'section').length;
//             final labCount = abs.where((a) => a['type'] == 'lab').length;
//
//             return TabBarView(children: [
//               _attendanceTab(ctx, abs, lCount, sCount, labCount),
//               _marksTab(ctx, marks),
//               _tasksTab(context, tasks, state.subjects),
//             ]);
//           },
//         ),
//       ),
//     );
//   }
//
//
//
//   Widget _ring(String label, int current, int max, Color color) {
//     final p = max > 0 ? current / max : 0.0;
//     final danger = p >= 1.0;
//     final warn = p >= 0.75;
//     final c = danger ? const Color(0xFFFF4757) : warn ? const Color(0xFFFF9F43) : color;
//     return Column(mainAxisSize: MainAxisSize.min, children: [
//       SizedBox(width: 70, height: 70, child: Stack(fit: StackFit.expand, children: [
//         CircularProgressIndicator(value: p.clamp(0, 1), strokeWidth: 7, backgroundColor: Colors.grey.withOpacity(0.15), valueColor: AlwaysStoppedAnimation(c)),
//         Center(child: Text('$current/$max', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: c))),
//       ])),
//       const SizedBox(height: 8),
//       Text(label, style: const TextStyle(fontSize: 12)),
//       Text('${max - current} left', style: TextStyle(fontSize: 10, color: c, fontWeight: FontWeight.w600)),
//     ]);
//   }
//
//   String _estimateGrade(double pct) {
//     if (pct >= 93) return 'A (4.0)';
//     if (pct >= 89) return 'A- (3.7)';
//     if (pct >= 84) return 'B+ (3.3)';
//     if (pct >= 80) return 'B (3.0)';
//     if (pct >= 76) return 'B- (2.7)';
//     if (pct >= 73) return 'C+ (2.3)';
//     if (pct >= 70) return 'C (2.0)';
//     if (pct >= 67) return 'C- (1.7)';
//     if (pct >= 64) return 'D+ (1.3)';
//     if (pct >= 60) return 'D (1.0)';
//     return 'F (0.0)';
//   }
//
//   void _showAddMark(BuildContext ctx) {
//     final labelC = TextEditingController();
//     final obtC = TextEditingController();
//     final totC = TextEditingController(text: '100'); // Default 100
//     String cat = 'midterm1';
//     const catOptions = {
//       'midterm1': '5th Week Midterm',
//       'midterm2': '10th Week Midterm',
//       'quiz': 'Quiz',
//       'assignment': 'Assignment',
//       'project': 'Project',
//       'report': 'Report',
//       'final': 'Final Exam',
//       'other': 'Other',
//     };
//
//     showModalBottomSheet(
//       context: ctx,
//       isScrollControlled: true,
//       backgroundColor: Colors.transparent,
//       builder: (c) => StatefulBuilder(builder: (c, setS) {
//         final d = Theme.of(c).brightness == Brightness.dark;
//         return Container(
//           padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
//           decoration: BoxDecoration(
//             color: d ? const Color(0xFF12122A) : Colors.white,
//             borderRadius:
//             const BorderRadius.vertical(top: Radius.circular(28)),
//           ),
//           child: SingleChildScrollView(
//             padding: const EdgeInsets.all(24),
//             child: Column(
//               mainAxisSize: MainAxisSize.min,
//               crossAxisAlignment: CrossAxisAlignment.stretch,
//               children: [
//                 Center(
//                   child: Container(
//                     width: 40,
//                     height: 4,
//                     decoration: BoxDecoration(
//                       color: Colors.grey.withOpacity(0.3),
//                       borderRadius: BorderRadius.circular(2),
//                     ),
//                   ),
//                 ),
//                 const SizedBox(height: 16),
//                 const Center(
//                   child: Text('Add Mark',
//                       style: TextStyle(
//                           fontSize: 20, fontWeight: FontWeight.w700)),
//                 ),
//                 const SizedBox(height: 16),
//                 DropdownButtonFormField<String>(
//                   value: cat,
//                   decoration: const InputDecoration(
//                     labelText: 'Category',
//                     prefixIcon: Icon(Icons.category_rounded),
//                   ),
//                   items: catOptions.entries
//                       .map((e) => DropdownMenuItem(
//                       value: e.key, child: Text(e.value)))
//                       .toList(),
//                   onChanged: (v) => setS(() => cat = v!),
//                 ),
//                 const SizedBox(height: 10),
//                 TextField(
//                   controller: labelC,
//                   decoration: const InputDecoration(
//                     labelText: 'Label (e.g. Quiz 1, Project 2)',
//                     prefixIcon: Icon(Icons.label_rounded),
//                   ),
//                 ),
//                 const SizedBox(height: 10),
//                 Row(children: [
//                   Expanded(
//                     child: TextField(
//                       controller: obtC,
//                       decoration: const InputDecoration(
//                         labelText: 'Obtained',
//                         prefixIcon: Icon(Icons.star_rounded),
//                       ),
//                       keyboardType: TextInputType.number,
//                     ),
//                   ),
//                   const SizedBox(width: 10),
//                   const Text('/',
//                       style: TextStyle(
//                           fontSize: 24,
//                           fontWeight: FontWeight.bold,
//                           color: Colors.grey)),
//                   const SizedBox(width: 10),
//                   Expanded(
//                     child: TextField(
//                       controller: totC,
//                       decoration: const InputDecoration(
//                         labelText: 'Total',
//                         prefixIcon: Icon(Icons.star_border_rounded),
//                       ),
//                       keyboardType: TextInputType.number,
//                     ),
//                   ),
//                 ]),
//                 const SizedBox(height: 8),
//                 // Quick total buttons
//                 Wrap(
//                   spacing: 8,
//                   runSpacing: 8,
//                   children: [10, 15, 20, 25, 30, 40, 50, 100].map((v) {
//                     final selected = totC.text == v.toString();
//                     return GestureDetector(
//                       onTap: () => setS(() => totC.text = v.toString()),
//                       child: Container(
//                         padding: const EdgeInsets.symmetric(
//                             horizontal: 12, vertical: 6),
//                         decoration: BoxDecoration(
//                           color: selected
//                               ? Color(subject.color).withOpacity(0.2)
//                               : Colors.grey.withOpacity(0.1),
//                           borderRadius: BorderRadius.circular(10),
//                           border: Border.all(
//                             color: selected
//                                 ? Color(subject.color)
//                                 : Colors.grey.withOpacity(0.3),
//                             width: selected ? 2 : 1,
//                           ),
//                         ),
//                         child: Text(
//                           '/ $v',
//                           style: TextStyle(
//                             fontSize: 12,
//                             fontWeight: selected
//                                 ? FontWeight.w700
//                                 : FontWeight.normal,
//                             color: selected
//                                 ? Color(subject.color)
//                                 : Colors.grey,
//                           ),
//                         ),
//                       ),
//                     );
//                   }).toList(),
//                 ),
//                 const SizedBox(height: 20),
//                 ElevatedButton(
//                   onPressed: () {
//                     if (labelC.text.isEmpty || obtC.text.isEmpty) {
//                       ScaffoldMessenger.of(c).showSnackBar(
//                           const SnackBar(content: Text('Fill all fields')));
//                       return;
//                     }
//                     ctx.read<AppBloc>().add(AddMark(MarkModel(
//                       subjectId: subject.id,
//                       category: cat,
//                       label: labelC.text.trim(),
//                       obtained: double.tryParse(obtC.text) ?? 0,
//                       total: double.tryParse(totC.text) ?? 100,
//                     )));
//                     Navigator.pop(c);
//                   },
//                   style: ElevatedButton.styleFrom(
//                     backgroundColor: Color(subject.color),
//                     foregroundColor: Colors.white,
//                     padding: const EdgeInsets.symmetric(vertical: 14),
//                     shape: RoundedRectangleBorder(
//                         borderRadius: BorderRadius.circular(14)),
//                   ),
//                   child: const Text('Save',
//                       style: TextStyle(
//                           fontSize: 15, fontWeight: FontWeight.w600)),
//                 ),
//                 const SizedBox(height: 8),
//               ],
//             ),
//           ),
//         );
//       }),
//     );
//   }
//
//   Widget _tasksTab(BuildContext ctx, List<TaskModel> tasks, List<Subject> subs) {
//     final pending = tasks.where((t) => !t.isCompleted).toList();
//     final done = tasks.where((t) => t.isCompleted).toList();
//
//     if (tasks.isEmpty) {
//       return Center(
//         child: Column(mainAxisSize: MainAxisSize.min, children: [
//           Icon(Icons.task_rounded,
//               size: 44, color: Colors.grey.withOpacity(0.3)),
//           const SizedBox(height: 6),
//           const Text('No tasks', style: TextStyle(color: Colors.grey)),
//         ]),
//       );
//     }
//
//     return StatefulBuilder(builder: (ctx, setS) {
//       // Track collapsed state locally
//       return _TasksTabContent(
//         pending: pending,
//         done: done,
//         subs: subs,
//         buildCard: (t) => _subjectTaskCard(ctx, t, subs),
//         onShowDetails: (t) => _showSubjectTaskDetails(ctx, t, subs),
//       );
//     });
//   }
//
//   Widget _marksTab(BuildContext ctx, List<MarkModel> marks) {
//     final cats = <String, List<MarkModel>>{};
//     for (final m in marks) cats.putIfAbsent(m.category, () => []).add(m);
//     double totalObt = 0, totalMax = 0;
//     for (final m in marks) { totalObt += m.obtained; totalMax += m.total; }
//     final pct = totalMax > 0 ? totalObt / totalMax * 100 : 0.0;
//
//     final catLabels = {'midterm1': '5th Week Mid', 'midterm2': '10th Week Mid', 'quiz': 'Quizzes', 'assignment': 'Assignments',
//       'project': 'Projects', 'report': 'Reports', 'final': 'Final', 'other': 'Other'};
//
//     return ListView(physics: const BouncingScrollPhysics(), padding: const EdgeInsets.all(8), children: [
//       Glass(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
//         SizedBox(width: 70, height: 70, child: Stack(fit: StackFit.expand, children: [
//           CircularProgressIndicator(value: (pct / 100).clamp(0, 1), strokeWidth: 7,
//               backgroundColor: Colors.grey.withOpacity(0.15), valueColor: AlwaysStoppedAnimation(Color(subject.color))),
//           Center(child: Text('${pct.toStringAsFixed(0)}%', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(subject.color)))),
//         ])),
//         const SizedBox(width: 20),
//         Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
//           Text('${totalObt.toStringAsFixed(1)} / ${totalMax.toStringAsFixed(1)}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
//           Text('GPA estimate: ${_estimateGrade(pct)}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
//           Text('${marks.length} entries', style: const TextStyle(fontSize: 11, color: Colors.grey)),
//         ]),
//       ])),
//       if (marks.isNotEmpty)
//         Glass(
//           child: SizedBox(height: 160, child: BarChart(BarChartData(
//             alignment: BarChartAlignment.spaceAround, maxY: 100,
//             barTouchData: BarTouchData(enabled: true,
//                 touchTooltipData: BarTouchTooltipData(
//                     getTooltipItem: (g, gi, r, ri) => BarTooltipItem('${r.toY.toStringAsFixed(1)}%', const TextStyle(color: Colors.white, fontSize: 11)))),
//             titlesData: FlTitlesData(
//               leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28,
//                   getTitlesWidget: (v, _) => Text('${v.toInt()}', style: const TextStyle(fontSize: 9)))),
//               bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true,
//                   getTitlesWidget: (v, _) {
//                     final idx = v.toInt();
//                     if (idx < marks.length) return Padding(padding: const EdgeInsets.only(top: 4), child: Text(marks[idx].label.length > 6 ? '${marks[idx].label.substring(0, 6)}..' : marks[idx].label, style: const TextStyle(fontSize: 8)));
//                     return const Text('');
//                   })),
//               topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
//               rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
//             ),
//             gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 25),
//             borderData: FlBorderData(show: false),
//             barGroups: List.generate(marks.length, (i) => BarChartGroupData(x: i, barRods: [
//               BarChartRodData(toY: marks[i].percentage.clamp(0, 100), color: Color(subject.color), width: max(8, 24 - marks.length * 1.5), borderRadius: BorderRadius.circular(4)),
//             ])),
//           ))),
//         ),
//       ...cats.entries.map((e) {
//         final catTotal = e.value.fold<double>(0, (s, m) => s + m.obtained);
//         final catMax = e.value.fold<double>(0, (s, m) => s + m.total);
//         return Glass(
//           padding: const EdgeInsets.all(12),
//           child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
//             Row(children: [
//               Text(catLabels[e.key] ?? e.key, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(subject.color))),
//               const Spacer(),
//               Text('${catTotal.toStringAsFixed(1)}/${catMax.toStringAsFixed(1)}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
//             ]),
//             const SizedBox(height: 6),
//             ...e.value.map((m) => Padding(
//               padding: const EdgeInsets.symmetric(vertical: 2),
//               child: Row(children: [
//                 const SizedBox(width: 8),
//                 Expanded(child: Text(m.label, style: const TextStyle(fontSize: 12))),
//                 Text('${m.obtained.toStringAsFixed(1)}/${m.total.toStringAsFixed(1)}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
//                 const SizedBox(width: 4),
//                 Text('${m.percentage.toStringAsFixed(0)}%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
//                     color: m.percentage >= 85 ? const Color(0xFF2ED573) : m.percentage >= 60 ? const Color(0xFFFF9F43) : const Color(0xFFFF4757))),
//                 IconButton(icon: const Icon(Icons.close, size: 16, color: Colors.red), onPressed: () => ctx.read<AppBloc>().add(DeleteMark(m.id!)),
//                     constraints: const BoxConstraints(), padding: const EdgeInsets.only(left: 4)),
//               ]),
//             )),
//           ]),
//         );
//       }),
//       const SizedBox(height: 8),
//       Padding(
//         padding: const EdgeInsets.symmetric(horizontal: 16),
//         child: ElevatedButton.icon(
//           onPressed: () => _showAddMark(ctx),
//           icon: const Icon(Icons.add_rounded),
//           label: const Text('Add Mark'),
//           style: ElevatedButton.styleFrom(backgroundColor: Color(subject.color), foregroundColor: Colors.white,
//               padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
//         ),
//       ),
//     ]);
//   }
//
//   Widget _attendanceTab(BuildContext ctx, List<Map<String, dynamic>> abs, int lC, int sC, int labC) {
//     final s = subject;
//     return ListView(physics: const BouncingScrollPhysics(), padding: const EdgeInsets.all(8), children: [
//       // Visual summary
//       Glass(
//         child: Column(children: [
//           const Text('Attendance Overview', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
//           const SizedBox(height: 16),
//           SizedBox(
//             height: 160,
//             child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
//               _ring('Lecture', lC, s.maxLectureAbs, Color(s.color)),
//               if (s.hasSection) _ring('Section', sC, s.maxSectionAbs, Colors.teal),
//               if (s.hasLab) _ring('Lab', labC, s.maxLabAbs, Colors.orange),
//             ]),
//           ),
//         ]),
//       ),
//       _absCard(ctx, 'Lectures', lC, s.maxLectureAbs, 'lecture', Color(s.color)),
//       if (s.hasSection) _absCard(ctx, 'Sections', sC, s.maxSectionAbs, 'section', Colors.teal),
//       if (s.hasLab) _absCard(ctx, 'Labs', labC, s.maxLabAbs, 'lab', Colors.orange),
//       if (abs.isNotEmpty) ...[
//         const Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 4), child: Text('Records', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
//         ...abs.map((a) => Glass(
//           padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
//           child: Row(children: [
//             Icon(a['type'] == 'lecture' ? Icons.school_rounded : a['type'] == 'section' ? Icons.engineering_rounded : Icons.science_rounded,
//                 size: 18, color: Color(s.color)),
//             const SizedBox(width: 10),
//             Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
//               Text('${(a['type'] as String)[0].toUpperCase()}${(a['type'] as String).substring(1)}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
//               Text(a['date'] ?? '', style: const TextStyle(fontSize: 10, color: Colors.grey)),
//             ])),
//             IconButton(icon: const Icon(Icons.close_rounded, color: Colors.red, size: 18),
//                 onPressed: () => ctx.read<AppBloc>().add(DeleteAbsence(a['id']))),
//           ]),
//         )),
//       ],
//     ]);
//   }
//
//   Widget _absCard(BuildContext ctx, String label, int cur, int max, String type, Color color) {
//     return Glass(
//       child: Row(children: [
//         Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
//           Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: color)),
//           const SizedBox(height: 4),
//           ClipRRect(borderRadius: BorderRadius.circular(4),
//               child: LinearProgressIndicator(value: (max > 0 ? cur / max : 0.0).clamp(0, 1), minHeight: 6,
//                   backgroundColor: Colors.grey.withOpacity(0.15), valueColor: AlwaysStoppedAnimation(cur >= max ? const Color(0xFFFF4757) : color))),
//           const SizedBox(height: 2),
//           Text('$cur / $max', style: const TextStyle(fontSize: 11, color: Colors.grey)),
//         ])),
//         const SizedBox(width: 12),
//         ElevatedButton(
//           onPressed: () async {
//             final date = await showDatePicker(context: ctx, initialDate: DateTime.now(),
//                 firstDate: DateTime.now().subtract(const Duration(days: 180)), lastDate: DateTime.now().add(const Duration(days: 30)));
//             if (date != null) ctx.read<AppBloc>().add(AddAbsence(subject.id!, intl.DateFormat('yyyy-MM-dd').format(date), type));
//           },
//           style: ElevatedButton.styleFrom(backgroundColor: color.withOpacity(0.15), foregroundColor: color, elevation: 0,
//               padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
//           child: const Text('+ Add', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
//         ),
//       ]),
//     );
//   }
//
//   Widget _subjectTaskCard(
//       BuildContext ctx, TaskModel t, List<Subject> subs) {
//     return Dismissible(
//       key: Key('st${t.id}_${t.isCompleted}'), // KEY FIX: unique key per state
//       confirmDismiss: (direction) async {
//         if (direction == DismissDirection.endToStart) {
//           // DELETE
//           final ok = await showDialog<bool>(
//             context: ctx,
//             builder: (c) => AlertDialog(
//               shape: RoundedRectangleBorder(
//                   borderRadius: BorderRadius.circular(20)),
//               title: const Text('Delete Task?'),
//               content:
//               Text('Are you sure you want to delete "${t.title}"?'),
//               actions: [
//                 TextButton(
//                     onPressed: () => Navigator.pop(c, false),
//                     child: const Text('Cancel')),
//                 TextButton(
//                     onPressed: () => Navigator.pop(c, true),
//                     child: const Text('Delete',
//                         style: TextStyle(color: Color(0xFFFF4757)))),
//               ],
//             ),
//           ) ??
//               false;
//           if (ok) ctx.read<AppBloc>().add(DeleteTask(t.id!));
//           return ok; // only dismiss if actually deleted
//         } else if (direction == DismissDirection.startToEnd) {
//           // TOGGLE — never actually dismiss, just toggle
//           final action =
//           t.isCompleted ? 'mark as pending' : 'mark as done';
//           final ok = await showDialog<bool>(
//             context: ctx,
//             builder: (c) => AlertDialog(
//               shape: RoundedRectangleBorder(
//                   borderRadius: BorderRadius.circular(20)),
//               title: Text(
//                   t.isCompleted ? 'Mark as Pending?' : 'Mark as Done?'),
//               content:
//               Text('Do you want to $action "${t.title}"?'),
//               actions: [
//                 TextButton(
//                     onPressed: () => Navigator.pop(c, false),
//                     child: const Text('Cancel')),
//                 TextButton(
//                     onPressed: () => Navigator.pop(c, true),
//                     child: Text(
//                         t.isCompleted ? 'Mark Pending' : 'Mark Done',
//                         style: const TextStyle(
//                             color: Color(0xFF2ED573)))),
//               ],
//             ),
//           ) ??
//               false;
//           if (ok) ctx.read<AppBloc>().add(ToggleTask(t.id!, !t.isCompleted));
//           return false; // NEVER dismiss — widget moves between lists
//         }
//         return false;
//       },
//       background: Container(
//         margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
//         decoration: BoxDecoration(
//           color: const Color(0xFF2ED573),
//           borderRadius: BorderRadius.circular(20),
//         ),
//         alignment: Alignment.centerLeft,
//         padding: const EdgeInsets.only(left: 24),
//         child: Row(mainAxisSize: MainAxisSize.min, children: [
//           Icon(
//               t.isCompleted
//                   ? Icons.undo_rounded
//                   : Icons.check_circle_rounded,
//               color: Colors.white,
//               size: 28),
//           const SizedBox(width: 8),
//           Text(t.isCompleted ? 'Undo' : 'Done',
//               style: const TextStyle(
//                   color: Colors.white,
//                   fontWeight: FontWeight.w700,
//                   fontSize: 16)),
//         ]),
//       ),
//       secondaryBackground: Container(
//         margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
//         decoration: BoxDecoration(
//           color: const Color(0xFFFF4757),
//           borderRadius: BorderRadius.circular(20),
//         ),
//         alignment: Alignment.centerRight,
//         padding: const EdgeInsets.only(right: 24),
//         child: const Row(mainAxisSize: MainAxisSize.min, children: [
//           Text('Delete',
//               style: TextStyle(
//                   color: Colors.white,
//                   fontWeight: FontWeight.w700,
//                   fontSize: 16)),
//           SizedBox(width: 8),
//           Icon(Icons.delete_rounded, color: Colors.white, size: 28),
//         ]),
//       ),
//       child: Glass(
//         padding: EdgeInsets.zero,
//         child: InkWell(
//           borderRadius: BorderRadius.circular(20),
//           onTap: () => _showSubjectTaskDetails(ctx, t, subs),
//           child: Padding(
//             padding: const EdgeInsets.all(12),
//             child: Row(children: [
//               Container(
//                 width: 4,
//                 height: 44,
//                 decoration: BoxDecoration(
//                   color: t.priorityColor,
//                   borderRadius: BorderRadius.circular(4),
//                 ),
//               ),
//               const SizedBox(width: 10),
//               GestureDetector(
//                 onTap: () => ctx
//                     .read<AppBloc>()
//                     .add(ToggleTask(t.id!, !t.isCompleted)),
//                 child: Container(
//                   width: 22,
//                   height: 22,
//                   decoration: BoxDecoration(
//                     shape: BoxShape.circle,
//                     color: t.isCompleted
//                         ? const Color(0xFF2ED573)
//                         : Colors.transparent,
//                     border: Border.all(
//                       color: t.isCompleted
//                           ? const Color(0xFF2ED573)
//                           : t.priorityColor,
//                       width: 2,
//                     ),
//                   ),
//                   child: t.isCompleted
//                       ? const Icon(Icons.check,
//                       size: 13, color: Colors.white)
//                       : null,
//                 ),
//               ),
//               const SizedBox(width: 10),
//               Expanded(
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     AText(t.title,
//                         style: TextStyle(
//                           fontWeight: FontWeight.w600,
//                           fontSize: 13,
//                           decoration: t.isCompleted
//                               ? TextDecoration.lineThrough
//                               : null,
//                         )),
//                     if (t.dueDate != null)
//                       Text(
//                         intl.DateFormat('MMM d, h:mm a')
//                             .format(t.dueDate!),
//                         style: const TextStyle(
//                             fontSize: 10, color: Colors.grey),
//                       ),
//                   ],
//                 ),
//               ),
//               Column(
//                 crossAxisAlignment: CrossAxisAlignment.end,
//                 children: [
//                   Container(
//                     padding: const EdgeInsets.symmetric(
//                         horizontal: 7, vertical: 2),
//                     decoration: BoxDecoration(
//                       color: t.priorityColor.withOpacity(0.15),
//                       borderRadius: BorderRadius.circular(10),
//                     ),
//                     child: Text(t.priorityLabel,
//                         style: TextStyle(
//                             fontSize: 9,
//                             color: t.priorityColor,
//                             fontWeight: FontWeight.w600)),
//                   ),
//                   const SizedBox(height: 4),
//                   if (t.isCompleted)
//                     Container(
//                       padding: const EdgeInsets.symmetric(
//                           horizontal: 6, vertical: 2),
//                       decoration: BoxDecoration(
//                         color:
//                         const Color(0xFF2ED573).withOpacity(0.15),
//                         borderRadius: BorderRadius.circular(10),
//                       ),
//                       child: const Text('Done',
//                           style: TextStyle(
//                               fontSize: 9,
//                               color: Color(0xFF2ED573),
//                               fontWeight: FontWeight.w600)),
//                     ),
//                 ],
//               ),
//             ]),
//           ),
//         ),
//       ),
//     );
//   }
//
//   void _showSubjectTaskDetails(
//       BuildContext context, TaskModel t, List<Subject> subs)
//   {
//     showModalBottomSheet(
//       context: context,
//       isScrollControlled: true,
//       backgroundColor: Colors.transparent,
//       builder: (ctx) {
//         final d = Theme.of(ctx).brightness == Brightness.dark;
//         return Container(
//           padding: const EdgeInsets.all(24),
//           decoration: BoxDecoration(
//             color: d ? const Color(0xFF12122A) : Colors.white,
//             borderRadius:
//             const BorderRadius.vertical(top: Radius.circular(28)),
//           ),
//           child: Column(
//             mainAxisSize: MainAxisSize.min,
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Center(
//                 child: Container(
//                   width: 40,
//                   height: 4,
//                   decoration: BoxDecoration(
//                     color: Colors.grey.withOpacity(0.3),
//                     borderRadius: BorderRadius.circular(2),
//                   ),
//                 ),
//               ),
//               const SizedBox(height: 20),
//               Row(children: [
//                 Icon(t.typeIcon, color: t.priorityColor, size: 28),
//                 const SizedBox(width: 10),
//                 Expanded(
//                   child: AText(t.title,
//                       style: const TextStyle(
//                           fontSize: 22, fontWeight: FontWeight.bold)),
//                 ),
//                 if (t.isCompleted)
//                   Container(
//                     padding: const EdgeInsets.symmetric(
//                         horizontal: 10, vertical: 4),
//                     decoration: BoxDecoration(
//                       color: const Color(0xFF2ED573).withOpacity(0.15),
//                       borderRadius: BorderRadius.circular(12),
//                     ),
//                     child: const Row(
//                       mainAxisSize: MainAxisSize.min,
//                       children: [
//                         Icon(Icons.check_circle_rounded,
//                             size: 14, color: Color(0xFF2ED573)),
//                         SizedBox(width: 4),
//                         Text('Done',
//                             style: TextStyle(
//                                 fontSize: 12,
//                                 color: Color(0xFF2ED573),
//                                 fontWeight: FontWeight.w600)),
//                       ],
//                     ),
//                   ),
//               ]),
//               const SizedBox(height: 10),
//               Row(children: [
//                 _detailChipLocal(Icons.menu_book_rounded,
//                     subjectName(subs, t.subjectId)),
//                 const SizedBox(width: 8),
//                 _detailChipLocal(
//                     Icons.priority_high_rounded,
//                     "${t.priorityLabel} Priority",
//                     color: t.priorityColor),
//                 const SizedBox(width: 8),
//                 _detailChipLocal(
//                   Icons.category_rounded,
//                   t.type[0].toUpperCase() + t.type.substring(1),
//                 ),
//               ]),
//               const Divider(height: 30),
//               const Text("Description",
//                   style: TextStyle(
//                       fontWeight: FontWeight.bold, color: Colors.grey)),
//               const SizedBox(height: 8),
//               AText(
//                 t.description.isEmpty
//                     ? "No description provided."
//                     : t.description,
//                 style: const TextStyle(fontSize: 16),
//               ),
//               const SizedBox(height: 20),
//               if (t.dueDate != null) ...[
//                 const Text("Deadline",
//                     style: TextStyle(
//                         fontWeight: FontWeight.bold,
//                         color: Colors.grey)),
//                 const SizedBox(height: 8),
//                 Row(children: [
//                   const Icon(Icons.calendar_today_rounded,
//                       size: 18, color: Color(0xFF6C63FF)),
//                   const SizedBox(width: 8),
//                   Text(
//                     intl.DateFormat('EEEE, MMM d, yyyy')
//                         .format(t.dueDate!),
//                     style: const TextStyle(fontSize: 15),
//                   ),
//                 ]),
//                 const SizedBox(height: 4),
//                 Row(children: [
//                   const Icon(Icons.access_time_rounded,
//                       size: 18, color: Color(0xFF6C63FF)),
//                   const SizedBox(width: 8),
//                   Text(
//                     intl.DateFormat('h:mm a').format(t.dueDate!),
//                     style: const TextStyle(fontSize: 15),
//                   ),
//                 ]),
//                 const SizedBox(height: 8),
//                 // Time remaining
//                 Builder(builder: (_) {
//                   final now = DateTime.now();
//                   final diff = t.dueDate!.difference(now);
//                   String remaining;
//                   Color remainColor;
//                   if (diff.isNegative) {
//                     remaining = 'Overdue by ${diff.abs().inDays}d ${diff.abs().inHours % 24}h';
//                     remainColor = const Color(0xFFFF4757);
//                   } else if (diff.inDays > 0) {
//                     remaining = '${diff.inDays}d ${diff.inHours % 24}h remaining';
//                     remainColor = const Color(0xFF2ED573);
//                   } else if (diff.inHours > 0) {
//                     remaining = '${diff.inHours}h ${diff.inMinutes % 60}m remaining';
//                     remainColor = const Color(0xFFFF9F43);
//                   } else {
//                     remaining = '${diff.inMinutes}m remaining';
//                     remainColor = const Color(0xFFFF4757);
//                   }
//                   return Container(
//                     padding: const EdgeInsets.symmetric(
//                         horizontal: 12, vertical: 6),
//                     decoration: BoxDecoration(
//                       color: remainColor.withOpacity(0.1),
//                       borderRadius: BorderRadius.circular(10),
//                     ),
//                     child: Row(
//                       mainAxisSize: MainAxisSize.min,
//                       children: [
//                         Icon(Icons.timelapse_rounded,
//                             size: 16, color: remainColor),
//                         const SizedBox(width: 6),
//                         Text(remaining,
//                             style: TextStyle(
//                                 fontSize: 13,
//                                 fontWeight: FontWeight.w600,
//                                 color: remainColor)),
//                       ],
//                     ),
//                   );
//                 }),
//               ],
//               const SizedBox(height: 30),
//             ],
//           ),
//         );
//       },
//     );
//   }
//
//   Widget _detailChipLocal(IconData icon, String label,
//       {Color color = Colors.grey}) {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
//       decoration: BoxDecoration(
//         color: color.withOpacity(0.1),
//         borderRadius: BorderRadius.circular(10),
//       ),
//       child: Row(mainAxisSize: MainAxisSize.min, children: [
//         Icon(icon, size: 14, color: color),
//         const SizedBox(width: 5),
//         Text(label,
//             style: TextStyle(
//                 fontSize: 12,
//                 color: color,
//                 fontWeight: FontWeight.w600)),
//       ]),
//     );
//   }
//
// }

//
// Smart Advisor (FREE, no API)
// dart
//
// // Analyzes YOUR data and gives personalized advice
// // No internet needed — runs 100% on device
//
// "📊 Grade Analysis:
// • Structural Analysis: 78% — need 85% on midterm for B+
// • Fluid Mechanics: 82% — on track for B+
// • Math: 91% — excellent! Aim for A
//
// ⚡ Priority Tonight:
// 1. Fluid Mechanics Quiz tomorrow — study Ch.4
// 2. Math Sheet 5 — due in 2 days, haven't started
//
// 💡 Study Plan for this week:
// Mon: Fluid Mechanics (3h) — quiz prep
// Tue: Math (2h) — start sheet 5
// Wed: Structural (2h) — midterm prep
// Thu: Structural (3h) — practice problems
// Fri: Review everything (1h)"
//
//
// Smart Advisor (No API needed — FREE)
// Uses your own data to generate advice with pure logic/algorithms:
//
// text
//
// 🤖 Study Buddy says:
// "You have a Structural Analysis midterm in 5 days.
// Your current score is 73%. You need 82% on the midterm
// to reach a B+. I suggest studying 2 hours/day for the
// next 5 days. Focus on Chapter 4 — your quiz score there
// was the lowest."
// How: Just math + your marks + your tasks + your timetable. No internet needed.






