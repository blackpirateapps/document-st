import { useState, useEffect, useRef } from 'react';
import MasterPassword from './components/MasterPassword';
import Sidebar from './components/Sidebar';
import FileList from './components/FileList';
import FileDetailView from './components/FileDetailView';
import UploadModal from './components/UploadModal';
import { Plus, Menu } from 'lucide-react';
import styles from './App.module.css';
import { decryptMetadata, encryptFile, encryptMetadata, generateUUID } from './utils/crypto';

function App() {
  const [vaultContext, setVaultContext] = useState(null); // { aesKey, authPassword }
  const [currentFolder, setCurrentFolder] = useState('inbox');
  const [isUploadModalOpen, setIsUploadModalOpen] = useState(false);
  
  const [files, setFiles] = useState([]);
  const [folders, setFolders] = useState([]);
  const [isLoading, setIsLoading] = useState(false);
  const [isSidebarOpen, setIsSidebarOpen] = useState(false);
  const [isDragActive, setIsDragActive] = useState(false);
  const dragCounterRef = useRef(0);

  // Detail view state: when a file is selected, show its detail page
  const [selectedFile, setSelectedFile] = useState(null);

  const handleUnlock = ({ key, password }) => {
    setVaultContext({ aesKey: key, authPassword: password });
  };

  const handleUploadSuccess = (newFileRecord) => {
    setFiles(prev => [newFileRecord, ...prev]);
  };

  const handleFolderCreateSuccess = (newFolderRecord) => {
    setFolders(prev => [...prev, newFolderRecord]);
  };

  const handleUploadFiles = async (selectedFiles, folderId = currentFolder) => {
    if (!selectedFiles?.length || !vaultContext) return;

    const uploaded = [];
    const failures = [];

    for (const file of selectedFiles) {
      try {
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
          folderId,
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

        const newFileRecord = {
          id: blobId,
          cloudinary_url,
          originalName,
          originalType,
          size,
          folderId,
          fileIv: Array.from(iv),
          starred: false,
          description: '',
          properties: [],
          dateAdded: metadataToEncrypt.dateAdded
        };

        uploaded.push(newFileRecord);
      } catch (err) {
        console.error('Upload failed for file:', file?.name, err);
        failures.push(file?.name || 'unknown file');
      }
    }

    if (uploaded.length) {
      setFiles(prev => [...uploaded, ...prev]);
    }

    if (failures.length) {
      alert(`Some files failed to upload: ${failures.join(', ')}`);
    }
  };

  // Fetch and decrypt files and folders when unlocked
  useEffect(() => {
    if (!vaultContext) return;

    const fetchData = async () => {
      setIsLoading(true);
      try {
        // Fetch files
        const resFiles = await fetch('/api/files', {
          headers: { 'Authorization': `Bearer ${vaultContext.authPassword}` }
        });
        if (!resFiles.ok) throw new Error('Failed to fetch files');
        const fileData = await resFiles.json();

        // Decrypt files
        const decryptedFiles = await Promise.all(fileData.map(async (row) => {
          try {
            const ivArray = JSON.parse(row.metadata_iv);
            const meta = await decryptMetadata(row.encrypted_metadata, ivArray, vaultContext.aesKey);
            return {
              id: row.id,
              cloudinary_url: row.cloudinary_url,
              originalName: meta.originalName,
              originalType: meta.originalType,
              size: meta.size,
              folderId: meta.folderId,
              fileIv: meta.fileIv,
              starred: meta.starred || false,
              description: meta.description || '',
              properties: meta.properties || [],
              dateAdded: meta.dateAdded || row.created_at
            };
          } catch (e) {
            console.error('Failed to decrypt file', row.id, e);
            return null;
          }
        }));
        setFiles(decryptedFiles.filter(Boolean));

        // Fetch folders
        const resFolders = await fetch('/api/folders', {
          headers: { 'Authorization': `Bearer ${vaultContext.authPassword}` }
        });
        if (resFolders.ok) {
          const folderData = await resFolders.json();
          const decryptedFolders = await Promise.all(folderData.map(async (row) => {
            try {
              const ivArray = JSON.parse(row.metadata_iv);
              const meta = await decryptMetadata(row.encrypted_metadata, ivArray, vaultContext.aesKey);
              return {
                id: row.id,
                name: meta.name,
                parentId: meta.parentId || null,
                dateAdded: meta.dateAdded || row.created_at
              };
            } catch (e) {
              console.error('Failed to decrypt folder', row.id, e);
              return null;
            }
          }));
          setFolders(decryptedFolders.filter(Boolean));
        }

      } catch (err) {
        console.error(err);
      } finally {
        setIsLoading(false);
      }
    };

    fetchData();
  }, [vaultContext]);

  useEffect(() => {
    if (!vaultContext) return;

    const hasFiles = (event) => {
      const types = event.dataTransfer?.types;
      return types && Array.from(types).includes('Files');
    };

    const onDragEnter = (event) => {
      if (!hasFiles(event)) return;
      event.preventDefault();
      dragCounterRef.current += 1;
      setIsDragActive(true);
    };

    const onDragOver = (event) => {
      if (!hasFiles(event)) return;
      event.preventDefault();
    };

    const onDragLeave = (event) => {
      if (!hasFiles(event)) return;
      event.preventDefault();
      dragCounterRef.current = Math.max(0, dragCounterRef.current - 1);
      if (dragCounterRef.current === 0) {
        setIsDragActive(false);
      }
    };

    const onDrop = async (event) => {
      if (!hasFiles(event)) return;
      event.preventDefault();
      dragCounterRef.current = 0;
      setIsDragActive(false);
      const droppedFiles = Array.from(event.dataTransfer?.files || []);
      if (!droppedFiles.length) return;
      await handleUploadFiles(droppedFiles, currentFolder);
    };

    window.addEventListener('dragenter', onDragEnter);
    window.addEventListener('dragover', onDragOver);
    window.addEventListener('dragleave', onDragLeave);
    window.addEventListener('drop', onDrop);

    return () => {
      window.removeEventListener('dragenter', onDragEnter);
      window.removeEventListener('dragover', onDragOver);
      window.removeEventListener('dragleave', onDragLeave);
      window.removeEventListener('drop', onDrop);
    };
  }, [vaultContext, currentFolder]);

  // If the vault is locked, show the unlock screen
  if (!vaultContext) {
    return <MasterPassword onUnlock={handleUnlock} />;
  }

  // Update files in state after a move/rename/star/edit
  const handleFileUpdate = (updatedFile) => {
    setFiles(prev => prev.map(f => f.id === updatedFile.id ? updatedFile : f));
    // If the detail view is open for this file, update it too
    if (selectedFile && selectedFile.id === updatedFile.id) {
      setSelectedFile(updatedFile);
    }
  };

  const handleSelectFile = (file) => {
    setSelectedFile(file);
  };

  const handleBackToList = () => {
    setSelectedFile(null);
  };

  return (
    <div className={styles.appContainer}>
      <button
        className={styles.mobileMenuButton}
        onClick={() => setIsSidebarOpen(true)}
        aria-label="Open folders"
      >
        <Menu size={20} />
      </button>

      {isSidebarOpen && <button className={styles.mobileSidebarBackdrop} onClick={() => setIsSidebarOpen(false)} aria-label="Close folders" />}

      <Sidebar 
        currentFolder={currentFolder} 
        onSelectFolder={(folderId) => { setCurrentFolder(folderId); setSelectedFile(null); setIsSidebarOpen(false); }} 
        customFolders={folders}
        vaultContext={vaultContext}
        onFolderCreateSuccess={handleFolderCreateSuccess}
        isMobileOpen={isSidebarOpen}
        onCloseMobile={() => setIsSidebarOpen(false)}
      />
      
      <main className={styles.mainContent}>
        {isLoading ? (
          <div style={{ padding: '32px', color: 'var(--text-secondary)', fontSize: 'var(--text-subheadline)' }}>Decrypting vault...</div>
        ) : selectedFile ? (
          <FileDetailView
            file={selectedFile}
            vaultContext={vaultContext}
            customFolders={folders}
            onFileUpdate={handleFileUpdate}
            onBack={handleBackToList}
            aesKey={vaultContext.aesKey}
          />
        ) : (
          <FileList 
            files={files} 
            aesKey={vaultContext.aesKey} 
            currentFolder={currentFolder}
            vaultContext={vaultContext}
            customFolders={folders}
            onFileUpdate={handleFileUpdate}
            onFileCopy={handleUploadSuccess}
            onSelectFile={handleSelectFile}
          />
        )}
        
        {!selectedFile && (
          <button 
            className={styles.fab} 
            onClick={() => setIsUploadModalOpen(true)}
            title="Add File"
          >
            <Plus size={24} />
          </button>
        )}
      </main>

      <UploadModal 
        isOpen={isUploadModalOpen} 
        onClose={() => setIsUploadModalOpen(false)} 
        vaultContext={vaultContext}
        currentFolder={currentFolder}
        customFolders={folders}
        onUploadSuccess={handleUploadSuccess}
        onUploadFiles={handleUploadFiles}
      />

      {isDragActive && (
        <div className={styles.globalDropOverlay}>
          <div className={styles.globalDropCard}>
            <span className={styles.globalDropTitle}>Drop to Encrypt and Upload</span>
            <span className={styles.globalDropSubtitle}>Files are encrypted locally before upload.</span>
          </div>
        </div>
      )}
    </div>
  );
}

export default App;
