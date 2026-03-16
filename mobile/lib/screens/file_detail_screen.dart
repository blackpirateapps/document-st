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

  IconData _fileTypeIcon(String mimeType) {
    if (mimeType.contains('pdf')) return CupertinoIcons.doc_text_fill;
    if (mimeType.contains('image')) return CupertinoIcons.photo_fill;
    if (mimeType.contains('video')) return CupertinoIcons.videocam_fill;
    if (mimeType.contains('audio')) return CupertinoIcons.music_note_2;
    if (mimeType.contains('zip') || mimeType.contains('archive')) {
      return CupertinoIcons.archivebox_fill;
    }
    if (mimeType.contains('text') ||
        mimeType.contains('json') ||
        mimeType.contains('xml') ||
        mimeType.contains('html')) {
      return CupertinoIcons.doc_plaintext;
    }
    if (mimeType.contains('spreadsheet') ||
        mimeType.contains('csv') ||
        mimeType.contains('excel')) {
      return CupertinoIcons.table_fill;
    }
    return CupertinoIcons.doc_fill;
  }

  Color _fileTypeColor(String mimeType) {
    if (mimeType.contains('pdf')) return const Color(0xFFFF453A);
    if (mimeType.contains('image')) return const Color(0xFF30D158);
    if (mimeType.contains('video')) return const Color(0xFFBF5AF2);
    if (mimeType.contains('audio')) return const Color(0xFFFF9F0A);
    if (mimeType.contains('zip') || mimeType.contains('archive')) {
      return const Color(0xFFAC8E68);
    }
    if (mimeType.contains('text') || mimeType.contains('json')) {
      return const Color(0xFF64D2FF);
    }
    return AppTheme.accentBlue;
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
        final typeIcon = _fileTypeIcon(file.originalType);
        final typeColor = _fileTypeColor(file.originalType);

        return CupertinoPageScaffold(
          backgroundColor: AppTheme.bgPrimary,
          navigationBar: CupertinoNavigationBar(
            backgroundColor: AppTheme.bgSecondary.withOpacity(0.95),
            border: Border(
              bottom: BorderSide(color: AppTheme.separator.withOpacity(0.2)),
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
            middle: const Text(
              'Details',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ),
          child: SafeArea(
            child: Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  children: [
                    // ── Hero Card ──
                    _buildHeroCard(file, typeIcon, typeColor, isPdf),
                    const SizedBox(height: 16),

                    // ── Quick Actions ──
                    _buildQuickActions(file, isPdf),
                    const SizedBox(height: 20),

                    // ── Description Section ──
                    _buildSectionCard(
                      title: 'Description',
                      icon: CupertinoIcons.text_alignleft,
                      child: CupertinoTextField(
                        controller: _descController,
                        placeholder: 'Add a description...',
                        maxLines: 4,
                        minLines: 2,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.bgPrimary.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(10),
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
                    ),
                    const SizedBox(height: 12),

                    // ── Properties Section ──
                    _buildSectionCard(
                      title: 'Custom Properties',
                      icon: CupertinoIcons.tag_fill,
                      child: _buildPropertiesContent(),
                    ),
                    const SizedBox(height: 12),

                    // ── File Information Section ──
                    _buildSectionCard(
                      title: 'File Information',
                      icon: CupertinoIcons.info_circle_fill,
                      child: Column(
                        children: [
                          _infoTile(
                            CupertinoIcons.doc,
                            'Name',
                            file.originalName,
                          ),
                          _infoTile(
                            CupertinoIcons.doc_chart,
                            'Type',
                            file.originalType,
                          ),
                          _infoTile(
                            CupertinoIcons.arrow_up_arrow_down,
                            'Size',
                            _formatSize(file.size),
                          ),
                          _infoTile(
                            CupertinoIcons.folder,
                            'Folder',
                            folderName,
                          ),
                          _infoTile(
                            CupertinoIcons.calendar,
                            'Date Added',
                            dateStr,
                          ),
                          _infoTile(
                            CupertinoIcons.number,
                            'File ID',
                            file.id,
                            mono: true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Security Section ──
                    _buildSectionCard(
                      title: 'Encryption',
                      icon: CupertinoIcons.lock_shield_fill,
                      child: Column(
                        children: [
                          _infoTile(
                            CupertinoIcons.shield_lefthalf_fill,
                            'Algorithm',
                            'AES-256-GCM',
                          ),
                          _infoTile(
                            CupertinoIcons.key_fill,
                            'Key Derivation',
                            'PBKDF2 (100k iterations)',
                          ),
                          _infoTile(
                            CupertinoIcons.checkmark_seal_fill,
                            'Status',
                            'End-to-end encrypted',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),

                // ── Sticky Save Bar ──
                if (_hasChanges)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      decoration: BoxDecoration(
                        color: AppTheme.bgSecondary.withOpacity(0.97),
                        border: Border(
                          top: BorderSide(
                            color: AppTheme.separator.withOpacity(0.2),
                          ),
                        ),
                      ),
                      child: CupertinoButton(
                        color: AppTheme.accentBlue,
                        borderRadius: BorderRadius.circular(12),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        onPressed: _isSaving ? null : _save,
                        child: _isSaving
                            ? const CupertinoActivityIndicator(
                                color: CupertinoColors.white,
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    CupertinoIcons.checkmark_alt,
                                    size: 18,
                                    color: CupertinoColors.white,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Save Changes',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 17,
                                      color: CupertinoColors.white,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Hero Card ──
  Widget _buildHeroCard(
    VaultFile file,
    IconData icon,
    Color color,
    bool isPdf,
  ) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withOpacity(0.12), AppTheme.bgSecondary],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.15), width: 0.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            // Large file type icon
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, size: 32, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.originalName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                      letterSpacing: -0.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _metaChip(
                        CupertinoIcons.arrow_up_arrow_down,
                        _formatSize(file.size),
                      ),
                      const SizedBox(width: 8),
                      _metaChip(
                        CupertinoIcons.folder,
                        context.read<VaultProvider>().folderName(file.folderId),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Star toggle
            CupertinoButton(
              padding: const EdgeInsets.all(8),
              onPressed: () => setState(() => _starred = !_starred),
              child: Icon(
                _starred ? CupertinoIcons.star_fill : CupertinoIcons.star,
                size: 24,
                color: _starred ? AppTheme.systemOrange : AppTheme.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metaChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.fillQuaternary,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: AppTheme.textSecondary),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              fontSize: 11,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ── Quick Actions Row ──
  Widget _buildQuickActions(VaultFile file, bool isPdf) {
    return Row(
      children: [
        if (isPdf) ...[
          Expanded(
            child: _actionButton(
              icon: CupertinoIcons.eye_fill,
              label: 'Preview',
              color: AppTheme.accentBlue,
              onTap: () => Navigator.push(
                context,
                CupertinoPageRoute(
                  builder: (_) => PdfPreviewScreen(file: file),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: _actionButton(
            icon: CupertinoIcons.arrow_down_to_line,
            label: 'Download',
            color: AppTheme.systemGreen,
            isLoading: _isDownloading,
            onTap: _isDownloading ? null : _download,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _actionButton(
            icon: CupertinoIcons.share,
            label: 'Share',
            color: AppTheme.systemOrange,
            onTap: _download, // reuse download for now
          ),
        ),
      ],
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    bool isLoading = false,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.15), width: 0.5),
        ),
        child: Column(
          children: [
            if (isLoading)
              CupertinoActivityIndicator(radius: 10, color: color)
            else
              Icon(icon, size: 22, color: color),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Section Card (frosted glass style) ──
  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgSecondary.withOpacity(0.8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppTheme.separator.withOpacity(0.15),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Icon(icon, size: 16, color: AppTheme.textSecondary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: child,
          ),
        ],
      ),
    );
  }

  // ── Properties Content ──
  Widget _buildPropertiesContent() {
    return Column(
      children: [
        ..._properties.asMap().entries.map((entry) {
          final i = entry.key;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppTheme.accentBlueDim,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Icon(
                    CupertinoIcons.tag,
                    size: 13,
                    color: AppTheme.accentBlue,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CupertinoTextField(
                    placeholder: 'Key',
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.bgPrimary.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    placeholderStyle: const TextStyle(
                      color: AppTheme.textTertiary,
                      fontSize: 14,
                    ),
                    controller: TextEditingController(
                      text: _properties[i]['key'],
                    ),
                    onChanged: (v) => setState(() => _properties[i]['key'] = v),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: CupertinoTextField(
                    placeholder: 'Value',
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.bgPrimary.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 14,
                    ),
                    placeholderStyle: const TextStyle(
                      color: AppTheme.textTertiary,
                      fontSize: 14,
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
                  minSize: 28,
                  onPressed: () => setState(() => _properties.removeAt(i)),
                  child: const Icon(
                    CupertinoIcons.minus_circle_fill,
                    size: 20,
                    color: AppTheme.dangerRed,
                  ),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: () =>
              setState(() => _properties.add({'key': '', 'value': ''})),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.accentBlueDim,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  CupertinoIcons.plus_circle_fill,
                  size: 16,
                  color: AppTheme.accentBlue,
                ),
                SizedBox(width: 6),
                Text(
                  'Add Property',
                  style: TextStyle(
                    color: AppTheme.accentBlue,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Info Tile ──
  Widget _infoTile(
    IconData icon,
    String label,
    String value, {
    bool mono = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppTheme.fillQuaternary,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(icon, size: 14, color: AppTheme.textSecondary),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 80,
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
              maxLines: 2,
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
