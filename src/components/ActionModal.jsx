import { useState, useEffect } from 'react';
import { X } from 'lucide-react';
import styles from './UploadModal.module.css'; // Reuse styles
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
          <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
            
            {actionType === 'rename' ? (
              <input
                type="text"
                value={inputValue}
                onChange={(e) => setInputValue(e.target.value)}
                placeholder="File Name"
                disabled={isProcessing}
                autoFocus
                style={{
                  width: '100%',
                  background: 'var(--bg-primary)',
                  border: '1px solid var(--border-color)',
                  color: 'var(--text-primary)',
                  padding: '10px 14px',
                  borderRadius: 'var(--border-radius-sm)',
                  fontSize: '15px'
                }}
              />
            ) : (
              <select
                value={inputValue}
                onChange={(e) => setInputValue(e.target.value)}
                disabled={isProcessing}
                style={{
                  width: '100%',
                  background: 'var(--bg-primary)',
                  border: '1px solid var(--border-color)',
                  color: 'var(--text-primary)',
                  padding: '10px 14px',
                  borderRadius: 'var(--border-radius-sm)',
                  fontSize: '15px',
                  outline: 'none'
                }}
              >
                {allFolders.map(f => (
                  <option key={f.id} value={f.id}>{f.label}</option>
                ))}
              </select>
            )}

            <button
              type="submit"
              disabled={isProcessing || !inputValue.trim() || inputValue === (actionType === 'rename' ? fileRec.originalName : fileRec.folderId)}
              style={{
                width: '100%',
                backgroundColor: 'var(--accent-blue)',
                color: '#fff',
                padding: '10px',
                borderRadius: 'var(--border-radius-sm)',
                fontSize: '15px',
                fontWeight: 500,
                opacity: (isProcessing || !inputValue.trim()) ? 0.5 : 1
              }}
            >
              {isProcessing ? 'Saving...' : 'Save'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}