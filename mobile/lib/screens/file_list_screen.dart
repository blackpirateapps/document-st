import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';
import '../services/vault_provider.dart';
import '../models/vault_file.dart';
import '../theme/app_theme.dart';
import 'pdf_preview_screen.dart';
import 'package:intl/intl.dart';

class FileListScreen extends StatelessWidget {
  const FileListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 600;

    return Consumer<VaultProvider>(
      builder: (context, vault, _) {
        if (vault.isLoading) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CupertinoActivityIndicator(radius: 14),
                SizedBox(height: 16),
                Text(
                  'Decrypting vault...',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 15),
                ),
              ],
            ),
          );
        }

        final files = vault.currentFiles;
        final title = vault.folderName(vault.currentFolder);

        return Stack(
          children: [
            CustomScrollView(
              slivers: [
                // Navigation bar
                CupertinoSliverNavigationBar(
                  largeTitle: Text(title),
                  backgroundColor: AppTheme.bgPrimary.withOpacity(0.9),
                  border: Border(
                    bottom: BorderSide(
                      color: AppTheme.separator.withOpacity(0.3),
                    ),
                  ),
                  // Hamburger menu on mobile
                  leading: isWide
                      ? null
                      : CupertinoButton(
                          padding: EdgeInsets.zero,
                          onPressed: () => vault.toggleSidebar(),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              const Icon(
                                CupertinoIcons.line_horizontal_3,
                                size: 24,
                              ),
                              // Upload indicator badge
                              if (vault.hasActiveUploads)
                                Positioned(
                                  top: -2,
                                  right: -4,
                                  child: Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: AppTheme.accentBlue,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                  trailing: CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => vault.refresh(),
                    child: const Icon(CupertinoIcons.refresh, size: 22),
                  ),
                ),

                if (files.isEmpty)
                  SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            vault.currentFolder == 'starred'
                                ? CupertinoIcons.star
                                : vault.currentFolder == 'trash'
                                ? CupertinoIcons.trash
                                : CupertinoIcons.folder,
                            size: 48,
                            color: AppTheme.textTertiary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            vault.currentFolder == 'starred'
                                ? 'No starred files'
                                : vault.currentFolder == 'trash'
                                ? 'Trash is empty'
                                : 'No files in this folder',
                            style: const TextStyle(
                              color: AppTheme.textTertiary,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            vault.currentFolder == 'starred'
                                ? 'Star files to find them quickly'
                                : 'Tap + to upload a file',
                            style: const TextStyle(
                              color: AppTheme.textTertiary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final file = files[index];
                      return _FileRow(file: file);
                    }, childCount: files.length),
                  ),
              ],
            ),

            // FAB - Upload button
            Positioned(
              bottom: 32,
              right: 24,
              child: GestureDetector(
                onTap: () => _handleUpload(context, vault),
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppTheme.accentBlue,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.accentBlue.withOpacity(0.35),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    CupertinoIcons.plus,
                    color: CupertinoColors.white,
                    size: 26,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleUpload(BuildContext context, VaultProvider vault) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: true,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      // Queue all files for non-blocking upload
      for (final pickedFile in result.files) {
        if (pickedFile.bytes == null) continue;
        final mimeType =
            lookupMimeType(pickedFile.name) ?? 'application/octet-stream';
        await vault.uploadFile(
          Uint8List.fromList(pickedFile.bytes!),
          pickedFile.name,
          mimeType,
        );
      }
    } catch (e) {
      if (context.mounted) {
        _showError(context, 'Upload failed: $e');
      }
    }
  }

  static void _showError(BuildContext context, String message) {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            child: const Text('OK'),
            onPressed: () => Navigator.pop(ctx),
          ),
        ],
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  final VaultFile file;
  const _FileRow({required this.file});

  IconData _fileIcon(String mimeType) {
    if (mimeType.contains('pdf')) return CupertinoIcons.doc_text_fill;
    if (mimeType.contains('image')) return CupertinoIcons.photo_fill;
    if (mimeType.contains('video')) return CupertinoIcons.videocam_fill;
    if (mimeType.contains('audio')) return CupertinoIcons.music_note_2;
    if (mimeType.contains('zip') || mimeType.contains('archive')) {
      return CupertinoIcons.archivebox_fill;
    }
    return CupertinoIcons.doc_fill;
  }

  Color _fileColor(String mimeType) {
    if (mimeType.contains('pdf')) return const Color(0xFFFF453A);
    if (mimeType.contains('image')) return const Color(0xFF30D158);
    if (mimeType.contains('video')) return const Color(0xFFBF5AF2);
    if (mimeType.contains('audio')) return const Color(0xFFFF9F0A);
    return AppTheme.accentBlue;
  }

  @override
  Widget build(BuildContext context) {
    final vault = context.read<VaultProvider>();
    final dateStr = DateFormat(
      'MMM d, yyyy',
    ).format(DateTime.parse(file.dateAdded));
    final isPdf = file.originalType == 'application/pdf';
    final icon = _fileIcon(file.originalType);
    final color = _fileColor(file.originalType);

    return GestureDetector(
      onTap: () {
        if (isPdf) {
          Navigator.push(
            context,
            CupertinoPageRoute(builder: (_) => PdfPreviewScreen(file: file)),
          );
        } else {
          vault.selectFile(file);
        }
      },
      onLongPress: () => _showActions(context, vault),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppTheme.borderColor, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            // Star button
            GestureDetector(
              onTap: () => vault.toggleStar(file),
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Icon(
                  file.starred ? CupertinoIcons.star_fill : CupertinoIcons.star,
                  size: 18,
                  color: file.starred
                      ? AppTheme.systemOrange
                      : AppTheme.textTertiary,
                ),
              ),
            ),
            // File icon
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 12),
            // File info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.originalName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textPrimary,
                      letterSpacing: -0.2,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${_formatSize(file.size)} · $dateStr',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textTertiary,
                      letterSpacing: -0.1,
                    ),
                  ),
                ],
              ),
            ),
            // Chevron
            const Icon(
              CupertinoIcons.chevron_right,
              size: 14,
              color: AppTheme.textTertiary,
            ),
          ],
        ),
      ),
    );
  }

  void _showActions(BuildContext context, VaultProvider vault) {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(file.originalName),
        actions: [
          if (file.originalType == 'application/pdf')
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  CupertinoPageRoute(
                    builder: (_) => PdfPreviewScreen(file: file),
                  ),
                );
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(CupertinoIcons.eye, size: 18),
                  SizedBox(width: 8),
                  Text('Preview'),
                ],
              ),
            ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              vault.selectFile(file);
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.info_circle, size: 18),
                SizedBox(width: 8),
                Text('Details'),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _showRenameDialog(context, vault);
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.pencil, size: 18),
                SizedBox(width: 8),
                Text('Rename'),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _showMoveDialog(context, vault);
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.folder, size: 18),
                SizedBox(width: 8),
                Text('Move'),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await vault.copyFile(file);
              } catch (_) {}
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.doc_on_doc, size: 18),
                SizedBox(width: 8),
                Text('Copy'),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () async {
              Navigator.pop(ctx);
              final confirmed = await _confirmTrash(context);
              if (confirmed) {
                await vault.trashFile(file);
              }
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.trash, size: 18, color: AppTheme.dangerRed),
                SizedBox(width: 8),
                Text('Move to Trash'),
              ],
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          child: const Text('Cancel'),
          onPressed: () => Navigator.pop(ctx),
        ),
      ),
    );
  }

  Future<bool> _confirmTrash(BuildContext context) async {
    bool result = false;
    await showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Move to Trash?'),
        content: Text('Move "${file.originalName}" to trash?'),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(ctx),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('Trash'),
            onPressed: () {
              result = true;
              Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
    return result;
  }

  void _showRenameDialog(BuildContext context, VaultProvider vault) {
    final controller = TextEditingController(text: file.originalName);
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Rename File'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: controller,
            autofocus: true,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(ctx),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text('Save'),
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty && name != file.originalName) {
                await vault.renameFile(file, name);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  }

  void _showMoveDialog(BuildContext context, VaultProvider vault) {
    final allFolders = [
      {'id': 'inbox', 'name': 'Inbox'},
      {'id': 'documents', 'name': 'Documents'},
      {'id': 'photos', 'name': 'Photos'},
      {'id': 'taxes', 'name': 'Taxes'},
      ...vault.folders.map((f) => {'id': f.id, 'name': f.name}),
    ];

    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Move to Folder'),
        actions: allFolders
            .map(
              (f) => CupertinoActionSheetAction(
                onPressed: () async {
                  Navigator.pop(ctx);
                  if (f['id'] != file.folderId) {
                    await vault.moveFile(file, f['id']!);
                  }
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      f['id'] == file.folderId
                          ? CupertinoIcons.checkmark_circle_fill
                          : CupertinoIcons.folder,
                      size: 18,
                      color: f['id'] == file.folderId
                          ? AppTheme.accentBlue
                          : AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      f['name']!,
                      style: TextStyle(
                        fontWeight: f['id'] == file.folderId
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
        cancelButton: CupertinoActionSheetAction(
          child: const Text('Cancel'),
          onPressed: () => Navigator.pop(ctx),
        ),
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}
