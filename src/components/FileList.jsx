import { FileIcon, Download, Clock } from 'lucide-react';
import styles from './FileList.module.css';
import { decryptFile } from '../utils/crypto';
import { useState } from 'react';

export default function FileList({ files, aesKey, currentFolder }) {
  const [downloadingId, setDownloadingId] = useState(null);

  const handleDownload = async (fileRec) => {
    try {
      setDownloadingId(fileRec.id);
      
      // 1. Fetch encrypted blob from Cloudinary
      const response = await fetch(fileRec.cloudinary_url);
      if (!response.ok) throw new Error('Failed to fetch blob from storage');
      const encryptedBlob = await response.blob();
      
      // 2. Decrypt the blob using the key in memory and the file's IV
      const decryptedBlob = await decryptFile(
        encryptedBlob, 
        aesKey, 
        fileRec.fileIv, 
        fileRec.originalType
      );
      
      // 3. Trigger local browser download
      const url = URL.createObjectURL(decryptedBlob);
      const a = document.createElement('a');
      a.href = url;
      a.download = fileRec.originalName;
      document.body.appendChild(a);
      a.click();
      
      // Cleanup
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
    } catch (err) {
      console.error("Failed to decrypt and download file", err);
      alert("Failed to download or decrypt file. Ensure network connection.");
    } finally {
      setDownloadingId(null);
    }
  };

  const folderFiles = files.filter(f => f.folderId === currentFolder);

  return (
    <div className={styles.container}>
      <header className={styles.header}>
        <h1 className={styles.title}>
          {currentFolder.charAt(0).toUpperCase() + currentFolder.slice(1)}
        </h1>
      </header>

      {folderFiles.length === 0 ? (
        <div className={styles.emptyState}>
          <div className={styles.emptyIcon}>
            <FolderEmptyIcon />
          </div>
          <p className={styles.emptyText}>No files in this folder.</p>
        </div>
      ) : (
        <div className={styles.tableContainer}>
          <table className={styles.table}>
            <thead>
              <tr>
                <th>Name</th>
                <th>Size</th>
                <th>Date Added</th>
                <th className={styles.actions}></th>
              </tr>
            </thead>
            <tbody>
              {folderFiles.map(file => (
                <tr key={file.id} className={styles.row}>
                  <td>
                    <div className={styles.fileName}>
                      <FileIcon size={18} className={styles.icon} />
                      <span>{file.originalName}</span>
                    </div>
                  </td>
                  <td className={styles.metaData}>
                    {(file.size / 1024).toFixed(1)} KB
                  </td>
                  <td className={styles.metaData}>
                    <div className={styles.date}>
                      <Clock size={14} className={styles.clockIcon} />
                      {new Date(file.dateAdded).toLocaleDateString()}
                    </div>
                  </td>
                  <td className={styles.actions}>
                    <button 
                      className={styles.downloadBtn} 
                      onClick={() => handleDownload(file)}
                      disabled={downloadingId === file.id}
                      title="Decrypt and Download"
                    >
                      {downloadingId === file.id ? (
                        <span className={styles.spinner}>...</span>
                      ) : (
                        <Download size={18} />
                      )}
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

const FolderEmptyIcon = () => (
  <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1" strokeLinecap="round" strokeLinejoin="round">
    <path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"></path>
  </svg>
);
