import { useState } from 'react';
import { X, FolderPlus } from 'lucide-react';
import styles from './UploadModal.module.css'; // Reuse same styles for consistency
import { encryptMetadata, generateUUID } from '../utils/crypto';

export default function FolderModal({ isOpen, onClose, vaultContext, onFolderCreateSuccess }) {
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
          <h3 className={styles.title}>New Folder</h3>
          <button className={styles.closeBtn} onClick={onClose} disabled={isCreating}>
            <X size={20} />
          </button>
        </div>

        <form onSubmit={handleSubmit} className={styles.content}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
              <FolderPlus size={24} style={{ color: 'var(--accent-blue)' }} />
              <input
                type="text"
                value={folderName}
                onChange={(e) => setFolderName(e.target.value)}
                placeholder="Folder Name"
                disabled={isCreating}
                autoFocus
                style={{
                  flex: 1,
                  background: 'var(--bg-primary)',
                  border: '1px solid var(--border-color)',
                  color: 'var(--text-primary)',
                  padding: '10px 14px',
                  borderRadius: 'var(--border-radius-sm)',
                  fontSize: '15px'
                }}
              />
            </div>
            <button
              type="submit"
              disabled={isCreating || !folderName.trim()}
              style={{
                width: '100%',
                backgroundColor: 'var(--accent-blue)',
                color: '#fff',
                padding: '10px',
                borderRadius: 'var(--border-radius-sm)',
                fontSize: '15px',
                fontWeight: 500,
                opacity: (isCreating || !folderName.trim()) ? 0.5 : 1
              }}
            >
              {isCreating ? 'Creating...' : 'Create Folder'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}