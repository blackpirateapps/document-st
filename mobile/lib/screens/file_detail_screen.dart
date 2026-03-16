import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import '../services/vault_provider.dart';
import '../models/vault_file.dart';
import '../theme/app_theme.dart';
import 'pdf_preview_screen.dart';
import 'package:intl/intl.dart';

class FileDetailScreen extends StatefulWidget {
  const FileDetailScreen({super.key});

  @override
  State<FileDetailScreen> createState() => _FileDetailScreenState();
}

class _FileDetailScreenState extends State<FileDetailScreen> {
  late TextEditingController _descController;
  late bool _starred;
  late List<Map<String, String>> _properties;
  bool _isSaving = false;
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    final file = context.read<VaultProvider>().selectedFile!;
    _descController = TextEditingController(text: file.description);
    _starred = file.starred;
    _properties = file.properties
        .map((p) => Map<String, String>.from(p))
        .toList();
  }

  @override
  void dispose() {
    _descController.dispose();
    super.dispose();
  }

  bool get _hasChanges {
    final file = context.read<VaultProvider>().selectedFile!;
    return _descController.text != file.description ||
        _starred != file.starred ||
        _propertiesChanged(file);
  }

  bool _propertiesChanged(VaultFile file) {
    if (_properties.length != file.properties.length) return true;
    for (int i = 0; i < _properties.length; i++) {
      if (_properties[i]['key'] != file.properties[i]['key'] ||
          _properties[i]['value'] != file.properties[i]['value']) {
        return true;
      }
    }
    return false;
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final vault = context.read<VaultProvider>();
      await vault.saveFileDetails(
        vault.selectedFile!,
        description: _descController.text,
        starred: _starred,
        properties: _properties,
      );
    } catch (_) {
      if (mounted) {
        showCupertinoDialog(
          context: context,
          builder: (ctx) => CupertinoAlertDialog(
            title: const Text('Error'),
            content: const Text('Failed to save changes.'),
            actions: [
              CupertinoDialogAction(
                child: const Text('OK'),
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _download() async {
    setState(() => _isDownloading = true);
    try {
      final vault = context.read<VaultProvider>();
      final file = vault.selectedFile!;
      final bytes = await vault.decryptFileForView(file);

      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/${file.originalName}';
      await File(filePath).writeAsBytes(bytes);
      await OpenFile.open(filePath);
    } catch (e) {
      if (mounted) {
        showCupertinoDialog(
          context: context,
          builder: (ctx) => CupertinoAlertDialog(
            title: const Text('Error'),
            content: Text('Download failed: $e'),
            actions: [
              CupertinoDialogAction(
                child: const Text('OK'),
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VaultProvider>(
      builder: (context, vault, _) {
        final file = vault.selectedFile;
        if (file == null) return const SizedBox.shrink();

        final isPdf = file.originalType == 'application/pdf';
        final folderName = vault.folderName(file.folderId);
        final dateStr = DateFormat(
          'MMMM d, yyyy · h:mm a',
        ).format(DateTime.parse(file.dateAdded));

        return CupertinoPageScaffold(
          backgroundColor: AppTheme.bgPrimary,
          navigationBar: CupertinoNavigationBar(
            backgroundColor: AppTheme.bgPrimary.withOpacity(0.9),
            border: Border(
              bottom: BorderSide(color: AppTheme.separator.withOpacity(0.3)),
            ),
            leading: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => vault.clearSelection(),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(CupertinoIcons.back, size: 20),
                  SizedBox(width: 2),
                  Text('Back', style: TextStyle(fontSize: 17)),
                ],
              ),
            ),
            middle: Text(
              file.originalName,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () => setState(() => _starred = !_starred),
                  child: Icon(
                    _starred ? CupertinoIcons.star_fill : CupertinoIcons.star,
                    size: 22,
                    color: _starred
                        ? AppTheme.systemOrange
                        : AppTheme.textSecondary,
                  ),
                ),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: _isDownloading ? null : _download,
                  child: _isDownloading
                      ? const CupertinoActivityIndicator(radius: 10)
                      : const Icon(CupertinoIcons.arrow_down_circle, size: 22),
                ),
              ],
            ),
          ),
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // File Header
                Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppTheme.fillTertiary,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        isPdf
                            ? CupertinoIcons.doc_text_fill
                            : CupertinoIcons.doc_fill,
                        size: 28,
                        color: AppTheme.accentBlue,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            file.originalName,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                              letterSpacing: -0.4,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_formatSize(file.size)} · ${file.originalType}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // PDF Preview button
                if (isPdf) ...[
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    color: AppTheme.accentBlueDim,
                    borderRadius: BorderRadius.circular(10),
                    onPressed: () {
                      Navigator.push(
                        context,
                        CupertinoPageRoute(
                          builder: (_) => PdfPreviewScreen(file: file),
                        ),
                      );
                    },
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          CupertinoIcons.eye,
                          size: 18,
                          color: AppTheme.accentBlue,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Preview PDF',
                          style: TextStyle(
                            color: AppTheme.accentBlue,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // Description
                _sectionLabel('DESCRIPTION'),
                const SizedBox(height: 8),
                CupertinoTextField(
                  controller: _descController,
                  placeholder: 'Add a description...',
                  maxLines: 4,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.fillQuaternary,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.borderColor),
                  ),
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 15,
                  ),
                  placeholderStyle: const TextStyle(
                    color: AppTheme.textTertiary,
                    fontSize: 15,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 24),

                // Properties
                _sectionLabel('PROPERTIES'),
                const SizedBox(height: 8),
                ..._properties.asMap().entries.map((entry) {
                  final i = entry.key;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: CupertinoTextField(
                            placeholder: 'Key',
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.fillQuaternary,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppTheme.borderColor),
                            ),
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 13,
                            ),
                            placeholderStyle: const TextStyle(
                              color: AppTheme.textTertiary,
                              fontSize: 13,
                            ),
                            controller: TextEditingController(
                              text: _properties[i]['key'],
                            ),
                            onChanged: (v) =>
                                setState(() => _properties[i]['key'] = v),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: CupertinoTextField(
                            placeholder: 'Value',
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.fillQuaternary,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppTheme.borderColor),
                            ),
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 13,
                            ),
                            placeholderStyle: const TextStyle(
                              color: AppTheme.textTertiary,
                              fontSize: 13,
                            ),
                            controller: TextEditingController(
                              text: _properties[i]['value'],
                            ),
                            onChanged: (v) =>
                                setState(() => _properties[i]['value'] = v),
                          ),
                        ),
                        const SizedBox(width: 4),
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () =>
                              setState(() => _properties.removeAt(i)),
                          child: const Icon(
                            CupertinoIcons.xmark_circle_fill,
                            size: 20,
                            color: AppTheme.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () =>
                      setState(() => _properties.add({'key': '', 'value': ''})),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        CupertinoIcons.plus,
                        size: 16,
                        color: AppTheme.accentBlue,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Add Property',
                        style: TextStyle(
                          color: AppTheme.accentBlue,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // File Info
                _sectionLabel('FILE INFO'),
                const SizedBox(height: 8),
                _infoCard([
                  _infoRow('Name', file.originalName),
                  _infoRow('Type', file.originalType),
                  _infoRow('Size', _formatSize(file.size)),
                  _infoRow('Folder', folderName),
                  _infoRow('Date Added', dateStr),
                  _infoRow('File ID', file.id, mono: true),
                ]),
                const SizedBox(height: 24),

                // Save button
                CupertinoButton(
                  color: AppTheme.accentBlue,
                  borderRadius: BorderRadius.circular(10),
                  onPressed: (_isSaving || !_hasChanges) ? null : _save,
                  child: _isSaving
                      ? const CupertinoActivityIndicator(
                          color: CupertinoColors.white,
                        )
                      : const Text(
                          'Save Changes',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 17,
                          ),
                        ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppTheme.textSecondary,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _infoCard(List<Widget> rows) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.fillQuaternary,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(children: rows),
    );
  }

  Widget _infoRow(String label, String value, {bool mono = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppTheme.borderColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.textPrimary,
                fontFamily: mono ? 'Menlo' : null,
                letterSpacing: mono ? -0.5 : -0.1,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}
