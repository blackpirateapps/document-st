import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../services/vault_provider.dart';
import '../theme/app_theme.dart';
import '../models/vault_folder.dart';
import 'file_list_screen.dart';
import 'file_detail_screen.dart';

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
    return CupertinoPageScaffold(
      backgroundColor: AppTheme.bgPrimary,
      child: SafeArea(
        child: Row(
          children: [
            // Sidebar (on wider screens) or drawer pattern
            if (MediaQuery.of(context).size.width >= 600) const _Sidebar(),
            // Main content
            const Expanded(child: FileListScreen()),
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
          width: 260,
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
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 20, 20, 16),
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

              // Default folders
              _SidebarItem(
                icon: CupertinoIcons.tray,
                label: 'Inbox',
                folderId: 'inbox',
                isActive: vault.currentFolder == 'inbox',
              ),
              _SidebarItem(
                icon: CupertinoIcons.star,
                label: 'Starred',
                folderId: 'starred',
                isActive: vault.currentFolder == 'starred',
              ),
              _SidebarItem(
                icon: CupertinoIcons.doc,
                label: 'Documents',
                folderId: 'documents',
                isActive: vault.currentFolder == 'documents',
              ),
              _SidebarItem(
                icon: CupertinoIcons.photo,
                label: 'Photos',
                folderId: 'photos',
                isActive: vault.currentFolder == 'photos',
              ),
              _SidebarItem(
                icon: CupertinoIcons.folder,
                label: 'Taxes',
                folderId: 'taxes',
                isActive: vault.currentFolder == 'taxes',
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
                      child: const Icon(
                        CupertinoIcons.plus,
                        size: 16,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),

              // Custom folders tree
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: vault.rootFolders
                      .map((f) => _FolderTreeItem(folder: f, depth: 0))
                      .toList(),
                ),
              ),

              // Trash
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: _SidebarItem(
                  icon: CupertinoIcons.trash,
                  label: 'Trash',
                  folderId: 'trash',
                  isActive: false,
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
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(parentId != null ? 'New Subfolder' : 'New Folder'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: controller,
            placeholder: parentId != null ? 'Subfolder name' : 'Folder name',
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
            child: const Text('Create'),
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              try {
                await vault.createFolder(name, parentId: parentId);
              } catch (_) {}
              if (ctx.mounted) Navigator.pop(ctx);
            },
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

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.folderId,
    required this.isActive,
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
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive ? AppTheme.accentBlue : AppTheme.textPrimary,
                letterSpacing: -0.2,
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
                  CupertinoIcons.folder,
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
