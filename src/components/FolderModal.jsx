import { useState } from 'react';
import { X, FolderPlus } from 'lucide-react';
import styles from './UploadModal.module.css';
import { encryptMetadata, generateUUID } from '../utils/crypto';

export default function FolderModal({ isOpen, onClose, vaultContext, onFolderCreateSuccess, parentId = null }) {
  const [folderName, setFolderName] = useState('');
  const [isCreating, setIsCreating] = useState(false);

  if (!isOpen) return null;

  const handleSubmit = async (e) => {
    e.preventDefault();
    if (!folderName.trim()) return;

    setIsCreating(true);

    try {
      const folderId = generateUUID();
      
      const metadataToEncrypt = {
        name: folderName.trim(),
        parentId: parentId || null,
        dateAdded: new Date().toISOString()
      };
      
      const encryptedMeta = await encryptMetadata(metadataToEncrypt, vaultContext.aesKey);

      const dbRes = await fetch('/api/folders', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${vaultContext.authPassword}`
        },
        body: JSON.stringify({
          id: folderId,
          encrypted_metadata: encryptedMeta.data,
          metadata_iv: JSON.stringify(encryptedMeta.iv)
        })
      });

      if (!dbRes.ok) throw new Error('Failed to save folder to database');

      onFolderCreateSuccess({
        id: folderId,
        name: metadataToEncrypt.name,
        parentId: metadataToEncrypt.parentId,
        dateAdded: metadataToEncrypt.dateAdded
      });
      
      setFolderName('');
      onClose();
    } catch (err) {
      console.error('Folder creation failed:', err);
      alert('Failed to create folder: ' + err.message);
    } finally {
      setIsCreating(false);
    }
  };

  return (
    <div className={styles.overlay}>
      <div className={styles.modal} style={{ maxWidth: '400px' }}>
        <div className={styles.header}>
          <h3 className={styles.title}>{parentId ? 'New Subfolder' : 'New Folder'}</h3>
          <button className={styles.closeBtn} onClick={onClose} disabled={isCreating}>
            <X size={20} />
          </button>
        </div>

        <form onSubmit={handleSubmit} className={styles.content}>
          <div className={styles.formGroup}>
            <div className={styles.folderInputRow}>
              <FolderPlus size={24} className={styles.folderInputIcon} />
              <input
                type="text"
                value={folderName}
                onChange={(e) => setFolderName(e.target.value)}
                placeholder={parentId ? 'Subfolder Name' : 'Folder Name'}
                disabled={isCreating}
                autoFocus
                className={styles.formInput}
              />
            </div>
            <button
              type="submit"
              disabled={isCreating || !folderName.trim()}
              className={styles.submitBtn}
            >
              {isCreating ? 'Creating...' : parentId ? 'Create Subfolder' : 'Create Folder'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
