import { useState, useEffect } from 'react';
import { X, Download } from 'lucide-react';
import styles from './UploadModal.module.css';
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
    <div className={`${styles.overlay} ${styles.previewOverlay}`}>
      <div className={styles.previewModal}>
        <div className={`${styles.header} ${styles.previewHeader}`}>
          <h3 className={styles.title}>
            <span className={styles.previewTitleRow}>
              <span>{fileRec.originalName}</span>
              {objectUrl && (
                <a 
                  href={objectUrl} 
                  download={fileRec.originalName}
                  className={styles.previewDownloadLink}
                  title="Download"
                >
                  <Download size={18} />
                </a>
              )}
            </span>
          </h3>
          <button className={styles.closeBtn} onClick={onClose}>
            <X size={20} />
          </button>
        </div>

        <div className={styles.previewBody}>
          {isLoading && (
            <div className={styles.previewLoading}>
              Decrypting PDF...
            </div>
          )}
          {error && (
            <div className={styles.previewError}>
              {error}
            </div>
          )}
          {objectUrl && !isLoading && (
            <iframe 
              src={`${objectUrl}#toolbar=0`} 
              className={styles.previewIframe}
              title="PDF Preview"
            />
          )}
        </div>
      </div>
    </div>
  );
}
