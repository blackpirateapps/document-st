import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';
import '../services/vault_provider.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: AppTheme.bgPrimary,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: AppTheme.bgSecondary.withOpacity(0.95),
        border: Border(
          bottom: BorderSide(color: AppTheme.separator.withOpacity(0.2)),
        ),
        middle: const Text(
          'Settings',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.pop(context),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(CupertinoIcons.back, size: 20),
              SizedBox(width: 2),
              Text('Back', style: TextStyle(fontSize: 17)),
            ],
          ),
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const SizedBox(height: 8),

            // ── Batch Upload Section ──
            _buildSection(
              title: 'Upload',
              icon: CupertinoIcons.cloud_upload_fill,
              children: [
                _SettingsTile(
                  icon: CupertinoIcons.folder_badge_plus,
                  iconColor: AppTheme.accentBlue,
                  title: 'Upload Files',
                  subtitle: 'Pick multiple files from your device',
                  onTap: () => _handleBatchUpload(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Vault Section ──
            _buildSection(
              title: 'Vault',
              icon: CupertinoIcons.lock_shield_fill,
              children: [
                _SettingsTile(
                  icon: CupertinoIcons.arrow_2_circlepath,
                  iconColor: AppTheme.systemGreen,
                  title: 'Sync Vault',
                  subtitle: 'Refresh data from server',
                  onTap: () {
                    context.read<VaultProvider>().refresh();
                    _showToast(context, 'Syncing vault...');
                  },
                ),
                _SettingsTile(
                  icon: CupertinoIcons.trash,
                  iconColor: AppTheme.systemOrange,
                  title: 'Clear Local Cache',
                  subtitle: 'Remove cached vault data from device',
                  onTap: () => _confirmClearCache(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Security Section ──
            _buildSection(
              title: 'Security',
              icon: CupertinoIcons.shield_fill,
              children: [
                _SettingsTile(
                  icon: CupertinoIcons.lock_fill,
                  iconColor: AppTheme.dangerRed,
                  title: 'Lock Vault',
                  subtitle: 'Lock and clear all decrypted data',
                  onTap: () => _confirmLock(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── About Section ──
            _buildSection(
              title: 'About',
              icon: CupertinoIcons.info_circle_fill,
              children: [
                const _SettingsTile(
                  icon: CupertinoIcons.shield_lefthalf_fill,
                  iconColor: AppTheme.accentBlue,
                  title: 'Encryption',
                  subtitle: 'AES-256-GCM with PBKDF2 key derivation',
                ),
                const _SettingsTile(
                  icon: CupertinoIcons.eye_slash_fill,
                  iconColor: AppTheme.textSecondary,
                  title: 'Zero Knowledge',
                  subtitle:
                      'Your data is encrypted before it leaves your device',
                ),
                _SettingsTile(
                  icon: CupertinoIcons.app_badge,
                  iconColor: AppTheme.textSecondary,
                  title: 'Version',
                  subtitle: '1.0.0',
                  onTap: () {},
                ),
              ],
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(
            children: [
              Icon(icon, size: 14, color: AppTheme.textSecondary),
              const SizedBox(width: 6),
              Text(
                title.toUpperCase(),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.bgSecondary.withOpacity(0.8),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppTheme.separator.withOpacity(0.15),
              width: 0.5,
            ),
          ),
          child: Column(
            children: [
              for (int i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1)
                  Padding(
                    padding: const EdgeInsets.only(left: 56),
                    child: Container(
                      height: 0.5,
                      color: AppTheme.separator.withOpacity(0.15),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _handleBatchUpload(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: true,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final vault = context.read<VaultProvider>();
      final filesToUpload = <Map<String, dynamic>>[];

      for (final pickedFile in result.files) {
        if (pickedFile.bytes == null) continue;
        final mimeType =
            lookupMimeType(pickedFile.name) ?? 'application/octet-stream';
        filesToUpload.add({
          'bytes': Uint8List.fromList(pickedFile.bytes!),
          'name': pickedFile.name,
          'mime': mimeType,
        });
      }

      if (filesToUpload.isEmpty) return;

      // Upload all files (non-blocking — they'll appear in sidebar progress)
      await vault.uploadFiles(filesToUpload);

      if (context.mounted) {
        _showToast(
          context,
          '${filesToUpload.length} file(s) queued for upload',
        );
        Navigator.pop(context); // Go back to main screen to see progress
      }
    } catch (e) {
      if (context.mounted) {
        showCupertinoDialog(
          context: context,
          builder: (ctx) => CupertinoAlertDialog(
            title: const Text('Upload Error'),
            content: Text('Failed to pick files: $e'),
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
  }

  void _confirmClearCache(BuildContext context) {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Clear Cache?'),
        content: const Text(
          'This will remove all locally cached vault data. '
          'You will need an internet connection to access your vault again.',
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(ctx),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('Clear'),
            onPressed: () async {
              await context.read<VaultProvider>().clearCache();
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) {
                _showToast(context, 'Cache cleared');
              }
            },
          ),
        ],
      ),
    );
  }

  void _confirmLock(BuildContext context) {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Lock Vault?'),
        content: const Text(
          'This will lock the vault and clear all decrypted data from memory. '
          'You will need to enter your master password again.',
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(ctx),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('Lock'),
            onPressed: () {
              context.read<VaultProvider>().lock();
              Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  }

  void _showToast(BuildContext context, String message) {
    showCupertinoDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        Future.delayed(const Duration(seconds: 2), () {
          if (ctx.mounted) Navigator.pop(ctx);
        });
        return Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.bgTertiary.withOpacity(0.95),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              message,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w500,
                decoration: TextDecoration.none,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 17, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textPrimary,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textTertiary,
                      letterSpacing: -0.1,
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null)
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
}
