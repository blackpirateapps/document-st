import { useState } from 'react';
import { ArrowLeft, Star, Download, Eye, FileIcon, Plus, X, Folder, Clock } from 'lucide-react';
import styles from './FileDetailView.module.css';
import { encryptMetadata, decryptFile } from '../utils/crypto';
import PdfPreviewModal from './PdfPreviewModal';

export default function FileDetailView({ file, vaultContext, customFolders, onFileUpdate, onBack, aesKey }) {
  const [description, setDescription] = useState(file.description || '');
  const [properties, setProperties] = useState(file.properties || []);
  const [starred, setStarred] = useState(file.starred || false);
  const [isSaving, setIsSaving] = useState(false);
  const [isDownloading, setIsDownloading] = useState(false);
  const [previewOpen, setPreviewOpen] = useState(false);

  const isPdf = file.originalType === 'application/pdf';

  // Determine if any edits have been made
  const hasChanges =
    description !== (file.description || '') ||
    starred !== (file.starred || false) ||
    JSON.stringify(properties) !== JSON.stringify(file.properties || []);

  const handleSave = async () => {
    setIsSaving(true);
    try {
      const metaToEncrypt = {
        originalName: file.originalName,
        originalType: file.originalType,
        size: file.size,
        folderId: file.folderId,
        fileIv: file.fileIv,
        starred,
        description,
        properties: properties.filter(p => p.key.trim() || p.value.trim()),
        dateAdded: file.dateAdded
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
      if (!dbRes.ok) throw new Error('Failed to save');
      onFileUpdate({
        ...file,
        starred,
        description,
        properties: properties.filter(p => p.key.trim() || p.value.trim())
      });
    } catch (_e) {
      alert('Failed to save file details.');
    } finally {
      setIsSaving(false);
    }
  };

  const handleDownload = async () => {
    try {
      setIsDownloading(true);
      const response = await fetch(file.cloudinary_url);
      if (!response.ok) throw new Error('Failed to fetch blob');
      const encryptedBlob = await response.blob();
      const decryptedBlob = await decryptFile(encryptedBlob, aesKey, file.fileIv, file.originalType);
      const url = URL.createObjectURL(decryptedBlob);
      const a = document.createElement('a');
      a.href = url;
      a.download = file.originalName;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
    } catch (_e) {
      alert('Failed to download file.');
    } finally {
      setIsDownloading(false);
    }
  };

  const handleAddProperty = () => {
    setProperties(prev => [...prev, { key: '', value: '' }]);
  };

  const handlePropertyChange = (index, field, value) => {
    setProperties(prev => prev.map((p, i) => i === index ? { ...p, [field]: value } : p));
  };

  const handleRemoveProperty = (index) => {
    setProperties(prev => prev.filter((_, i) => i !== index));
  };

  // Resolve folder name
  let folderName = file.folderId;
  const builtinFolders = { inbox: 'Inbox', starred: 'Starred', documents: 'Documents', photos: 'Photos', taxes: 'Taxes', trash: 'Trash' };
  if (builtinFolders[file.folderId]) {
    folderName = builtinFolders[file.folderId];
  } else {
    const cf = customFolders?.find(f => f.id === file.folderId);
    if (cf) folderName = cf.name;
  }

  const formatSize = (bytes) => {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
  };

  return (
    <div className={styles.container}>
      {/* Top Bar */}
      <div className={styles.topBar}>
        <button className={styles.backBtn} onClick={onBack}>
          <ArrowLeft size={16} />
          Back
        </button>
        <span className={styles.topBarTitle}>{file.originalName}</span>
        <div className={styles.topBarActions}>
          <button
            className={`${styles.iconBtn} ${starred ? styles.starActive : ''}`}
            onClick={() => setStarred(s => !s)}
            title={starred ? 'Unstar' : 'Star'}
          >
            <Star size={18} fill={starred ? 'currentColor' : 'none'} />
          </button>
          <button
            className={styles.iconBtn}
            onClick={handleDownload}
            disabled={isDownloading}
            title="Download"
          >
            <Download size={18} />
          </button>
        </div>
      </div>

      {/* Body */}
      <div className={styles.body}>
        {/* File Header */}
        <div className={styles.fileHeader}>
          <div className={styles.fileIconBox}>
            <FileIcon size={28} />
          </div>
          <div className={styles.fileHeaderInfo}>
            <div className={styles.fileHeaderName}>{file.originalName}</div>
            <div className={styles.fileHeaderMeta}>
              {formatSize(file.size)} &middot; {file.originalType || 'Unknown type'}
            </div>
          </div>
        </div>

        {/* PDF Preview Button */}
        {isPdf && (
          <button className={styles.previewBtn} onClick={() => setPreviewOpen(true)}>
            <Eye size={16} />
            Preview PDF
          </button>
        )}

        {/* Description */}
        <div className={styles.section}>
          <label className={styles.sectionLabel}>Description</label>
          <textarea
            className={styles.descriptionTextarea}
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            placeholder="Add a description..."
            rows={3}
          />
        </div>

        {/* Custom Properties */}
        <div className={styles.section}>
          <label className={styles.sectionLabel}>Properties</label>
          <div className={styles.propertiesList}>
            {properties.map((prop, index) => (
              <div key={index} className={styles.propertyRow}>
                <input
                  className={styles.propertyInput}
                  type="text"
                  value={prop.key}
                  onChange={(e) => handlePropertyChange(index, 'key', e.target.value)}
                  placeholder="Key"
                />
                <input
                  className={styles.propertyInput}
                  type="text"
                  value={prop.value}
                  onChange={(e) => handlePropertyChange(index, 'value', e.target.value)}
                  placeholder="Value"
                />
                <button
                  className={styles.removePropertyBtn}
                  onClick={() => handleRemoveProperty(index)}
                  title="Remove property"
                >
                  <X size={14} />
                </button>
              </div>
            ))}
          </div>
          <button className={styles.addPropertyBtn} onClick={handleAddProperty}>
            <Plus size={14} />
            Add Property
          </button>
        </div>

        {/* File Metadata */}
        <div className={styles.section}>
          <label className={styles.sectionLabel}>File Info</label>
          <div className={styles.metadataTable}>
            <div className={styles.metadataRow}>
              <span className={styles.metadataKey}>Name</span>
              <span className={styles.metadataValue}>{file.originalName}</span>
            </div>
            <div className={styles.metadataRow}>
              <span className={styles.metadataKey}>Type</span>
              <span className={styles.metadataValue}>{file.originalType || 'Unknown'}</span>
            </div>
            <div className={styles.metadataRow}>
              <span className={styles.metadataKey}>Size</span>
              <span className={styles.metadataValue}>{formatSize(file.size)}</span>
            </div>
            <div className={styles.metadataRow}>
              <span className={styles.metadataKey}>Folder</span>
              <span className={styles.metadataValue}>
                <span className={styles.folderBadge}>
                  <Folder size={11} />
                  {folderName}
                </span>
              </span>
            </div>
            <div className={styles.metadataRow}>
              <span className={styles.metadataKey}>Date Added</span>
              <span className={styles.metadataValue}>
                {new Date(file.dateAdded).toLocaleDateString(undefined, {
                  year: 'numeric', month: 'long', day: 'numeric',
                  hour: '2-digit', minute: '2-digit'
                })}
              </span>
            </div>
            <div className={styles.metadataRow}>
              <span className={styles.metadataKey}>File ID</span>
              <span className={styles.metadataValue} style={{ fontFamily: 'var(--font-family-mono)', fontSize: 'var(--text-caption2)' }}>
                {file.id}
              </span>
            </div>
          </div>
        </div>

        {/* Save Button */}
        <button
          className={styles.saveBtn}
          onClick={handleSave}
          disabled={isSaving || !hasChanges}
        >
          {isSaving ? 'Saving...' : 'Save Changes'}
        </button>
      </div>

      {/* PDF Preview Modal */}
      {isPdf && (
        <PdfPreviewModal
          isOpen={previewOpen}
          onClose={() => setPreviewOpen(false)}
          fileRec={file}
          aesKey={aesKey}
        />
      )}
    </div>
  );
}
