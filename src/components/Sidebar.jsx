import { Folder, Inbox, Star, Settings } from 'lucide-react';
import styles from './Sidebar.module.css';
import clsx from 'clsx';

export default function Sidebar({ currentFolder, onSelectFolder }) {
  const folders = [
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
            {folders.map(folder => (
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
      </nav>

      <div className={styles.footer}>
        <button className={styles.button}>
          <Settings size={18} className={styles.icon} />
          <span>Settings</span>
        </button>
      </div>
    </aside>
  );
}
