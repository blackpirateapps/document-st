import { useState, useEffect } from 'react';
import { X, Download } from 'lucide-react';
import styles from './UploadModal.module.css'; // Reuse overlay and some modal styles
import { decryptFile } from '../utils/crypto';

export default function PdfPreviewModal({ isOpen, onClose, fileRec, aesKey }) {
  const [objectUrl, setObjectUrl] = useState(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    if (!isOpen || !fileRec) return;

    let url = null;
    let isMounted = true;

    const fetchAndDecrypt = async () => {
      setIsLoading(true);
      setError('');
      try {
        const response = await fetch(fileRec.cloudinary_url);
        if (!response.ok) throw new Error('Failed to fetch blob from storage');
        const encryptedBlob = await response.blob();
        
        const decryptedBlob = await decryptFile(
          encryptedBlob, 
          aesKey, 
          fileRec.fileIv, 
          fileRec.originalType
        );
        
        if (isMounted) {
          url = URL.createObjectURL(decryptedBlob);
          setObjectUrl(url);
        }
      } catch (err) {
        if (isMounted) {
          console.error("PDF Preview Error:", err);
          setError("Failed to decrypt and load PDF.");
        }
      } finally {
        if (isMounted) setIsLoading(false);
      }
    };

    fetchAndDecrypt();

    return () => {
      isMounted = false;
      if (url) URL.revokeObjectURL(url);
    };
  }, [isOpen, fileRec, aesKey]);

  if (!isOpen || !fileRec) return null;

  return (
    <div className={styles.overlay} style={{ zIndex: 1000, padding: '24px' }}>
      <div 
        style={{ 
          backgroundColor: 'var(--bg-secondary)', 
          borderRadius: 'var(--border-radius-lg)',
          width: '100%',
          maxWidth: '1200px',
          height: '100%',
          display: 'flex',
          flexDirection: 'column',
          border: '1px solid var(--border-color)',
          boxShadow: 'var(--shadow-lg)'
        }}
      >
        <div className={styles.header} style={{ flexShrink: 0 }}>
          <h3 className={styles.title} style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
            <span>{fileRec.originalName}</span>
            {objectUrl && (
              <a 
                href={objectUrl} 
                download={fileRec.originalName}
                style={{ color: 'var(--text-secondary)', marginLeft: '16px' }}
                title="Download"
              >
                <Download size={18} />
              </a>
            )}
          </h3>
          <button className={styles.closeBtn} onClick={onClose}>
            <X size={20} />
          </button>
        </div>

        <div style={{ flex: 1, position: 'relative', overflow: 'hidden', backgroundColor: '#e5e5ea' }}>
          {isLoading && (
            <div style={{ position: 'absolute', top: '50%', left: '50%', transform: 'translate(-50%, -50%)', color: '#000' }}>
              Decrypting PDF...
            </div>
          )}
          {error && (
            <div style={{ position: 'absolute', top: '50%', left: '50%', transform: 'translate(-50%, -50%)', color: 'var(--danger-red)' }}>
              {error}
            </div>
          )}
          {objectUrl && !isLoading && (
            <iframe 
              src={`${objectUrl}#toolbar=0`} 
              style={{ width: '100%', height: '100%', border: 'none' }}
              title="PDF Preview"
            />
          )}
        </div>
      </div>
    </div>
  );
}