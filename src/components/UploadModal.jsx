import { useState, useRef } from 'react';
import { X, UploadCloud } from 'lucide-react';
import styles from './UploadModal.module.css';
import { encryptFile, encryptMetadata, generateUUID } from '../utils/crypto';

export default function UploadModal({ isOpen, onClose, vaultContext, currentFolder, onUploadSuccess, onUploadFiles }) {
  const [isUploading, setIsUploading] = useState(false);
  const fileInputRef = useRef(null);

  if (!isOpen) return null;

  const handleFileChange = async (e) => {
    const selectedFiles = Array.from(e.target.files || []);
    if (!selectedFiles.length) return;

    setIsUploading(true);
    try {
      if (onUploadFiles) {
        await onUploadFiles(selectedFiles, currentFolder);
      } else {
        const file = selectedFiles[0];
        const { encryptedBlob, iv, originalName, originalType, size } = await encryptFile(file, vaultContext.aesKey);
        const formData = new FormData();
        formData.append('file', encryptedBlob, 'encrypted_blob');

        const uploadRes = await fetch('/api/upload', {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${vaultContext.authPassword}`
          },
          body: formData
        });

        if (!uploadRes.ok) throw new Error('Failed to upload file to storage');
        const { url: cloudinary_url } = await uploadRes.json();

        const blobId = generateUUID();
        const metadataToEncrypt = {
          originalName,
          originalType,
          size,
          folderId: currentFolder,
          fileIv: Array.from(iv),
          starred: false,
          description: '',
          properties: [],
          dateAdded: new Date().toISOString()
        };

        const encryptedMeta = await encryptMetadata(metadataToEncrypt, vaultContext.aesKey);
        const dbRes = await fetch('/api/files', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${vaultContext.authPassword}`
          },
          body: JSON.stringify({
            id: blobId,
            encrypted_metadata: encryptedMeta.data,
            metadata_iv: JSON.stringify(encryptedMeta.iv),
            cloudinary_url
          })
        });

        if (!dbRes.ok) throw new Error('Failed to save metadata to database');

        onUploadSuccess({
          id: blobId,
          cloudinary_url,
          originalName,
          originalType,
          size,
          folderId: currentFolder,
          fileIv: Array.from(iv),
          starred: false,
          description: '',
          properties: [],
          dateAdded: metadataToEncrypt.dateAdded
        });
      }

      onClose();
    } catch (err) {
      console.error('Upload failed:', err);
      alert('Encryption or upload failed: ' + err.message);
    } finally {
      setIsUploading(false);
      if (fileInputRef.current) fileInputRef.current.value = null;
    }
  };

  return (
    <div className={styles.overlay}>
      <div className={styles.modal}>
        <div className={styles.header}>
          <h3 className={styles.title}>Upload File</h3>
          <button className={styles.closeBtn} onClick={onClose} disabled={isUploading}>
            <X size={20} />
          </button>
        </div>

        <div className={styles.content}>
          <input
            type="file"
            ref={fileInputRef}
            onChange={handleFileChange}
            className={styles.hiddenInput}
            id="file-upload"
            disabled={isUploading}
            multiple
          />
          <label htmlFor="file-upload" className={styles.uploadArea}>
            <div className={styles.uploadIconContainer}>
              <UploadCloud size={32} className={styles.uploadIcon} />
            </div>
            <p className={styles.uploadText}>
              {isUploading ? 'Encrypting and Uploading...' : 'Click to select a file'}
            </p>
            <p className={styles.uploadSubtext}>
              Files are encrypted locally before uploading.
            </p>
          </label>
        </div>
      </div>
    </div>
  );
}
