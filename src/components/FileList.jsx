import { FileIcon, Download, Clock, MoreVertical, Edit2, Copy, FolderInput, Trash2, Eye, Star } from 'lucide-react';
import styles from './FileList.module.css';
import { decryptFile, encryptMetadata, generateUUID } from '../utils/crypto';
import { useState, useRef, useEffect } from 'react';
import ActionModal from './ActionModal';
import PdfPreviewModal from './PdfPreviewModal';

export default function FileList({ files, aesKey, currentFolder, vaultContext, customFolders, onFileUpdate, onFileCopy, onSelectFile }) {
  const [downloadingId, setDownloadingId] = useState(null);
  const [menuOpenId, setMenuOpenId] = useState(null);
  
  // Modal states
  const [actionModalConfig, setActionModalConfig] = useState({ isOpen: false, type: null, file: null });
  const [previewModalConfig, setPreviewModalConfig] = useState({ isOpen: false, file: null });

  const menuRef = useRef(null);

  // Close menu when clicking outside
  useEffect(() => {
    function handleClickOutside(event) {
      if (menuRef.current && !menuRef.current.contains(event.target)) {
        setMenuOpenId(null);
      }
    }
    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, []);

  const handleDownload = async (fileRec) => {
    try {
      setDownloadingId(fileRec.id);
      
      const response = await fetch(fileRec.cloudinary_url);
      if (!response.ok) throw new Error('Failed to fetch blob from storage');
      const encryptedBlob = await response.blob();
      
      const decryptedBlob = await decryptFile(
        encryptedBlob, 
        aesKey, 
        fileRec.fileIv, 
        fileRec.originalType
      );
      
      const url = URL.createObjectURL(decryptedBlob);
      const a = document.createElement('a');
      a.href = url;
      a.download = fileRec.originalName;
      document.body.appendChild(a);
      a.click();
      
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
    } catch (err) {
      console.error("Failed to decrypt and download file", err);
      alert("Failed to download or decrypt file. Ensure network connection.");
    } finally {
      setDownloadingId(null);
    }
  };

  const handleToggleStar = async (file) => {
    try {
      const newMetadata = { ...file, starred: !file.starred };
      // Remove non-metadata fields before encrypting
      const metaToEncrypt = {
        originalName: newMetadata.originalName,
        originalType: newMetadata.originalType,
        size: newMetadata.size,
        folderId: newMetadata.folderId,
        fileIv: newMetadata.fileIv,
        starred: newMetadata.starred,
        description: newMetadata.description || '',
        properties: newMetadata.properties || [],
        dateAdded: newMetadata.dateAdded
      };
      const encryptedMeta = await encryptMetadata(metaToEncrypt, vaultContext.aesKey);
      const dbRes = await fetch('/api/files', {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${vaultContext.authPassword}`
        },
        body: JSON.stringify({
          id: file.id,
          encrypted_metadata: encryptedMeta.data,
          metadata_iv: JSON.stringify(encryptedMeta.iv)
        })
      });
      if (!dbRes.ok) throw new Error('Failed to update star status');
      onFileUpdate({ ...file, starred: !file.starred });
    } catch (_e) {
      alert("Failed to update star status.");
    }
  };

  const handleRowClick = (file) => {
    // PDF files open the preview modal directly
    if (file.originalType === 'application/pdf') {
      setPreviewModalConfig({ isOpen: true, file });
    } else {
      // All other files open the detail view
      onSelectFile(file);
    }
  };

  const handleAction = async (action, file) => {
    setMenuOpenId(null);

    if (action === 'preview') {
      setPreviewModalConfig({ isOpen: true, file });
    } else if (action === 'details') {
      onSelectFile(file);
    } else if (action === 'rename' || action === 'move') {
      setActionModalConfig({ isOpen: true, type: action, file });
    } else if (action === 'trash') {
      if (!window.confirm(`Move "${file.originalName}" to trash?`)) return;
      try {
        const newMetadata = {
          originalName: file.originalName,
          originalType: file.originalType,
          size: file.size,
          folderId: 'trash',
          fileIv: file.fileIv,
          starred: file.starred || false,
          description: file.description || '',
          properties: file.properties || [],
          dateAdded: file.dateAdded
        };
        const encryptedMeta = await encryptMetadata(newMetadata, vaultContext.aesKey);
        const dbRes = await fetch('/api/files', {
          method: 'PUT',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${vaultContext.authPassword}`
          },
          body: JSON.stringify({
            id: file.id,
            encrypted_metadata: encryptedMeta.data,
            metadata_iv: JSON.stringify(encryptedMeta.iv)
          })
        });
        if (!dbRes.ok) throw new Error('Failed to update file metadata');
        onFileUpdate({ ...file, folderId: 'trash' });
      } catch (_e) {
        alert("Failed to trash file.");
      }
    } else if (action === 'copy') {
      try {
        const newId = generateUUID();
        const newMetadata = {
          originalName: file.originalName.replace(/(\.[\w\d_-]+)$/i, ' Copy$1'),
          originalType: file.originalType,
          size: file.size,
          folderId: file.folderId,
          fileIv: file.fileIv,
          starred: false,
          description: file.description || '',
          properties: file.properties || [],
          dateAdded: new Date().toISOString()
        };
        const encryptedMeta = await encryptMetadata(newMetadata, vaultContext.aesKey);
        
        const dbRes = await fetch('/api/files', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${vaultContext.authPassword}`
          },
          body: JSON.stringify({
            id: newId,
            encrypted_metadata: encryptedMeta.data,
            metadata_iv: JSON.stringify(encryptedMeta.iv),
            cloudinary_url: file.cloudinary_url
          })
        });
        if (!dbRes.ok) throw new Error('Failed to save copied file metadata');
        onFileCopy({
          id: newId,
          cloudinary_url: file.cloudinary_url,
          ...newMetadata
        });
      } catch (_e) {
        alert("Failed to copy file.");
      }
    }
  };

  // Filter files: "starred" folder shows all starred files, otherwise filter by folderId
  const folderFiles = currentFolder === 'all'
    ? files.filter(f => f.folderId !== 'trash')
    : currentFolder === 'starred'
      ? files.filter(f => f.starred && f.folderId !== 'trash')
      : files.filter(f => f.folderId === currentFolder);
  
  // Find custom folder name if it's a custom folder
  let folderTitle = currentFolder === 'all'
    ? 'All Files'
    : currentFolder.charAt(0).toUpperCase() + currentFolder.slice(1);
  const customFolder = customFolders?.find(f => f.id === currentFolder);
  if (customFolder) folderTitle = customFolder.name;

  return (
    <div className={styles.container}>
      <header className={styles.header}>
        <h1 className={styles.title}>{folderTitle}</h1>
      </header>

      {folderFiles.length === 0 ? (
        <div className={styles.emptyState}>
          <div className={styles.emptyIcon}>
            <FolderEmptyIcon />
          </div>
          <p className={styles.emptyText}>
            {currentFolder === 'starred'
              ? 'No starred files.'
              : currentFolder === 'all'
                ? 'No decrypted files available.'
                : 'No files in this folder.'}
          </p>
        </div>
      ) : (
        <div className={styles.tableContainer}>
          <table className={styles.table}>
            <thead>
              <tr>
                <th className={styles.starCol}></th>
                <th>Name</th>
                <th>Size</th>
                <th>Date Added</th>
                <th className={styles.actions}></th>
              </tr>
            </thead>
            <tbody>
              {folderFiles.map(file => (
                <tr key={file.id} className={styles.row} onClick={() => handleRowClick(file)}>
                  <td className={styles.starCol} onClick={(e) => e.stopPropagation()}>
                    <button
                      className={`${styles.starBtn} ${file.starred ? styles.starActive : ''}`}
                      onClick={() => handleToggleStar(file)}
                      title={file.starred ? 'Unstar' : 'Star'}
                    >
                      <Star size={14} fill={file.starred ? 'currentColor' : 'none'} />
                    </button>
                  </td>
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
                  <td className={styles.actions} onClick={(e) => e.stopPropagation()}>
                    <div style={{ display: 'flex', justifyContent: 'flex-end', gap: '8px', position: 'relative' }}>
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
                      <button 
                        className={styles.menuBtn} 
                        onClick={() => setMenuOpenId(menuOpenId === file.id ? null : file.id)}
                        title="More Actions"
                      >
                        <MoreVertical size={18} />
                      </button>
                      
                      {menuOpenId === file.id && (
                        <div className={styles.dropdownMenu} ref={menuRef}>
                          {file.originalType === 'application/pdf' && (
                            <button onClick={() => handleAction('preview', file)}>
                              <Eye size={14} /> Preview
                            </button>
                          )}
                          <button onClick={() => handleAction('details', file)}>
                            <FileIcon size={14} /> Details
                          </button>
                          <button onClick={() => handleAction('rename', file)}>
                            <Edit2 size={14} /> Rename
                          </button>
                          <button onClick={() => handleAction('move', file)}>
                            <FolderInput size={14} /> Move
                          </button>
                          <button onClick={() => handleAction('copy', file)}>
                            <Copy size={14} /> Copy
                          </button>
                          <div className={styles.menuDivider}></div>
                          <button onClick={() => handleAction('trash', file)} className={styles.dangerAction}>
                            <Trash2 size={14} /> Trash
                          </button>
                        </div>
                      )}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* Action Modals */}
      <ActionModal 
        isOpen={actionModalConfig.isOpen}
        onClose={() => setActionModalConfig({ isOpen: false, type: null, file: null })}
        actionType={actionModalConfig.type}
        fileRec={actionModalConfig.file}
        vaultContext={vaultContext}
        customFolders={customFolders}
        onSuccess={onFileUpdate}
      />
      
      <PdfPreviewModal
        isOpen={previewModalConfig.isOpen}
        onClose={() => setPreviewModalConfig({ isOpen: false, file: null })}
        fileRec={previewModalConfig.file}
        aesKey={aesKey}
      />
    </div>
  );
}

const FolderEmptyIcon = () => (
  <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1" strokeLinecap="round" strokeLinejoin="round">
    <path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"></path>
  </svg>
);
