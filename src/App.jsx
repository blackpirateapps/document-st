import { useState, useEffect } from 'react';
import MasterPassword from './components/MasterPassword';
import Sidebar from './components/Sidebar';
import FileList from './components/FileList';
import UploadModal from './components/UploadModal';
import { Plus } from 'lucide-react';
import styles from './App.module.css';
import { decryptMetadata } from './utils/crypto';

function App() {
  const [vaultContext, setVaultContext] = useState(null); // { aesKey, authPassword }
  const [currentFolder, setCurrentFolder] = useState('inbox');
  const [isUploadModalOpen, setIsUploadModalOpen] = useState(false);
  
  const [files, setFiles] = useState([]);
  const [folders, setFolders] = useState([]);
  const [isLoading, setIsLoading] = useState(false);

  const handleUnlock = ({ key, password }) => {
    setVaultContext({ aesKey: key, authPassword: password });
  };

  const handleUploadSuccess = (newFileRecord) => {
    setFiles(prev => [newFileRecord, ...prev]);
  };

  const handleFolderCreateSuccess = (newFolderRecord) => {
    setFolders(prev => [...prev, newFolderRecord]);
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

  // If the vault is locked, show the unlock screen
  if (!vaultContext) {
    return <MasterPassword onUnlock={handleUnlock} />;
  }

  // Update files in state after a move/rename
  const handleFileUpdate = (updatedFile) => {
    setFiles(prev => prev.map(f => f.id === updatedFile.id ? updatedFile : f));
  };

  return (
    <div className={styles.appContainer}>
      <Sidebar 
        currentFolder={currentFolder} 
        onSelectFolder={setCurrentFolder} 
        customFolders={folders}
        vaultContext={vaultContext}
        onFolderCreateSuccess={handleFolderCreateSuccess}
      />
      
      <main className={styles.mainContent}>
        {isLoading ? (
          <div style={{ padding: '40px', color: 'var(--text-secondary)' }}>Decrypting vault...</div>
        ) : (
          <FileList 
            files={files} 
            aesKey={vaultContext.aesKey} 
            currentFolder={currentFolder}
            vaultContext={vaultContext}
            customFolders={folders}
            onFileUpdate={handleFileUpdate}
            onFileCopy={handleUploadSuccess}
          />
        )}
        
        <button 
          className={styles.fab} 
          onClick={() => setIsUploadModalOpen(true)}
          title="Add File"
        >
          <Plus size={24} />
        </button>
      </main>

      <UploadModal 
        isOpen={isUploadModalOpen} 
        onClose={() => setIsUploadModalOpen(false)} 
        vaultContext={vaultContext}
        currentFolder={currentFolder}
        customFolders={folders}
        onUploadSuccess={handleUploadSuccess}
      />
    </div>
  );
}

export default App;
