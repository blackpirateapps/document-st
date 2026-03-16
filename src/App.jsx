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
  const [isLoading, setIsLoading] = useState(false);

  const handleUnlock = ({ key, password }) => {
    setVaultContext({ aesKey: key, authPassword: password });
  };

  const handleUploadSuccess = (newFileRecord) => {
    setFiles(prev => [newFileRecord, ...prev]);
  };

  // Fetch and decrypt files when unlocked
  useEffect(() => {
    if (!vaultContext) return;

    const fetchFiles = async () => {
      setIsLoading(true);
      try {
        const res = await fetch('/api/files', {
          headers: { 'Authorization': `Bearer ${vaultContext.authPassword}` }
        });
        if (!res.ok) throw new Error('Failed to fetch files');
        
        const data = await res.json();

        // Decrypt metadata for all files
        const decryptedFiles = await Promise.all(data.map(async (row) => {
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
              fileIv: meta.fileIv, // The IV for the blob
              dateAdded: meta.dateAdded || row.created_at
            };
          } catch (e) {
            console.error('Failed to decrypt metadata for file', row.id, e);
            return null; // Skip if decryption fails
          }
        }));

        setFiles(decryptedFiles.filter(Boolean));
      } catch (err) {
        console.error(err);
      } finally {
        setIsLoading(false);
      }
    };

    fetchFiles();
  }, [vaultContext]);

  // If the vault is locked, show the unlock screen
  if (!vaultContext) {
    return <MasterPassword onUnlock={handleUnlock} />;
  }

  return (
    <div className={styles.appContainer}>
      <Sidebar 
        currentFolder={currentFolder} 
        onSelectFolder={setCurrentFolder} 
      />
      
      <main className={styles.mainContent}>
        {isLoading ? (
          <div style={{ padding: '40px', color: 'var(--text-secondary)' }}>Decrypting vault...</div>
        ) : (
          <FileList 
            files={files} 
            aesKey={vaultContext.aesKey} 
            currentFolder={currentFolder} 
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
        onUploadSuccess={handleUploadSuccess}
      />
    </div>
  );
}

export default App;
