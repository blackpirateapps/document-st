import { useState, useEffect } from 'react';
import { X } from 'lucide-react';
import styles from './UploadModal.module.css';
import { encryptMetadata } from '../utils/crypto';

export default function ActionModal({ 
  isOpen, 
  onClose, 
  actionType, // 'rename' or 'move'
  fileRec, 
  vaultContext, 
  customFolders,
  onSuccess 
}) {
  const [inputValue, setInputValue] = useState('');
  const [isProcessing, setIsProcessing] = useState(false);

  useEffect(() => {
    if (isOpen && fileRec) {
      if (actionType === 'rename') {
        setInputValue(fileRec.originalName);
      } else if (actionType === 'move') {
        setInputValue(fileRec.folderId);
      }
    }
  }, [isOpen, fileRec, actionType]);

  if (!isOpen || !fileRec) return null;

  const handleSubmit = async (e) => {
    e.preventDefault();
    if (!inputValue.trim()) return;

    setIsProcessing(true);

    try {
      // 1. Prepare new metadata
      const newMetadata = {
        originalName: actionType === 'rename' ? inputValue.trim() : fileRec.originalName,
        originalType: fileRec.originalType,
        size: fileRec.size,
        folderId: actionType === 'move' ? inputValue : fileRec.folderId,
        fileIv: fileRec.fileIv,
        starred: fileRec.starred || false,
        description: fileRec.description || '',
        properties: fileRec.properties || [],
        dateAdded: fileRec.dateAdded
      };

      // 2. Encrypt new metadata
      const encryptedMeta = await encryptMetadata(newMetadata, vaultContext.aesKey);

      // 3. Update DB
      const dbRes = await fetch('/api/files', {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${vaultContext.authPassword}`
        },
        body: JSON.stringify({
          id: fileRec.id,
          encrypted_metadata: encryptedMeta.data,
          metadata_iv: JSON.stringify(encryptedMeta.iv)
        })
      });

      if (!dbRes.ok) throw new Error('Failed to update file metadata');

      // 4. Update local state via callback
      onSuccess({
        ...fileRec,
        ...newMetadata
      });

      onClose();
    } catch (err) {
      console.error('Action failed:', err);
      alert('Failed to process request: ' + err.message);
    } finally {
      setIsProcessing(false);
    }
  };

  const defaultFolders = [
    { id: 'inbox', label: 'Inbox' },
    { id: 'starred', label: 'Starred' },
    { id: 'documents', label: 'Documents' },
    { id: 'photos', label: 'Photos' },
    { id: 'taxes', label: 'Taxes' },
  ];

  const allFolders = [...defaultFolders, ...customFolders.map(f => ({ id: f.id, label: f.name }))];

  return (
    <div className={styles.overlay} style={{ zIndex: 110 }}>
      <div className={styles.modal} style={{ maxWidth: '400px' }}>
        <div className={styles.header}>
          <h3 className={styles.title}>
            {actionType === 'rename' ? 'Rename File' : 'Move File'}
          </h3>
          <button className={styles.closeBtn} onClick={onClose} disabled={isProcessing}>
            <X size={20} />
          </button>
        </div>

        <form onSubmit={handleSubmit} className={styles.content}>
          <div className={styles.formGroup}>
            
            {actionType === 'rename' ? (
              <input
                type="text"
                value={inputValue}
                onChange={(e) => setInputValue(e.target.value)}
                placeholder="File Name"
                disabled={isProcessing}
                autoFocus
                className={styles.formInput}
              />
            ) : (
              <select
                value={inputValue}
                onChange={(e) => setInputValue(e.target.value)}
                disabled={isProcessing}
                className={styles.formSelect}
              >
                {allFolders.map(f => (
                  <option key={f.id} value={f.id}>{f.label}</option>
                ))}
              </select>
            )}

            <button
              type="submit"
              disabled={isProcessing || !inputValue.trim() || inputValue === (actionType === 'rename' ? fileRec.originalName : fileRec.folderId)}
              className={styles.submitBtn}
            >
              {isProcessing ? 'Saving...' : 'Save'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
