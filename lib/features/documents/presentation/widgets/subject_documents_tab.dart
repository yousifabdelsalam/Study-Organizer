import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart' as intl;
import 'package:study_organizer/core/bloc/app_bloc.dart';
import 'package:study_organizer/core/bloc/app_event.dart';
import 'package:study_organizer/core/widgets/glass.dart';
import 'package:study_organizer/features/subjects/data/models/subject.dart';
import 'package:study_organizer/features/documents/data/models/study_document.dart';
import 'package:study_organizer/features/documents/data/services/document_brain_service.dart';
import 'package:study_organizer/features/documents/data/services/document_search_indexer.dart';
import 'package:study_organizer/features/exams/presentation/pages/exam_prep_hud_page.dart';
import 'package:study_organizer/features/exams/presentation/widgets/post_exam_analyzer.dart';
import 'package:study_organizer/features/nova_intelligence/data/services/nova_intelligence_engine.dart';
import 'package:study_organizer/core/database/database_helper.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

class SubjectDocumentsTab extends StatefulWidget {
  final Subject subject;
  final List<JarvisDocument> docs;
  final String instructorFocus;

  const SubjectDocumentsTab({super.key, 
    required this.subject,
    required this.docs,
    required this.instructorFocus,
  });

  @override
  State<SubjectDocumentsTab> createState() => _SubjectDocumentsTabState();
}

class _SubjectDocumentsTabState extends State<SubjectDocumentsTab> {
  late TextEditingController _focusController;
  bool _editingFocus = false;
  bool _uploadingFile = false;
  String _uploadStatus = 'AI is reading your file...';
  // â”€â”€ Intel Card â”€â”€
  String? _intelCard;
  bool _loadingCard = false;
  bool _generatingCard = false;

  @override
  void initState() {
    super.initState();
    _focusController = TextEditingController(text: widget.instructorFocus);
    _loadIntelCard();
  }

  @override
  void didUpdateWidget(SubjectDocumentsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editingFocus && oldWidget.instructorFocus != widget.instructorFocus) {
      _focusController.text = widget.instructorFocus;
    }
  }

  @override
  void dispose() {
    _focusController.dispose();
    super.dispose();
  }

  Future<void> _loadIntelCard() async {
    if (widget.subject.id == null) return;
    setState(() => _loadingCard = true);
    final card = await NovaIntelligenceEngine.loadIntelCard(widget.subject.id!);
    if (mounted)
      setState(() {
        _intelCard = card;
        _loadingCard = false;
      });
  }

  Future<void> _generateIntelCard() async {
    setState(() => _generatingCard = true);
    final card = await NovaIntelligenceEngine.generateIntelCard(widget.subject);
    if (mounted)
      setState(() {
        _intelCard = card.isEmpty ? null : card;
        _generatingCard = false;
      });
  }

  // â”€â”€ MIME type by file extension â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _intelCardSection() {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF39FF14).withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF39FF14).withOpacity(0.05),
            blurRadius: 12,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF39FF14).withOpacity(0.06),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(13),
              ),
              border: Border(
                bottom: BorderSide(
                  color: const Color(0xFF39FF14).withOpacity(0.15),
                ),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.insights_rounded,
                  color: Color(0xFF39FF14),
                  size: 16,
                ),
                const SizedBox(width: 8),
                const Text(
                  'NOVA  INTEL  CARD',
                  style: TextStyle(
                    color: Color(0xFF39FF14),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.5,
                    fontFamily: 'Courier',
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _generatingCard ? null : _generateIntelCard,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: const Color(0xFF39FF14).withOpacity(0.5),
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: _generatingCard
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF39FF14),
                            ),
                          )
                        : Text(
                            _intelCard == null ? '⚡ Generate' : '🔄 Regen',
                            style: const TextStyle(
                              color: Color(0xFF39FF14),
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
          // Body
          Padding(
            padding: const EdgeInsets.all(14),
            child: _loadingCard
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(
                        color: Color(0xFF39FF14),
                        strokeWidth: 2,
                      ),
                    ),
                  )
                : _intelCard == null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'No intel card yet.',
                        style: TextStyle(color: Colors.white38, fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Upload past exams and lecture notes first, then tap Generate. NOVA will analyze your instructor\'s exam pattern and predict likely questions.',
                        style: TextStyle(
                          color: Colors.white24,
                          fontSize: 11,
                          height: 1.5,
                        ),
                      ),
                    ],
                  )
                : SelectableText(
                    _intelCard!,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12.5,
                      height: 1.65,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  static String _mimeType(String ext) {
    switch (ext) {
      case 'pdf':
        return 'application/pdf';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case 'ppt':
        return 'application/vnd.ms-powerpoint';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      default:
        return 'text/plain';
    }
  }

  // â”€â”€ Sanitize text (prevent crashes from bad unicode) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  String _sanitizeText(String raw) {
    final buffer = StringBuffer();
    for (final rune in raw.runes) {
      if (rune == 0) continue;
      if (rune >= 0xD800 && rune <= 0xDFFF) continue;
      if (rune > 0x10FFFF) continue;
      buffer.writeCharCode(rune);
    }
    return buffer
        .toString()
        .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '')
        .trim();
  }

  void _showNoApiKeySnack() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Set your Gemini API key first: open NOVA overlay â†’ Settings (key icon)',
        ),
        duration: Duration(seconds: 5),
      ),
    );
  }

  // â”€â”€ MAIN UPLOAD FLOW â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  // Strategy:
  //   PDF/PPTX/Images â†’ Gemini Files API (upload once, get URI, use forever)
  //   TXT/MD           â†’ Read directly
  //
  // Why Files API?
  //   â€¢ Handles files up to 20MB natively
  //   â€¢ No base64 encoding (avoids payload limits)
  //   â€¢ No chunking PDF bytes (broken PDF = empty result)
  //   â€¢ Gemini reads the PDF as a document, not OCR
  //   â€¢ Same URI can be reused for deep analysis (Break Doctor Brain)
  Future<void> _pickAndAddDocument(String type) async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'pdf',
          'pptx',
          'ppt',
          'txt',
          'md',
          'jpg',
          'jpeg',
          'png',
        ],
        withData: false,
        allowMultiple: false,
      );
      if (picked == null || picked.files.single.path == null) return;

      final file = picked.files.single;
      final path = file.path!;
      final ext = path.split('.').last.toLowerCase();
      final name = file.name;

      // â”€â”€ Plain text: read directly â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      if (ext == 'txt' || ext == 'md') {
        setState(() {
          _uploadingFile = true;
          _uploadStatus = 'Reading file...';
        });
        String text = '';
        try {
          text = _sanitizeText(await File(path).readAsString());
        } catch (_) {}
        setState(() => _uploadingFile = false);
        if (text.isEmpty) {
          if (mounted)
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('File appears to be empty.')),
            );
          return;
        }
        if (mounted)
          _showAddDocSheet(name, text, type, fileUri: null, fileMime: null);
        return;
      }

      // â”€â”€ Binary files (PDF, PPTX, images): use Gemini Files API â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      final apiKey = await JarvisBrainService.getApiKey();
      if (apiKey == null || apiKey.isEmpty) {
        _showNoApiKeySnack();
        return;
      }

      final bytes = await File(path).readAsBytes();
      final fileSize = bytes.length;
      final mime = _mimeType(ext);

      setState(() {
        _uploadingFile = true;
        _uploadStatus =
            'Uploading ${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB to Gemini...';
      });

      // Step 1: Upload file to Gemini Files API â†’ get URI
      final uploaded = await JarvisBrainService.uploadFileToGemini(
        bytes: bytes,
        mimeType: mime,
        displayName: name,
        onStatus: (s) {
          if (mounted) setState(() => _uploadStatus = s);
        },
      );

      if (uploaded == null) {
        setState(() => _uploadingFile = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Upload failed. Check your API key and internet connection.',
              ),
              duration: Duration(seconds: 5),
            ),
          );
        }
        return;
      }

      final fileUri = uploaded['uri']!;
      final fileMime = uploaded['mimeType']!;

      // Step 2: Extract text using on-device PDF engine if PDF, otherwise Gemini Files API
      String extracted = '';
      if (ext == 'pdf') {
        setState(() => _uploadStatus = 'Extracting PDF text on-device...');
        extracted = DocumentSearchIndexer.extractTextFromPdfBytes(bytes);
      }
      if (extracted.isEmpty) {
        setState(() => _uploadStatus = 'Extracting text for search...');
        extracted = await JarvisBrainService.extractTextFromFileUri(
          fileUri: fileUri,
          mimeType: fileMime,
        );
      }

      setState(() => _uploadingFile = false);
      if (!mounted) return;

      // Show confirmation sheet. File URI is always valid even if text = empty.
      _showAddDocSheet(
        name,
        extracted,
        type,
        fileUri: fileUri,
        fileMime: fileMime,
      );
    } catch (e) {
      setState(() => _uploadingFile = false);
      debugPrint('_pickAndAddDocument error: $e');
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _showAddDocSheet(
    String defaultName,
    String extractedContent,
    String type, {
    required String? fileUri, // Gemini Files API URI (null for text files)
    required String? fileMime, // MIME type for the uploaded file
  }) {
    final nameController = TextEditingController(text: defaultName);
    final contentController = TextEditingController(text: extractedContent);
    final subjectId = widget.subject.id ?? 0;
    final charCount = extractedContent.length;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(c).size.height * 0.9,
          ),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(c).brightness == Brightness.dark
                ? const Color(0xFF12122A)
                : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
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
              Row(
                children: [
                  Icon(
                    type == 'past_exam'
                        ? Icons.quiz_rounded
                        : Icons.description_rounded,
                    color: type == 'past_exam'
                        ? Colors.orange
                        : const Color(0xFF6C63FF),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    type == 'past_exam' ? 'Add Past Exam' : 'Add Document',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.check_circle_rounded,
                    color: Colors.green,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    fileUri != null ? 'Uploaded ✓' : 'Ready',
                    style: const TextStyle(fontSize: 12, color: Colors.green),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      charCount > 0
                          ? '$charCount chars extracted'
                          : 'Use Brain analysis below',
                      style: TextStyle(
                        fontSize: 12,
                        color: charCount > 0 ? Colors.grey : Colors.orange,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: 'Name',
                  hintText: type == 'past_exam'
                      ? 'e.g. Midterm 2024'
                      : 'e.g. Chapter 3 notes',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: TextField(
                  controller: contentController,
                  maxLines: 6,
                  decoration: InputDecoration(
                    labelText: charCount > 0
                        ? 'Extracted text ($charCount chars, editable)'
                        : 'Could not extract text — Run "Break Doctor Brain" below for full AI analysis',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Save button
              ElevatedButton.icon(
                icon: const Icon(Icons.save_rounded),
                label: const Text('Save to NOVA Memory'),
                onPressed: () {
                  final docName = nameController.text.trim();
                  final docContent = contentController.text.trim();
                  if (docName.isEmpty) {
                    ScaffoldMessenger.of(c).showSnackBar(
                      const SnackBar(content: Text('Enter a name')),
                    );
                    return;
                  }
                  context.read<AppBloc>().add(
                    AddJarvisDocument(
                      JarvisDocument(
                        subjectId: subjectId,
                        type: type,
                        name: docName,
                        content: docContent,
                        fileUri: fileUri,
                        fileMime: fileMime,
                      ),
                    ),
                  );
                  Navigator.pop(c);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('\'$docName\' added to NOVA memory'),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C63FF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              // Break Doctor Brain button (only if file was uploaded via Files API)
              if (fileUri != null) ...[
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  icon: const Icon(Icons.psychology_alt_rounded),
                  label: const Text('🔬 Break Doctor Brain NOW'),
                  onPressed: () {
                    final docName = nameController.text.trim().isEmpty
                        ? defaultName
                        : nameController.text.trim();
                    final docContent = contentController.text.trim();
                    // Save first, then analyze
                    context.read<AppBloc>().add(
                      AddJarvisDocument(
                        JarvisDocument(
                          subjectId: subjectId,
                          type: type,
                          name: docName,
                          content: docContent,
                          fileUri: fileUri,
                          fileMime: fileMime,
                        ),
                      ),
                    );
                    Navigator.pop(c);
                    // Run deep analysis using file URI
                    _runDirectDeepAnalysis(
                      docName: docName,
                      docType: type,
                      fileUri: fileUri,
                      fileMime: fileMime!,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF4757),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                const Center(
                  child: Text(
                    'Analyze now — crack the exam pattern instantly',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // â”€â”€ Run deep analysis using file URI directly (no text extraction needed) â”€â”€
  Future<void> _runDirectDeepAnalysis({
    required String docName,
    required String docType,
    required String fileUri,
    required String fileMime,
  }) async {
    if (!mounted) return;

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF12122A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: StatefulBuilder(
          builder: (ctx, setS) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Color(0xFF6C63FF)),
              const SizedBox(height: 20),
              const Text(
                'ðŸ”¬ Breaking Doctor Brain...',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'NOVA is reading $docName\nThis takes 30-60 seconds.',
                style: const TextStyle(color: Colors.white60, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'Gemini is analyzing the document directly\n(not OCR â€” actual content understanding)',
                style: TextStyle(color: Colors.white38, fontSize: 10),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );

    final state = context.read<AppBloc>().state;
    final subject =
        state.subjects.where((s) => s.id == widget.subject.id).firstOrNull ??
        widget.subject;
    final subjectDocs = state.jarvisDocuments
        .where((d) => d.subjectId == widget.subject.id)
        .toList();
    final allContext = subjectDocs
        .map(
          (d) =>
              '[${d.name}]:\n${d.content.substring(0, d.content.length.clamp(0, 1500))}',
        )
        .join('\n\n');

    final analysis = await JarvisBrainService.analyzeFileDirectly(
      fileUri: fileUri,
      mimeType: fileMime,
      subjectName: subject.name,
      doctorName: subject.doctorName,
      docType: docType,
      docName: docName,
      allSubjectContext: allContext,
    );

    if (mounted) {
      Navigator.of(context).pop(); // Close loading
      _displayAnalysisReport(docName, analysis, fromCache: false);
    }
  }

  void _confirmDeleteDoc(JarvisDocument doc) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Remove from NOVA memory?'),
        content: Text(
          'Delete "${doc.name}"? NOVA will no longer have access to this content.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (doc.id != null)
                context.read<AppBloc>().add(DeleteJarvisDocument(doc.id!));
              Navigator.pop(c);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final subjectId = widget.subject.id ?? 0;
    final subjectColor = Color(widget.subject.color);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // â”€â”€ Instructor Focus Card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: subjectColor.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: subjectColor.withOpacity(0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.psychology_rounded, color: subjectColor, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Instructor Focus',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  const Spacer(),
                  if (widget.instructorFocus.isNotEmpty && !_editingFocus)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_rounded, size: 18),
                          color: Colors.grey,
                          onPressed: () => setState(() => _editingFocus = true),
                          tooltip: 'Edit',
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(4),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                          ),
                          color: Colors.redAccent,
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: const Text('Clear instructor focus?'),
                                content: const Text(
                                  'This will remove the focus note for this subject.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(c),
                                    child: const Text('Cancel'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () {
                                      context.read<AppBloc>().add(
                                        SetInstructorFocus(subjectId, ''),
                                      );
                                      Navigator.pop(c);
                                      setState(() {
                                        _focusController.text = '';
                                        _editingFocus = false;
                                      });
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
                                      foregroundColor: Colors.white,
                                    ),
                                    child: const Text('Clear'),
                                  ),
                                ],
                              ),
                            );
                          },
                          tooltip: 'Delete',
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(4),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'What does the instructor emphasize? NOVA uses this for exam advice.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 10),
              if (!_editingFocus && widget.instructorFocus.isNotEmpty)
                // Display mode
                GestureDetector(
                  onTap: () => setState(() => _editingFocus = true),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Text(
                      widget.instructorFocus,
                      style: const TextStyle(fontSize: 14, height: 1.4),
                    ),
                  ),
                )
              else
                // Edit mode
                Column(
                  children: [
                    TextField(
                      controller: _focusController,
                      maxLines: 3,
                      autofocus: _editingFocus,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText:
                            'e.g. Problem-solving, definitions from slides, past exam style',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        if (_editingFocus && widget.instructorFocus.isNotEmpty)
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => setState(() {
                                _focusController.text = widget.instructorFocus;
                                _editingFocus = false;
                              }),
                              child: const Text('Cancel'),
                            ),
                          ),
                        if (_editingFocus && widget.instructorFocus.isNotEmpty)
                          const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              context.read<AppBloc>().add(
                                SetInstructorFocus(
                                  subjectId,
                                  _focusController.text.trim(),
                                ),
                              );
                              setState(() => _editingFocus = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Saved. NOVA will use this.'),
                                ),
                              );
                            },
                            icon: const Icon(Icons.save_rounded, size: 16),
                            label: const Text('Save'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: subjectColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // ── EXAM PREPARATION BUTTON ──────────────────────────────────────────
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF7F00FF), Color(0xFFE100FF)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF7F00FF).withOpacity(0.4),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _runExamPrep,
              child: const Padding(
                padding: EdgeInsets.symmetric(
                  vertical: 18,
                  horizontal: 20,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.psychology_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'EXAM PREPARATION',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              letterSpacing: 1.2,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Full enigma breakdown + predictions + exam generator',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: Colors.white70,
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: 10),

        // ── POST-EXAM REVIEW BUTTON ───────────────────────────────────────────
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [const Color(0xFF1A1A2E), subjectColor.withOpacity(0.25)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: subjectColor.withOpacity(0.45)),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => PostExamAnalyzer.show(context, widget.subject),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 20,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.analytics_rounded,
                      color: subjectColor,
                      size: 28,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ANALYZE PAST EXAM',
                            style: TextStyle(
                              color: subjectColor,
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                              letterSpacing: 1.1,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Upload exam → NOVA reviews each question → saves mistakes to all future plans',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: subjectColor,
                      size: 14,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: 8),

        // ── NOVA Subject Intel Card ──────────────────────────────────────────
        _intelCardSection(),

        const SizedBox(height: 8),

        // â”€â”€ Documents & Past Exams â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        // â”€â”€ Documents & Past Exams â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
        Row(
          children: [
            const Icon(
              Icons.folder_special_rounded,
              color: Color(0xFF6C63FF),
              size: 20,
            ),
            const SizedBox(width: 8),
            const Text(
              'NOVA Memory',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const Spacer(),
            Text(
              '${widget.docs.length} files',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Feed NOVA with documents and past exams. Supports PDF, PowerPoint, and text files.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 12),

        // Upload buttons
        if (_uploadingFile)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF6C63FF).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF6C63FF),
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    _uploadStatus,
                    style: const TextStyle(color: Color(0xFF9D97FF)),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          )
        else
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickAndAddDocument('document'),
                  icon: const Icon(Icons.upload_file_rounded, size: 18),
                  label: const Text('Add Document'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF6C63FF),
                    side: const BorderSide(color: Color(0xFF6C63FF)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pickAndAddDocument('past_exam'),
                  icon: const Icon(Icons.quiz_rounded, size: 18),
                  label: const Text('Past Exam'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange,
                    side: const BorderSide(color: Colors.orange),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),

        const SizedBox(height: 8),
        // Supported formats hint
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.info_outline_rounded,
                size: 14,
                color: Colors.grey,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Supported: PDF, .pptx, .ppt, .txt, .md',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),
        _buildGapDetectorCard(context),
        const SizedBox(height: 16),

        // Documents list
        if (widget.docs.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(
                    Icons.folder_open_rounded,
                    size: 48,
                    color: Colors.grey.withOpacity(0.4),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'No files yet. Add a past exam or document.',
                    style: TextStyle(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        else
          ...widget.docs.map((d) => _docCard(d, subjectColor)),
      ],
    );
  }

  Widget _docCard(JarvisDocument d, Color subjectColor) {
    final isPastExam = d.isPastExam;
    final color = isPastExam ? Colors.orange : const Color(0xFF6C63FF);
    final charCount = d.content.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isPastExam ? Icons.quiz_rounded : Icons.description_rounded,
                  color: color,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isPastExam ? 'Past Exam' : 'Document',
                            style: TextStyle(
                              fontSize: 10,
                              color: color,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$charCount chars',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Deep analyze button
              IconButton(
                icon: const Icon(
                  Icons.psychology_alt_rounded,
                  color: Color(0xFF6C63FF),
                  size: 20,
                ),
                onPressed: () => _showDeepAnalysis(d),
                tooltip: 'Deep Analysis â€” Break the Doctor Brain',
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(8),
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.redAccent,
                  size: 20,
                ),
                onPressed: () => _confirmDeleteDoc(d),
                tooltip: 'Remove from NOVA memory',
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(8),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showDeepAnalysis(JarvisDocument doc) async {
    // Check cached analysis
    try {
      final db = await DatabaseHelper.instance.database;
      final cached = await db.query(
        'jarvis_doc_analysis',
        where: 'docId = ?',
        whereArgs: [doc.id ?? -1],
        limit: 1,
      );
      if (cached.isNotEmpty) {
        _displayAnalysisReport(
          doc.name,
          cached.first['analysis'] as String,
          fromCache: true,
        );
        return;
      }
    } catch (_) {}

    if (!mounted) return;

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF12122A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Color(0xFF6C63FF)),
            const SizedBox(height: 20),
            const Text(
              'ðŸ”¬ Breaking Doctor Brain...',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Analyzing ${doc.name}',
              style: const TextStyle(color: Colors.white60, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            const Text(
              '30-90 seconds â€” reading the full document',
              style: TextStyle(color: Colors.white38, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );

    final state = context.read<AppBloc>().state;
    final subjectDocs = state.jarvisDocuments
        .where((d) => d.subjectId == doc.subjectId)
        .toList();
    final allContext = subjectDocs
        .where((d) => d.id != doc.id) // exclude self to avoid duplication
        .map(
          (d) =>
              '[${d.name}]:\n${d.content.substring(0, d.content.length.clamp(0, 1500))}',
        )
        .join('\n\n');
    final subject = state.subjects
        .where((s) => s.id == doc.subjectId)
        .firstOrNull;

    // Use deepAnalyzeDocument with stored text content
    final analysis = await JarvisBrainService.deepAnalyzeDocument(
      subjectName: subject?.name ?? 'Unknown Subject',
      doctorName: subject?.doctorName ?? 'Unknown',
      docType: doc.type,
      docName: doc.name,
      content: doc.content,
      allSubjectContext: allContext,
    );

    // Cache it
    try {
      if (doc.id != null) {
        final db = await DatabaseHelper.instance.database;
        await db.insert(
          'jarvis_doc_analysis',
          {
            'subjectId': doc.subjectId,
            'docId': doc.id!,
            'analysis': analysis,
            'createdAt': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
        );
      }
    } catch (_) {}

    if (mounted) {
      Navigator.of(context).pop();
      _displayAnalysisReport(doc.name, analysis, fromCache: false);
    }
  }

  // â”€â”€ Shared beautiful report viewer â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  void _displayAnalysisReport(
    String title,
    String content, {
    bool fromCache = false,
    String subtitle = '',
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ReportViewerPage(
          title: title,
          subtitle: subtitle,
          content: content,
          fromCache: fromCache,
        ),
      ),
    );
  }

  // â”€â”€ Exam Prep launcher â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _runExamPrep() async {
    final state = context.read<AppBloc>().state;
    final subjectId = widget.subject.id ?? 0;
    final meta = state.subjectMetadata
        .where((m) => m.subjectId == subjectId)
        .firstOrNull;
    final focus = meta?.instructorFocus ?? '';

    // Open the new Iron Man HUD Dashboard
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ExamPrepHud(subject: widget.subject, instructorFocus: focus),
      ),
    );
  }

  Widget _buildGapDetectorCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.yellowAccent.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.yellowAccent.withOpacity(0.3)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            final studyDocs = widget.docs
                .where((d) => d.type == 'document')
                .toList();
            final pastExams = widget.docs
                .where((d) => d.type == 'past_exam')
                .toList();
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) => _GapDetectorDialog(
                subjectName: widget.subject.name,
                studyMaterials: studyDocs,
                pastExams: pastExams,
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.yellowAccent.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.radar_rounded,
                    color: Colors.yellowAccent,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Statistical Gap Detector',
                        style: TextStyle(
                          color: Colors.yellowAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Find untested topics by cross-referencing materials vs exams.',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.yellowAccent,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Tasks Tab helper (unchanged)
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _ReportViewerPage extends StatefulWidget {
  final String title;
  final String subtitle;
  final String content;
  final bool fromCache;
  const _ReportViewerPage({
    required this.title,
    required this.subtitle,
    required this.content,
    this.fromCache = false,
  });
  @override
  State<_ReportViewerPage> createState() => _ReportViewerPageState();
}

class _ReportViewerPageState extends State<_ReportViewerPage> {
  double _fontSize = 14;
  bool _copied = false;

  Future<void> _share() async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/jarvis_report.txt');
      await file.writeAsString(widget.content, encoding: utf8Codec);
      await Share.shareXFiles([XFile(file.path)], text: widget.title);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.content));
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      body: Column(
        children: [
          // â”€â”€ Header â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          Container(
            padding: EdgeInsets.fromLTRB(
              16,
              MediaQuery.of(context).padding.top + 8,
              16,
              16,
            ),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1A0050), Color(0xFF4A0080)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back_ios_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (widget.fromCache)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white12,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'CACHED',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
                if (widget.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Dr. ${widget.subtitle}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 12),
                // â”€â”€ Controls row â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                Row(
                  children: [
                    // Font size
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.text_decrease_rounded,
                              color: Colors.white70,
                              size: 18,
                            ),
                            onPressed: () => setState(
                              () => _fontSize = (_fontSize - 1).clamp(11, 22),
                            ),
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(8),
                          ),
                          Text(
                            '${_fontSize.toInt()}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.text_increase_rounded,
                              color: Colors.white70,
                              size: 18,
                            ),
                            onPressed: () => setState(
                              () => _fontSize = (_fontSize + 1).clamp(11, 22),
                            ),
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(8),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    // Copy
                    IconButton(
                      onPressed: _copy,
                      icon: Icon(
                        _copied ? Icons.check_rounded : Icons.copy_rounded,
                        color: _copied ? Colors.greenAccent : Colors.white70,
                        size: 20,
                      ),
                      tooltip: 'Copy to clipboard',
                    ),
                    // Export / share
                    IconButton(
                      onPressed: _share,
                      icon: const Icon(
                        Icons.share_rounded,
                        color: Colors.white70,
                        size: 20,
                      ),
                      tooltip: 'Export / Share',
                    ),
                  ],
                ),
              ],
            ),
          ),

          // â”€â”€ Content â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          Expanded(
            child: Markdown(
              data: widget.content,
              selectable: true,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              styleSheet: MarkdownStyleSheet(
                p: TextStyle(
                  color: const Color(0xFFE0E0FF),
                  fontSize: _fontSize,
                  height: 1.75,
                ),
                h1: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: _fontSize + 6,
                  height: 2.2,
                ),
                h2: TextStyle(
                  color: const Color(0xFFBB86FC),
                  fontWeight: FontWeight.w800,
                  fontSize: _fontSize + 4,
                  height: 2.0,
                ),
                h3: TextStyle(
                  color: const Color(0xFF03DAC6),
                  fontWeight: FontWeight.w700,
                  fontSize: _fontSize + 2,
                  height: 1.9,
                ),
                h4: TextStyle(
                  color: const Color(0xFFFF9800),
                  fontWeight: FontWeight.w700,
                  fontSize: _fontSize + 1,
                ),
                strong: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: _fontSize,
                ),
                em: TextStyle(
                  color: const Color(0xFFCFCFFF),
                  fontStyle: FontStyle.italic,
                  fontSize: _fontSize,
                ),
                code: TextStyle(
                  color: const Color(0xFF80CBC4),
                  backgroundColor: const Color(0xFF1E1E3A),
                  fontSize: _fontSize - 1,
                  fontFamily: 'monospace',
                ),
                blockquote: TextStyle(
                  color: const Color(0xFFB0BEC5),
                  fontSize: _fontSize,
                  fontStyle: FontStyle.italic,
                ),
                blockquoteDecoration: const BoxDecoration(
                  color: Color(0xFF1A1A3E),
                  border: Border(
                    left: BorderSide(color: Color(0xFF7F00FF), width: 4),
                  ),
                ),
                listBullet: TextStyle(
                  color: const Color(0xFFBB86FC),
                  fontSize: _fontSize,
                ),
                horizontalRuleDecoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Color(0xFF3A3A6A), width: 1),
                  ),
                ),
                tableHead: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: _fontSize,
                ),
                tableBody: TextStyle(
                  color: const Color(0xFFCCCCFF),
                  fontSize: _fontSize - 1,
                ),
                tableBorder: TableBorder.all(color: const Color(0xFF3A3A6A)),
                tableHeadAlign: TextAlign.center,
                blockSpacing: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const utf8Codec = Utf8Codec();

// =============================================================================
// EXAM PREP LAUNCHER â€” Language picker + mode selector
// =============================================================================
class _ExamPrepLauncher extends StatefulWidget {
  final String subjectName;
  final String doctorName;
  final int docCount;
  final int pastExamCount;
  const _ExamPrepLauncher({
    required this.subjectName,
    required this.doctorName,
    required this.docCount,
    required this.pastExamCount,
  });
  @override
  State<_ExamPrepLauncher> createState() => _ExamPrepLauncherState();
}

class _ExamPrepLauncherState extends State<_ExamPrepLauncher> {
  String _lang = 'english';

  void _launch(String mode) => Navigator.pop(context, '$_lang:$mode');

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D2B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Title
          Row(
            children: [
              const Text('ðŸ§ ', style: TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'EXAM PREPARATION',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                    Text(
                      '${widget.subjectName} â€” Dr. ${widget.doctorName}',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Stats
          Row(
            children: [
              _StatChip(
                icon: Icons.folder_rounded,
                label: '${widget.docCount} docs',
                color: const Color(0xFF6C63FF),
              ),
              const SizedBox(width: 8),
              _StatChip(
                icon: Icons.quiz_rounded,
                label: '${widget.pastExamCount} past exams',
                color: Colors.orange,
              ),
            ],
          ),

          if (widget.docCount == 0)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orange,
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Add documents and past exams for better predictions.',
                      style: TextStyle(color: Colors.orange, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 20),

          // Language selector
          const Text(
            'LANGUAGE',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _LangButton(
                  label: 'English',
                  active: _lang == 'english',
                  onTap: () => setState(() => _lang = 'english'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _LangButton(
                  label: 'Egyptian Arabic',
                  active: _lang == 'arabic',
                  onTap: () => setState(() => _lang = 'arabic'),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),
          const Text(
            'WHAT DO YOU NEED?',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),

          // Full analysis
          _ModeButton(
            icon: 'ðŸ”¬',
            title: 'Full Enigma Breakdown',
            subtitle: 'Doctor pattern analysis, predictions, study roadmap',
            color: const Color(0xFF7F00FF),
            onTap: () => _launch('analysis'),
          ),
          const SizedBox(height: 8),

          const Text(
            'GENERATE PREDICTED EXAM',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              Expanded(
                child: _ExamTypeButton(
                  label: '5th Week\nQuiz',
                  icon: 'ðŸ“',
                  onTap: () => _launch('week5'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ExamTypeButton(
                  label: 'Mid-\nterm',
                  icon: 'ðŸ“‹',
                  onTap: () => _launch('midterm'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ExamTypeButton(
                  label: '10th Week\nQuiz',
                  icon: 'ðŸ“',
                  onTap: () => _launch('week10'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ExamTypeButton(
                  label: 'Final\nExam',
                  icon: 'ðŸ',
                  onTap: () => _launch('final'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _StatChip({
    required this.icon,
    required this.label,
    required this.color,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withOpacity(0.15),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _LangButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _LangButton({
    required this.label,
    required this.active,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: active ? const Color(0xFF7F00FF) : Colors.white10,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active ? const Color(0xFF7F00FF) : Colors.white24,
        ),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: active ? Colors.white : Colors.white54,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    ),
  );
}

class _ModeButton extends StatelessWidget {
  final String icon, title, subtitle;
  final Color color;
  final VoidCallback onTap;
  const _ModeButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.3), color.withOpacity(0.1)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          Icon(Icons.arrow_forward_ios_rounded, color: color, size: 14),
        ],
      ),
    ),
  );
}

class _ExamTypeButton extends StatelessWidget {
  final String label, icon;
  final VoidCallback onTap;
  const _ExamTypeButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}

// =============================================================================
// EXAM PREP LOADING DIALOG
// =============================================================================
class _ExamPrepLoadingDialog extends StatelessWidget {
  final String mode;
  final String subjectName;
  const _ExamPrepLoadingDialog({required this.mode, required this.subjectName});

  @override
  Widget build(BuildContext context) {
    final messages = {
      'analysis': [
        'Gathering all subject data...',
        'Analyzing doctor\'s patterns...',
        'Breaking the exam code...',
        'Generating intelligence report...',
      ],
      'week5': [
        'Studying past exam patterns...',
        'Predicting 5th week topics...',
        'Generating quiz...',
      ],
      'midterm': [
        'Analyzing doctor\'s midterm style...',
        'Predicting exam structure...',
        'Generating predicted midterm...',
      ],
      'week10': [
        'Analyzing patterns...',
        'Predicting 10th week topics...',
        'Generating quiz...',
      ],
      'final': [
        'Analyzing ALL past exams...',
        'Decoding final exam patterns...',
        'Generating full predicted final...',
      ],
    };
    final msgs = messages[mode] ?? messages['analysis']!;

    return AlertDialog(
      backgroundColor: const Color(0xFF0D0D2B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          SizedBox(
            width: 60,
            height: 60,
            child: Stack(
              alignment: Alignment.center,
              children: [
                const CircularProgressIndicator(
                  color: Color(0xFF7F00FF),
                  strokeWidth: 3,
                ),
                const Text('ðŸ§ ', style: TextStyle(fontSize: 28)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'NOVA is working...',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subjectName,
            style: const TextStyle(color: Color(0xFFBB86FC), fontSize: 13),
          ),
          const SizedBox(height: 16),
          ...msgs.map(
            (m) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFF7F00FF),
                    size: 16,
                  ),
                  Text(
                    m,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '60-120 seconds',
            style: TextStyle(color: Colors.white24, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// â”€â”€ Saved Reports History â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _GapDetectorDialog extends StatefulWidget {
  final String subjectName;
  final List<JarvisDocument> studyMaterials;
  final List<JarvisDocument> pastExams;

  const _GapDetectorDialog({
    required this.subjectName,
    required this.studyMaterials,
    required this.pastExams,
  });

  @override
  State<_GapDetectorDialog> createState() => _GapDetectorDialogState();
}

class _GapDetectorDialogState extends State<_GapDetectorDialog> {
  bool _loading = true;
  String _analysis = '';

  @override
  void initState() {
    super.initState();
    _runAnalysis();
  }

  Future<void> _runAnalysis() async {
    final result = await JarvisBrainService.analyzeStatisticalGaps(
      subjectName: widget.subjectName,
      studyMaterials: widget.studyMaterials,
      pastExams: widget.pastExams,
    );
    if (!mounted) return;
    setState(() {
      _analysis = result;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Glass(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.radar_rounded,
                  color: Colors.yellowAccent,
                  size: 28,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'GAP DETECTOR',
                    style: TextStyle(
                      color: Colors.yellowAccent,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                if (!_loading && _analysis.isNotEmpty) ...[
                  IconButton(
                    onPressed: () => Share.share(_analysis),
                    icon: const Icon(
                      Icons.share,
                      color: Colors.yellowAccent,
                      size: 20,
                    ),
                    tooltip: 'Share Report',
                  ),
                  IconButton(
                    onPressed: () async {
                      final prefs = await SharedPreferences.getInstance();
                      final key = 'saved_reports_${widget.subjectName}';
                      final existing = prefs.getStringList(key) ?? [];
                      existing.insert(
                        0,
                        'Gap Analysis|${DateTime.now().toIso8601String()}|$_analysis',
                      );
                      await prefs.setStringList(key, existing);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('âœ… Report saved'),
                            backgroundColor: Color(0xFF00796B),
                          ),
                        );
                      }
                    },
                    icon: const Icon(
                      Icons.save,
                      color: Colors.yellowAccent,
                      size: 20,
                    ),
                    tooltip: 'Save Report',
                  ),
                ],
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white54),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Column(
                  children: [
                    CircularProgressIndicator(color: Colors.yellowAccent),
                    SizedBox(height: 16),
                    Text(
                      'Analyzing materials vs. exams...',
                      style: TextStyle(
                        color: Colors.yellowAccent,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              )
            else
              Flexible(
                child: SingleChildScrollView(
                  child: MarkdownBody(
                    data: _analysis,
                    styleSheet: MarkdownStyleSheet(
                      p: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        height: 1.6,
                      ),
                      h1: const TextStyle(
                        color: Colors.yellowAccent,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      h2: const TextStyle(
                        color: Colors.orangeAccent,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      h3: const TextStyle(
                        color: Colors.yellowAccent,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      strong: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      em: const TextStyle(
                        color: Colors.amber,
                        fontStyle: FontStyle.italic,
                      ),
                      listBullet: const TextStyle(color: Colors.yellowAccent),
                      blockquoteDecoration: const BoxDecoration(
                        border: Border(
                          left: BorderSide(
                            color: Colors.yellowAccent,
                            width: 3,
                          ),
                        ),
                      ),
                      blockquotePadding: const EdgeInsets.fromLTRB(
                        12,
                        8,
                        12,
                        8,
                      ),
                      tableHead: const TextStyle(
                        color: Colors.yellowAccent,
                        fontWeight: FontWeight.bold,
                      ),
                      tableBody: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                      tableBorder: TableBorder.all(color: Colors.white24),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

