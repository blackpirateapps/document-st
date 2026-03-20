import { Folder, ChevronRight, Inbox, Star, Settings, Trash2, Plus, X, Files } from 'lucide-react';
import styles from './Sidebar.module.css';
import clsx from 'clsx';
import { useState } from 'react';
import FolderModal from './FolderModal';

function formatBytes(bytes) {
  if (!Number.isFinite(bytes) || bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  const idx = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1);
  const value = bytes / 1024 ** idx;
  return `${value.toFixed(idx === 0 ? 0 : value >= 100 ? 0 : value >= 10 ? 1 : 2)} ${units[idx]}`;
}

function FolderTreeItem({ folder, currentFolder, onSelectFolder, customFolders, depth = 0, onCreateSubfolder }) {
  const [isExpanded, setIsExpanded] = useState(false);
  const children = customFolders.filter(f => f.parentId === folder.id);
  const hasChildren = children.length > 0;

  return (
    <li className={styles.listItem}>
      <div className={styles.treeRow}>
        <button
          className={clsx(styles.button, currentFolder === folder.id && styles.active)}
          onClick={() => onSelectFolder(folder.id)}
          style={{ paddingLeft: `${10 + depth * 16}px` }}
        >
          {hasChildren ? (
            <span
              className={clsx(styles.chevron, isExpanded && styles.chevronExpanded)}
              onClick={(e) => { e.stopPropagation(); setIsExpanded(!isExpanded); }}
            >
              <ChevronRight size={12} />
            </span>
          ) : (
            <span className={styles.chevronSpacer} />
          )}
          <Folder size={16} className={styles.icon} />
          <span className={styles.folderNameText}>{folder.name}</span>
        </button>
        <button
          className={styles.subfolderBtn}
          onClick={(e) => { e.stopPropagation(); onCreateSubfolder(folder.id); }}
          title="New Subfolder"
        >
          <Plus size={11} />
        </button>
      </div>
      {hasChildren && isExpanded && (
        <ul className={styles.list}>
          {children.map(child => (
            <FolderTreeItem
              key={child.id}
              folder={child}
              currentFolder={currentFolder}
              onSelectFolder={onSelectFolder}
              customFolders={customFolders}
              depth={depth + 1}
              onCreateSubfolder={onCreateSubfolder}
            />
          ))}
        </ul>
      )}
    </li>
  );
}

export default function Sidebar({
  currentFolder,
  onSelectFolder,
  onOpenSettings,
  customFolders = [],
  vaultContext,
  onFolderCreateSuccess,
  vaultStats,
  cloudinaryUsage,
  onRefreshUsage,
  isMobileOpen = false,
  onCloseMobile,
}) {
  const [folderModalState, setFolderModalState] = useState({ isOpen: false, parentId: null });

  const defaultFolders = [
    { id: 'all', label: 'All Files', icon: Files },
    { id: 'inbox', label: 'Inbox', icon: Inbox },
    { id: 'starred', label: 'Starred', icon: Star },
    { id: 'documents', label: 'Documents', icon: Folder },
    { id: 'photos', label: 'Photos', icon: Folder },
    { id: 'taxes', label: 'Taxes', icon: Folder },
  ];

  // Root-level custom folders (no parent)
  const rootFolders = customFolders.filter(f => !f.parentId);

  const handleCreateSubfolder = (parentId) => {
    setFolderModalState({ isOpen: true, parentId });
  };

  return (
    <aside className={`${styles.sidebar} ${isMobileOpen ? styles.mobileOpen : ''}`}>
      <div className={styles.header}>
        <h2 className={styles.title}>Vault</h2>
        <button className={styles.mobileCloseBtn} onClick={onCloseMobile} aria-label="Close folders">
          <X size={18} />
        </button>
      </div>

      <nav className={styles.nav}>
        <div className={styles.section}>
          <ul className={styles.list}>
            {defaultFolders.map(folder => (
              <li key={folder.id} className={styles.listItem}>
                <button
                  className={clsx(styles.button, currentFolder === folder.id && styles.active)}
                  onClick={() => onSelectFolder(folder.id)}
                >
                  <span className={styles.chevronSpacer} />
                  <folder.icon size={16} className={styles.icon} />
                  <span>{folder.label}</span>
                </button>
              </li>
            ))}
          </ul>
        </div>

        <div className={styles.section}>
          <div className={styles.sectionHeader}>
            <h3 className={styles.sectionTitle}>Folders</h3>
            <button 
              className={styles.addFolderBtn} 
              onClick={() => setFolderModalState({ isOpen: true, parentId: null })}
              title="New Folder"
            >
              <Plus size={14} />
            </button>
          </div>
          <ul className={styles.list}>
            {rootFolders.map(folder => (
              <FolderTreeItem
                key={folder.id}
                folder={folder}
                currentFolder={currentFolder}
                onSelectFolder={onSelectFolder}
                customFolders={customFolders}
                depth={0}
                onCreateSubfolder={handleCreateSubfolder}
              />
            ))}
          </ul>
        </div>

        <div className={styles.section}>
          <ul className={styles.list}>
            <li className={styles.listItem}>
              <button
                className={clsx(styles.button, currentFolder === 'trash' && styles.active)}
                onClick={() => onSelectFolder('trash')}
              >
                <span className={styles.chevronSpacer} />
                <Trash2 size={16} className={styles.icon} />
                <span>Trash</span>
              </button>
            </li>
          </ul>
        </div>
      </nav>

      <div className={styles.footer}>
        <div className={styles.usageCard}>
          <div className={styles.usageHeader}>
            <span className={styles.usageTitle}>Vault Usage</span>
            <button
              className={styles.usageRefreshBtn}
              onClick={onRefreshUsage}
              disabled={cloudinaryUsage?.loading}
              title="Refresh cloud usage"
            >
              {cloudinaryUsage?.loading ? '...' : '↻'}
            </button>
          </div>
          <div className={styles.usageRow}>
            <span>Decryptable Files</span>
            <strong>{vaultStats?.decryptableFileCount ?? 0}</strong>
          </div>
          <div className={styles.usageRow}>
            <span>Vault Size</span>
            <strong>{formatBytes(vaultStats?.decryptableBytes ?? 0)}</strong>
          </div>
          <div className={styles.usageRow}>
            <span>Cloudinary Credits</span>
            <strong>
              {cloudinaryUsage?.error
                ? 'Unavailable'
                : cloudinaryUsage?.credits?.used != null && cloudinaryUsage?.credits?.limit != null
                  ? `${cloudinaryUsage.credits.used}/${cloudinaryUsage.credits.limit}`
                  : 'Unknown'}
            </strong>
          </div>
          <div className={styles.usageRow}>
            <span>Cloudinary Storage</span>
            <strong>
              {cloudinaryUsage?.error
                ? 'Unavailable'
                : cloudinaryUsage?.storage?.usedBytes != null && cloudinaryUsage?.storage?.limitBytes != null
                  ? `${formatBytes(cloudinaryUsage.storage.usedBytes)} / ${formatBytes(cloudinaryUsage.storage.limitBytes)}`
                  : 'Unknown'}
            </strong>
          </div>
        </div>

        <button
          className={clsx(styles.button, currentFolder === 'settings' && styles.active)}
          onClick={onOpenSettings}
        >
          <span className={styles.chevronSpacer} />
          <Settings size={16} className={styles.icon} />
          <span>Settings</span>
        </button>
      </div>

      <FolderModal 
        isOpen={folderModalState.isOpen} 
        onClose={() => setFolderModalState({ isOpen: false, parentId: null })}
        vaultContext={vaultContext}
        onFolderCreateSuccess={onFolderCreateSuccess}
        parentId={folderModalState.parentId}
      />
    </aside>
  );
}
