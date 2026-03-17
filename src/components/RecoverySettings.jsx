import { useMemo, useState } from 'react';
import styles from './RecoverySettings.module.css';
import { decryptFile, decryptMetadata, deriveKey, encryptFile, encryptMetadata } from '../utils/crypto';

const STATIC_SALT = new Uint8Array([
  1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
]);

function normalizeFileMetadata(meta, fallbackDate) {
  const rawProps = Array.isArray(meta?.properties) ? meta.properties : [];
  const properties = rawProps.map((p) => ({
    key: p?.key?.toString?.() || '',
    value: p?.value?.toString?.() || '',
  }));

  return {
    originalName: meta?.originalName?.toString?.() || 'Unknown',
    originalType:
      meta?.originalType?.toString?.() || 'application/octet-stream',
    size: Number(meta?.size || 0),
    folderId: meta?.folderId?.toString?.() || 'inbox',
    fileIv: Array.isArray(meta?.fileIv) ? meta.fileIv.map((v) => Number(v)) : [],
    starred: meta?.starred === true,
    description: meta?.description?.toString?.() || '',
    properties,
    dateAdded:
      meta?.dateAdded?.toString?.() || fallbackDate || new Date().toISOString(),
  };
}

async function uploadEncryptedBlobDirect(encryptedBlob, authPassword) {
  const cfgRes = await fetch('/api/cloudinary-config', {
    headers: {
      Authorization: `Bearer ${authPassword}`,
    },
  });
  if (!cfgRes.ok) {
    throw new Error('Failed to fetch Cloudinary upload config');
  }
  const cfg = await cfgRes.json();
  const endpoint = `https://api.cloudinary.com/v1_1/${cfg.cloudName}/${cfg.resourceType}/upload`;

  const formData = new FormData();
  formData.append('file', encryptedBlob, 'encrypted_blob');
  formData.append('upload_preset', cfg.uploadPreset);

  const uploadRes = await fetch(endpoint, {
    method: 'POST',
    body: formData,
  });
  if (!uploadRes.ok) {
    const details = await uploadRes.text().catch(() => 'Unknown Cloudinary error');
    throw new Error(`Cloudinary upload failed: ${details}`);
  }
  const data = await uploadRes.json();
  return data.secure_url;
}

export default function RecoverySettings({ vaultContext, onMigrationApplied }) {
  const [rawFiles, setRawFiles] = useState([]);
  const [loadingRows, setLoadingRows] = useState(false);
  const [rowsError, setRowsError] = useState('');
  const [selectedId, setSelectedId] = useState('');
  const [previousPassword, setPreviousPassword] = useState('');
  const [status, setStatus] = useState('');
  const [running, setRunning] = useState(false);

  const selectedRow = useMemo(
    () => rawFiles.find((row) => row.id === selectedId) || null,
    [rawFiles, selectedId],
  );

  const scanRows = async () => {
    setLoadingRows(true);
    setRowsError('');
    setStatus('');
    try {
      const res = await fetch('/api/files', {
        headers: { Authorization: `Bearer ${vaultContext.authPassword}` },
      });
      if (!res.ok) throw new Error('Failed to fetch file metadata records');
      const rows = await res.json();

      const failed = [];
      for (const row of rows) {
        try {
          const iv = JSON.parse(row.metadata_iv);
          await decryptMetadata(row.encrypted_metadata, iv, vaultContext.aesKey);
        } catch (_) {
          failed.push(row);
        }
      }

      setRawFiles(failed);
      if (failed.length === 0) {
        setStatus('No failed file decryptions found for current key.');
      } else {
        setStatus(`Found ${failed.length} file entries that failed decryption.`);
      }
      if (!failed.some((row) => row.id === selectedId)) {
        setSelectedId(failed[0]?.id || '');
      }
    } catch (e) {
      setRowsError(e?.message || 'Failed to scan for recoverable entries.');
    } finally {
      setLoadingRows(false);
    }
  };

  const recoverSelected = async () => {
    if (!selectedRow || !previousPassword || running) return;

    setRunning(true);
    setRowsError('');
    setStatus('Decrypting with previous password...');
    try {
      const { key: oldKey } = await deriveKey(previousPassword, STATIC_SALT);
      const oldIv = JSON.parse(selectedRow.metadata_iv);
      const oldMeta = await decryptMetadata(selectedRow.encrypted_metadata, oldIv, oldKey);
      const normalized = normalizeFileMetadata(oldMeta, selectedRow.created_at);

      const blobRes = await fetch(selectedRow.cloudinary_url);
      if (!blobRes.ok) {
        throw new Error('Failed to fetch encrypted blob from Cloudinary');
      }
      const encryptedBlob = await blobRes.blob();
      const plainBlob = await decryptFile(
        encryptedBlob,
        oldKey,
        normalized.fileIv,
        normalized.originalType,
      );

      setStatus('Re-encrypting with current password...');
      const fileLike = {
        arrayBuffer: () => plainBlob.arrayBuffer(),
        name: normalized.originalName,
        type: normalized.originalType,
        size: normalized.size,
      };
      const reencrypted = await encryptFile(fileLike, vaultContext.aesKey);
      const nextMeta = {
        ...normalized,
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
          id: selectedRow.id,
          encrypted_metadata: encryptedMeta.data,
          metadata_iv: JSON.stringify(encryptedMeta.iv),
          cloudinary_url: nextCloudinaryUrl,
        }),
      });

      if (!updateRes.ok) {
        throw new Error('Failed to persist re-encrypted metadata');
      }

      setStatus('Entry migrated successfully.');
      setPreviousPassword('');
      await scanRows();
      if (onMigrationApplied) {
        await onMigrationApplied();
      }
    } catch (e) {
      setRowsError(e?.message || 'Failed to recover selected entry.');
    } finally {
      setRunning(false);
    }
  };

  return (
    <section className={styles.wrap}>
      <h2 className={styles.title}>Recovery Settings</h2>
      <p className={styles.subtitle}>
        Recover specific file entries that fail to decrypt with your current password.
      </p>

      <button
        className={styles.button}
        onClick={scanRows}
        disabled={loadingRows || running}
      >
        {loadingRows ? 'Scanning...' : 'Scan Failed File Entries'}
      </button>

      {rowsError && <p className={styles.error}>{rowsError}</p>}
      {status && <p className={styles.status}>{status}</p>}

      {rawFiles.length > 0 && (
        <div className={styles.formCard}>
          <label className={styles.label} htmlFor="failed-entry">
            Failed Entry
          </label>
          <select
            id="failed-entry"
            className={styles.select}
            value={selectedId}
            onChange={(e) => setSelectedId(e.target.value)}
            disabled={running}
          >
            {rawFiles.map((row) => (
              <option key={row.id} value={row.id}>
                {row.id}
              </option>
            ))}
          </select>

          <label className={styles.label} htmlFor="prev-pass">
            Previous Decryption Password
          </label>
          <input
            id="prev-pass"
            type="password"
            className={styles.input}
            value={previousPassword}
            onChange={(e) => setPreviousPassword(e.target.value)}
            placeholder="Enter previous password for selected entry"
            disabled={running}
          />

          <button
            className={styles.button}
            onClick={recoverSelected}
            disabled={running || !selectedRow || !previousPassword}
          >
            {running ? 'Recovering...' : 'Recover and Re-encrypt Selected Entry'}
          </button>
        </div>
      )}
    </section>
  );
}
