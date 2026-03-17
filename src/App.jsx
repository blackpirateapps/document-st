import { useState, useEffect, useRef } from 'react';
import MasterPassword from './components/MasterPassword';
import Sidebar from './components/Sidebar';
import FileList from './components/FileList';
import FileDetailView from './components/FileDetailView';
import UploadModal from './components/UploadModal';
import { Plus, Menu } from 'lucide-react';
import styles from './App.module.css';
import {
  decryptMetadata,
  decryptFile,
  deriveKey,
  encryptFile,
  encryptMetadata,
  generateUUID,
} from './utils/crypto';

const STATIC_SALT = new Uint8Array([
  1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
]);

async function fetchCloudinaryConfig(authPassword) {
  const res = await fetch('/api/cloudinary-config', {
    headers: {
      Authorization: `Bearer ${authPassword}`,
    },
  });
  if (!res.ok) {
    throw new Error('Failed to fetch Cloudinary upload config');
  }
  return res.json();
}

async function uploadEncryptedBlobDirect(encryptedBlob, authPassword) {
  const cfg = await fetchCloudinaryConfig(authPassword);
  const endpoint = `https://api.cloudinary.com/v1_1/${cfg.cloudName}/${cfg.resourceType}/upload`;
  const formData = new FormData();
  formData.append('file', encryptedBlob, 'encrypted_blob');
  formData.append('upload_preset', cfg.uploadPreset);

  const res = await fetch(endpoint, {
    method: 'POST',
    body: formData,
  });

  if (!res.ok) {
    const details = await res.text().catch(() => 'Unknown Cloudinary error');
    throw new Error(`Cloudinary upload failed: ${details}`);
  }

  const data = await res.json();
  if (!data?.secure_url) {
    throw new Error('Cloudinary upload succeeded without secure_url');
  }
  return data.secure_url;
}

function normalizeFileMetadata(meta, fallbackDate) {
  const rawProps = Array.isArray(meta?.properties) ? meta.properties : [];
  const properties = rawProps.map((p) => ({
    key: p?.key?.toString?.() || '',
    value: p?.value?.toString?.() || '',
  }));
  const fileIv = Array.isArray(meta?.fileIv)
    ? meta.fileIv.map((v) => Number(v))
    : [];

  return {
    originalName: meta?.originalName?.toString?.() || 'Unknown',
    originalType:
      meta?.originalType?.toString?.() || 'application/octet-stream',
    size: Number(meta?.size || 0),
    folderId: meta?.folderId?.toString?.() || 'inbox',
    fileIv,
    starred: meta?.starred === true,
    description: meta?.description?.toString?.() || '',
    properties,
    dateAdded:
      meta?.dateAdded?.toString?.() || fallbackDate || new Date().toISOString(),
  };
}

function normalizeFolderMetadata(meta, fallbackDate) {
  return {
    name: meta?.name?.toString?.() || 'Unnamed',
    parentId: meta?.parentId ?? null,
    dateAdded:
      meta?.dateAdded?.toString?.() || fallbackDate || new Date().toISOString(),
  };
}

function App() {
  const [vaultContext, setVaultContext] = useState(null);
  const [currentFolder, setCurrentFolder] = useState('inbox');
  const [isUploadModalOpen, setIsUploadModalOpen] = useState(false);

  const [files, setFiles] = useState([]);
  const [folders, setFolders] = useState([]);
  const [isLoading, setIsLoading] = useState(false);
  const [isSidebarOpen, setIsSidebarOpen] = useState(false);
  const [isDragActive, setIsDragActive] = useState(false);
  const dragCounterRef = useRef(0);

  const [selectedFile, setSelectedFile] = useState(null);
  const [recoveryState, setRecoveryState] = useState({
    needed: false,
    fileRows: [],
    folderRows: [],
    previousPassword: '',
    isMigrating: false,
    error: '',
  });

  const handleUnlock = ({ key, password }) => {
    setVaultContext({ aesKey: key, authPassword: password });
  };

  const handleUploadSuccess = (newFileRecord) => {
    setFiles((prev) => [newFileRecord, ...prev]);
  };

  const handleFolderCreateSuccess = (newFolderRecord) => {
    setFolders((prev) => [...prev, newFolderRecord]);
  };

  const handleUploadFiles = async (selectedFiles, folderId = currentFolder) => {
    if (!selectedFiles?.length || !vaultContext) return;

    const uploaded = [];
    const failures = [];

    for (const file of selectedFiles) {
      try {
        const { encryptedBlob, iv, originalName, originalType, size } =
          await encryptFile(file, vaultContext.aesKey);

        const cloudinary_url = await uploadEncryptedBlobDirect(
          encryptedBlob,
          vaultContext.authPassword,
        );

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
          dateAdded: new Date().toISOString(),
        };

        const encryptedMeta = await encryptMetadata(
          metadataToEncrypt,
          vaultContext.aesKey,
        );
        const dbRes = await fetch('/api/files', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${vaultContext.authPassword}`,
          },
          body: JSON.stringify({
            id: blobId,
            encrypted_metadata: encryptedMeta.data,
            metadata_iv: JSON.stringify(encryptedMeta.iv),
            cloudinary_url,
          }),
        });

        if (!dbRes.ok) throw new Error('Failed to save metadata to database');

        uploaded.push({
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
          dateAdded: metadataToEncrypt.dateAdded,
        });
      } catch (err) {
        console.error('Upload failed for file:', file?.name, err);
        failures.push(file?.name || 'unknown file');
      }
    }

    if (uploaded.length) {
      setFiles((prev) => [...uploaded, ...prev]);
    }

    if (failures.length) {
      alert(`Some files failed to upload: ${failures.join(', ')}`);
    }
  };

  const handleRecoverVault = async () => {
    if (!recoveryState.previousPassword || recoveryState.isMigrating || !vaultContext) {
      return;
    }

    setRecoveryState((prev) => ({ ...prev, isMigrating: true, error: '' }));

    try {
      const { key: oldKey } = await deriveKey(
        recoveryState.previousPassword,
        STATIC_SALT,
      );

      const migratedFiles = [];
      for (const row of recoveryState.fileRows) {
        const oldIv = JSON.parse(row.metadata_iv);
        const oldMeta = await decryptMetadata(row.encrypted_metadata, oldIv, oldKey);
        const normalizedMeta = normalizeFileMetadata(oldMeta, row.created_at);

        const blobRes = await fetch(row.cloudinary_url);
        if (!blobRes.ok) {
          throw new Error(`Failed to fetch encrypted blob for ${row.id}`);
        }
        const encryptedBlob = await blobRes.blob();
        const plainBlob = await decryptFile(
          encryptedBlob,
          oldKey,
          normalizedMeta.fileIv,
          normalizedMeta.originalType,
        );

        const fileLike = {
          arrayBuffer: () => plainBlob.arrayBuffer(),
          name: normalizedMeta.originalName,
          type: normalizedMeta.originalType,
          size: normalizedMeta.size,
        };

        const reencrypted = await encryptFile(fileLike, vaultContext.aesKey);
        const nextMeta = {
          ...normalizedMeta,
          fileIv: Array.from(reencrypted.iv),
        };
        const encryptedMeta = await encryptMetadata(nextMeta, vaultContext.aesKey);

        const nextCloudinaryUrl = await uploadEncryptedBlobDirect(
          reencrypted.encryptedBlob,
          vaultContext.authPassword,
        );

        const updateRes = await fetch('/api/files', {
          method: 'PUT',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${vaultContext.authPassword}`,
          },
          body: JSON.stringify({
            id: row.id,
            encrypted_metadata: encryptedMeta.data,
            metadata_iv: JSON.stringify(encryptedMeta.iv),
            cloudinary_url: nextCloudinaryUrl,
          }),
        });
        if (!updateRes.ok) {
          throw new Error(`Failed to update migrated file metadata for ${row.id}`);
        }

        migratedFiles.push({
          id: row.id,
          cloudinary_url: nextCloudinaryUrl,
          ...nextMeta,
        });
      }

      const migratedFolders = [];
      for (const row of recoveryState.folderRows) {
        const oldIv = JSON.parse(row.metadata_iv);
        const oldMeta = await decryptMetadata(row.encrypted_metadata, oldIv, oldKey);
        const nextMeta = normalizeFolderMetadata(oldMeta, row.created_at);
        const encryptedMeta = await encryptMetadata(nextMeta, vaultContext.aesKey);

        const updateRes = await fetch('/api/folders', {
          method: 'PUT',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${vaultContext.authPassword}`,
          },
          body: JSON.stringify({
            id: row.id,
            encrypted_metadata: encryptedMeta.data,
            metadata_iv: JSON.stringify(encryptedMeta.iv),
          }),
        });
        if (!updateRes.ok) {
          throw new Error(`Failed to update migrated folder metadata for ${row.id}`);
        }

        migratedFolders.push({
          id: row.id,
          ...nextMeta,
        });
      }

      setFiles(migratedFiles);
      setFolders(migratedFolders);
      setRecoveryState({
        needed: false,
        fileRows: [],
        folderRows: [],
        previousPassword: '',
        isMigrating: false,
        error: '',
      });
      alert(
        'Vault migration complete. Your files and metadata are now encrypted with the new password.',
      );
    } catch (err) {
      setRecoveryState((prev) => ({
        ...prev,
        isMigrating: false,
        error: err?.message || 'Failed to recover and re-encrypt vault data.',
      }));
    }
  };

  useEffect(() => {
    if (!vaultContext) return;

    const fetchData = async () => {
      setIsLoading(true);
      try {
        const resFiles = await fetch('/api/files', {
          headers: { Authorization: `Bearer ${vaultContext.authPassword}` },
        });
        if (!resFiles.ok) throw new Error('Failed to fetch files');
        const fileData = await resFiles.json();

        let failedFiles = 0;
        const decryptedFiles = await Promise.all(
          fileData.map(async (row) => {
            try {
              const ivArray = JSON.parse(row.metadata_iv);
              const meta = await decryptMetadata(
                row.encrypted_metadata,
                ivArray,
                vaultContext.aesKey,
              );
              const normalized = normalizeFileMetadata(meta, row.created_at);
              return {
                id: row.id,
                cloudinary_url: row.cloudinary_url,
                ...normalized,
              };
            } catch (e) {
              console.error('Failed to decrypt file', row.id, e);
              failedFiles += 1;
              return null;
            }
          }),
        );
        const validFiles = decryptedFiles.filter(Boolean);

        const resFolders = await fetch('/api/folders', {
          headers: { Authorization: `Bearer ${vaultContext.authPassword}` },
        });
        if (resFolders.ok) {
          const folderData = await resFolders.json();
          let failedFolders = 0;
          const decryptedFolders = await Promise.all(
            folderData.map(async (row) => {
              try {
                const ivArray = JSON.parse(row.metadata_iv);
                const meta = await decryptMetadata(
                  row.encrypted_metadata,
                  ivArray,
                  vaultContext.aesKey,
                );
                return {
                  id: row.id,
                  ...normalizeFolderMetadata(meta, row.created_at),
                };
              } catch (e) {
                console.error('Failed to decrypt folder', row.id, e);
                failedFolders += 1;
                return null;
              }
            }),
          );
          const validFolders = decryptedFolders.filter(Boolean);

          const totalRows = fileData.length + folderData.length;
          const totalDecrypted = validFiles.length + validFolders.length;
          const totalFailed = failedFiles + failedFolders;

          if (totalRows > 0 && totalDecrypted === 0 && totalFailed > 0) {
            setFiles([]);
            setFolders([]);
            setRecoveryState({
              needed: true,
              fileRows: fileData,
              folderRows: folderData,
              previousPassword: '',
              isMigrating: false,
              error: '',
            });
          } else {
            setFiles(validFiles);
            setFolders(validFolders);
            setRecoveryState((prev) => ({
              ...prev,
              needed: false,
              fileRows: [],
              folderRows: [],
              previousPassword: '',
              isMigrating: false,
              error: '',
            }));
          }
        } else {
          setFiles(validFiles);
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
    if (!vaultContext || recoveryState.needed) return;

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
  }, [vaultContext, currentFolder, recoveryState.needed]);

  if (!vaultContext) {
    return <MasterPassword onUnlock={handleUnlock} />;
  }

  const handleFileUpdate = (updatedFile) => {
    setFiles((prev) => prev.map((f) => (f.id === updatedFile.id ? updatedFile : f)));
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

      {isSidebarOpen && (
        <button
          className={styles.mobileSidebarBackdrop}
          onClick={() => setIsSidebarOpen(false)}
          aria-label="Close folders"
        />
      )}

      <Sidebar
        currentFolder={currentFolder}
        onSelectFolder={(folderId) => {
          setCurrentFolder(folderId);
          setSelectedFile(null);
          setIsSidebarOpen(false);
        }}
        customFolders={folders}
        vaultContext={vaultContext}
        onFolderCreateSuccess={handleFolderCreateSuccess}
        isMobileOpen={isSidebarOpen}
        onCloseMobile={() => setIsSidebarOpen(false)}
      />

      <main className={styles.mainContent}>
        {isLoading ? (
          <div
            style={{
              padding: '32px',
              color: 'var(--text-secondary)',
              fontSize: 'var(--text-subheadline)',
            }}
          >
            Decrypting vault...
          </div>
        ) : recoveryState.needed ? (
          <div className={styles.recoveryWrap}>
            <div className={styles.recoveryCard}>
              <h2 className={styles.recoveryTitle}>Vault Re-encryption Required</h2>
              <p className={styles.recoveryText}>
                Your files appear to be encrypted with a previous password. Enter
                the old decryption password to migrate all file blobs and metadata
                to your current password.
              </p>
              <input
                type="password"
                className={styles.recoveryInput}
                placeholder="Previous decryption password"
                value={recoveryState.previousPassword}
                onChange={(e) =>
                  setRecoveryState((prev) => ({
                    ...prev,
                    previousPassword: e.target.value,
                    error: '',
                  }))
                }
                disabled={recoveryState.isMigrating}
              />
              {recoveryState.error && (
                <p className={styles.recoveryError}>{recoveryState.error}</p>
              )}
              <button
                className={styles.recoveryButton}
                onClick={handleRecoverVault}
                disabled={
                  recoveryState.isMigrating || !recoveryState.previousPassword
                }
              >
                {recoveryState.isMigrating
                  ? 'Re-encrypting Vault...'
                  : 'Recover and Re-encrypt Vault'}
              </button>
            </div>
          </div>
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

        {!selectedFile && !recoveryState.needed && (
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
            <span className={styles.globalDropTitle}>
              Drop to Encrypt and Upload
            </span>
            <span className={styles.globalDropSubtitle}>
              Files are encrypted locally before upload.
            </span>
          </div>
        </div>
      )}
    </div>
  );
}

export default App;
