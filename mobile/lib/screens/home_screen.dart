import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../services/vault_provider.dart';
import '../theme/app_theme.dart';
import '../models/vault_folder.dart';
import 'file_list_screen.dart';
import 'file_detail_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<VaultProvider>(
      builder: (context, vault, _) {
        if (vault.selectedFile != null) {
          return const FileDetailScreen();
        }
        return const _HomeLayout();
      },
    );
  }
}

class _HomeLayout extends StatelessWidget {
  const _HomeLayout();

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 600;

    return CupertinoPageScaffold(
      backgroundColor: AppTheme.bgPrimary,
      child: SafeArea(
        child: Stack(
          children: [
            Row(
              children: [
                // Sidebar visible on wide screens permanently
                if (isWide) const _Sidebar(),
                // Main content
                const Expanded(child: FileListScreen()),
              ],
            ),

            // Mobile drawer overlay
            if (!isWide)
              Consumer<VaultProvider>(
                builder: (context, vault, _) {
                  if (!vault.sidebarOpen) return const SizedBox.shrink();
                  return Stack(
                    children: [
                      // Backdrop
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 220),
                        builder: (context, opacity, child) {
                          return GestureDetector(
                            onTap: () => vault.closeSidebar(),
                            child: Container(
                              color: Color.fromRGBO(0, 0, 0, 0.6 * opacity),
                            ),
                          );
                        },
                      ),
                      // Drawer
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        child: TweenAnimationBuilder<Offset>(
                          tween: Tween(
                            begin: const Offset(-1, 0),
                            end: Offset.zero,
                          ),
                          duration: const Duration(milliseconds: 240),
                          curve: Curves.easeOutCubic,
                          builder: (context, offset, child) {
                            return FractionalTranslation(
                              translation: offset,
                              child: child,
                            );
                          },
                          child: const _Sidebar(),
                        ),
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar();

  @override
  Widget build(BuildContext context) {
    return Consumer<VaultProvider>(
      builder: (context, vault, _) {
        return Container(
          width: 280,
          decoration: const BoxDecoration(
            color: AppTheme.bgSecondary,
            border: Border(
              right: BorderSide(color: AppTheme.separator, width: 0.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 16, 16),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Vault',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    CupertinoButton(
                      padding: const EdgeInsets.all(6),
                      minSize: 0,
                      onPressed: () {
                        Navigator.push(
                          context,
                          CupertinoPageRoute(
                            builder: (_) => const SettingsScreen(),
                          ),
                        );
                      },
                      child: const Icon(
                        CupertinoIcons.gear,
                        size: 22,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),

              // Upload progress section
              _UploadProgressSection(),

              // Default folders
              _SidebarItem(
                icon: CupertinoIcons.square_stack_3d_down_right_fill,
                label: 'All Files',
                folderId: 'all',
                isActive: vault.currentFolder == 'all',
                count: vault.files.where((f) => f.folderId != 'trash').length,
              ),
              _SidebarItem(
                icon: CupertinoIcons.tray_fill,
                label: 'Inbox',
                folderId: 'inbox',
                isActive: vault.currentFolder == 'inbox',
                count: vault.files.where((f) => f.folderId == 'inbox').length,
              ),
              _SidebarItem(
                icon: CupertinoIcons.star_fill,
                label: 'Starred',
                folderId: 'starred',
                isActive: vault.currentFolder == 'starred',
                count: vault.files
                    .where((f) => f.starred && f.folderId != 'trash')
                    .length,
              ),
              _SidebarItem(
                icon: CupertinoIcons.doc_fill,
                label: 'Documents',
                folderId: 'documents',
                isActive: vault.currentFolder == 'documents',
                count: vault.files
                    .where((f) => f.folderId == 'documents')
                    .length,
              ),
              _SidebarItem(
                icon: CupertinoIcons.photo_fill,
                label: 'Photos',
                folderId: 'photos',
                isActive: vault.currentFolder == 'photos',
                count: vault.files.where((f) => f.folderId == 'photos').length,
              ),
              _SidebarItem(
                icon: CupertinoIcons.folder_fill,
                label: 'Taxes',
                folderId: 'taxes',
                isActive: vault.currentFolder == 'taxes',
                count: vault.files.where((f) => f.folderId == 'taxes').length,
              ),

              const SizedBox(height: 12),
              // Section header
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'FOLDERS',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textTertiary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () =>
                          _showCreateFolderDialog(context, vault, null),
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: AppTheme.fillQuaternary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: vault.isCreatingFolder
                            ? const CupertinoActivityIndicator(radius: 6)
                            : const Icon(
                                CupertinoIcons.plus,
                                size: 14,
                                color: AppTheme.textTertiary,
                              ),
                      ),
                    ),
                  ],
                ),
              ),

              // Custom folders tree
              Expanded(
                child: vault.rootFolders.isEmpty
                    ? const Center(
                        child: Text(
                          'No custom folders',
                          style: TextStyle(
                            color: AppTheme.textTertiary,
                            fontSize: 13,
                          ),
                        ),
                      )
                    : ListView(
                        padding: EdgeInsets.zero,
                        children: vault.rootFolders
                            .map((f) => _FolderTreeItem(folder: f, depth: 0))
                            .toList(),
                      ),
              ),

              // Trash + file count
              Container(
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: AppTheme.separator, width: 0.5),
                  ),
                ),
                child: _SidebarItem(
                  icon: CupertinoIcons.trash_fill,
                  label: 'Trash',
                  folderId: 'trash',
                  isActive: vault.currentFolder == 'trash',
                  count: vault.files.where((f) => f.folderId == 'trash').length,
                ),
              ),

              // Total files count
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Text(
                  '${vault.files.length} files in vault',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.textTertiary,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static void _showCreateFolderDialog(
    BuildContext context,
    VaultProvider vault,
    String? parentId,
  ) {
    final controller = TextEditingController();
    showCupertinoDialog(
      context: context,
      builder: (ctx) {
        bool creating = false;
        return StatefulBuilder(
          builder: (context, setState) => CupertinoAlertDialog(
            title: Text(parentId != null ? 'New Subfolder' : 'New Folder'),
            content: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: CupertinoTextField(
                controller: controller,
                placeholder: parentId != null
                    ? 'Subfolder name'
                    : 'Folder name',
                autofocus: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
            actions: [
              CupertinoDialogAction(
                isDestructiveAction: true,
                onPressed: creating ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: creating
                    ? null
                    : () async {
                        final name = controller.text.trim();
                        if (name.isEmpty) return;
                        setState(() => creating = true);
                        try {
                          await vault.createFolder(name, parentId: parentId);
                          if (ctx.mounted) Navigator.pop(ctx);
                        } finally {
                          if (ctx.mounted) setState(() => creating = false);
                        }
                      },
                child: creating
                    ? const CupertinoActivityIndicator(radius: 8)
                    : const Text('Create'),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Upload Progress Section ──
class _UploadProgressSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<VaultProvider>(
      builder: (context, vault, _) {
        final tasks = vault.uploadQueue;
        if (tasks.isEmpty) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          decoration: BoxDecoration(
            color: AppTheme.bgTertiary.withOpacity(0.6),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppTheme.separator.withOpacity(0.15),
              width: 0.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                child: Row(
                  children: [
                    const Icon(
                      CupertinoIcons.cloud_upload_fill,
                      size: 14,
                      color: AppTheme.accentBlue,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Uploads (${tasks.length})',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              ...tasks.map((task) => _UploadTaskTile(task: task)),
              const SizedBox(height: 4),
            ],
          ),
        );
      },
    );
  }
}

class _UploadTaskTile extends StatelessWidget {
  final UploadTask task;
  const _UploadTaskTile({required this.task});

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    IconData statusIcon;

    switch (task.status) {
      case 'encrypting':
        statusColor = AppTheme.systemOrange;
        statusIcon = CupertinoIcons.lock_fill;
        break;
      case 'uploading':
        statusColor = AppTheme.accentBlue;
        statusIcon = CupertinoIcons.cloud_upload;
        break;
      case 'saving':
        statusColor = AppTheme.accentBlue;
        statusIcon = CupertinoIcons.checkmark_circle;
        break;
      case 'done':
        statusColor = AppTheme.systemGreen;
        statusIcon = CupertinoIcons.checkmark_circle_fill;
        break;
      case 'error':
        statusColor = AppTheme.dangerRed;
        statusIcon = CupertinoIcons.xmark_circle_fill;
        break;
      default:
        statusColor = AppTheme.textTertiary;
        statusIcon = CupertinoIcons.time;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Icon(statusIcon, size: 14, color: statusColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.fileName,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                // Progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: SizedBox(
                    height: 3,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return Stack(
                          children: [
                            Container(
                              width: constraints.maxWidth,
                              height: 3,
                              color: AppTheme.fillQuaternary,
                            ),
                            Container(
                              width: constraints.maxWidth * task.progress,
                              height: 3,
                              color: statusColor,
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (task.status == 'error')
            GestureDetector(
              onTap: () =>
                  context.read<VaultProvider>().dismissUploadTask(task.id),
              child: const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(
                  CupertinoIcons.xmark,
                  size: 12,
                  color: AppTheme.textTertiary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String folderId;
  final bool isActive;
  final int count;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.folderId,
    required this.isActive,
    this.count = 0,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.read<VaultProvider>().setCurrentFolder(folderId),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.accentBlueDim : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: isActive ? AppTheme.accentBlue : AppTheme.textSecondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  color: isActive ? AppTheme.accentBlue : AppTheme.textPrimary,
                  letterSpacing: -0.2,
                ),
              ),
            ),
            if (count > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppTheme.accentBlue.withOpacity(0.2)
                      : AppTheme.fillQuaternary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isActive
                        ? AppTheme.accentBlue
                        : AppTheme.textTertiary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FolderTreeItem extends StatefulWidget {
  final VaultFolder folder;
  final int depth;

  const _FolderTreeItem({required this.folder, required this.depth});

  @override
  State<_FolderTreeItem> createState() => _FolderTreeItemState();
}

class _FolderTreeItemState extends State<_FolderTreeItem> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final vault = context.watch<VaultProvider>();
    final children = vault.childrenOf(widget.folder.id);
    final hasChildren = children.isNotEmpty;
    final isActive = vault.currentFolder == widget.folder.id;
    final count = vault.files
        .where((f) => f.folderId == widget.folder.id)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => vault.setCurrentFolder(widget.folder.id),
          onLongPress: () => _Sidebar._showCreateFolderDialog(
            context,
            vault,
            widget.folder.id,
          ),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
            padding: EdgeInsets.only(
              left: 12.0 + widget.depth * 16,
              right: 12,
              top: 9,
              bottom: 9,
            ),
            decoration: BoxDecoration(
              color: isActive ? AppTheme.accentBlueDim : null,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                if (hasChildren)
                  GestureDetector(
                    onTap: () => setState(() => _isExpanded = !_isExpanded),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(
                        _isExpanded
                            ? CupertinoIcons.chevron_down
                            : CupertinoIcons.chevron_right,
                        size: 12,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                  )
                else
                  const SizedBox(width: 16),
                Icon(
                  isActive ? CupertinoIcons.folder_fill : CupertinoIcons.folder,
                  size: 18,
                  color: isActive
                      ? AppTheme.accentBlue
                      : AppTheme.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.folder.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                      color: isActive
                          ? AppTheme.accentBlue
                          : AppTheme.textPrimary,
                      letterSpacing: -0.2,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (count > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: isActive
                          ? AppTheme.accentBlue.withOpacity(0.2)
                          : AppTheme.fillQuaternary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isActive
                            ? AppTheme.accentBlue
                            : AppTheme.textTertiary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (hasChildren && _isExpanded)
          ...children.map(
            (c) => _FolderTreeItem(folder: c, depth: widget.depth + 1),
          ),
      ],
    );
  }
}
