import { useState, useRef } from 'react';
import { X, UploadCloud } from 'lucide-react';
import styles from './UploadModal.module.css';
import { encryptFile, encryptMetadata, generateUUID } from '../utils/crypto';

export default function UploadModal({ isOpen, onClose, vaultContext, currentFolder, onUploadSuccess }) {
  const [isUploading, setIsUploading] = useState(false);
  const fileInputRef = useRef(null);

  if (!isOpen) return null;

  const handleFileChange = async (e) => {
    const file = e.target.files[0];
    if (!file) return;

    setIsUploading(true);

    try {
      // 1. Encrypt File Blob Locally
      const { encryptedBlob, iv, originalName, originalType, size } = await encryptFile(file, vaultContext.aesKey);

      // 2. Upload Encrypted Blob to Vercel/Cloudinary
      const formData = new FormData();
      formData.append('file', encryptedBlob, 'encrypted_blob'); // Original name is hidden

      const uploadRes = await fetch('/api/upload', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${vaultContext.authPassword}`
        },
        body: formData
      });

      if (!uploadRes.ok) throw new Error('Failed to upload file to storage');
      const { url: cloudinary_url } = await uploadRes.json();

      // 3. Generate UUID for DB Record
      const blobId = generateUUID();

      // 4. Encrypt Metadata (including the IV needed to decrypt the blob)
      const metadataToEncrypt = {
        originalName,
        originalType,
        size,
        folderId: currentFolder,
        fileIv: Array.from(iv), // Store the file's IV in encrypted metadata
        dateAdded: new Date().toISOString()
      };
      
      const encryptedMeta = await encryptMetadata(metadataToEncrypt, vaultContext.aesKey);

      // 5. Save to Turso DB
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

      // 6. Update local state
      const newFileRecord = {
        id: blobId,
        cloudinary_url,
        originalName,
        originalType,
        size,
        folderId: currentFolder,
        fileIv: Array.from(iv),
        dateAdded: metadataToEncrypt.dateAdded
      };

      onUploadSuccess(newFileRecord);
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
