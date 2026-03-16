import { Folder, Inbox, Star, Settings, Trash2, Plus } from 'lucide-react';
import styles from './Sidebar.module.css';
import clsx from 'clsx';
import { useState } from 'react';
import FolderModal from './FolderModal';

export default function Sidebar({ currentFolder, onSelectFolder, customFolders = [], vaultContext, onFolderCreateSuccess }) {
  const [isFolderModalOpen, setIsFolderModalOpen] = useState(false);

  const defaultFolders = [
    { id: 'inbox', label: 'Inbox', icon: Inbox },
    { id: 'starred', label: 'Starred', icon: Star },
    { id: 'documents', label: 'Documents', icon: Folder },
    { id: 'photos', label: 'Photos', icon: Folder },
    { id: 'taxes', label: 'Taxes', icon: Folder },
  ];

  return (
    <aside className={styles.sidebar}>
      <div className={styles.header}>
        <h2 className={styles.title}>Vault</h2>
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
                  <folder.icon size={18} className={styles.icon} />
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
              onClick={() => setIsFolderModalOpen(true)}
              title="New Folder"
            >
              <Plus size={14} />
            </button>
          </div>
          <ul className={styles.list}>
            {customFolders.map(folder => (
              <li key={folder.id} className={styles.listItem}>
                <button
                  className={clsx(styles.button, currentFolder === folder.id && styles.active)}
                  onClick={() => onSelectFolder(folder.id)}
                >
                  <Folder size={18} className={styles.icon} />
                  <span className={styles.folderNameText}>{folder.name}</span>
                </button>
              </li>
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
                <Trash2 size={18} className={styles.icon} />
                <span>Trash</span>
              </button>
            </li>
          </ul>
        </div>
      </nav>

      <div className={styles.footer}>
        <button className={styles.button}>
          <Settings size={18} className={styles.icon} />
          <span>Settings</span>
        </button>
      </div>

      <FolderModal 
        isOpen={isFolderModalOpen} 
        onClose={() => setIsFolderModalOpen(false)}
        vaultContext={vaultContext}
        onFolderCreateSuccess={onFolderCreateSuccess}
      />
    </aside>
  );
}
