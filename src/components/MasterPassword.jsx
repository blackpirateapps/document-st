import { useState } from 'react';
import { Lock } from 'lucide-react';
import { deriveKey } from '../utils/crypto';
import styles from './MasterPassword.module.css';

export default function MasterPassword({ onUnlock }) {
  const [password, setPassword] = useState('');
  const [isUnlocking, setIsUnlocking] = useState(false);
  const [error, setError] = useState('');

  const handleUnlock = async (e) => {
    e.preventDefault();
    if (!password) return;

    setIsUnlocking(true);
    setError('');

    try {
      // 1. Authenticate with backend
      const res = await fetch('/api/files', {
        headers: {
          'Authorization': `Bearer ${password}`
        }
      });

      if (!res.ok) {
        if (res.status === 404) {
          throw new Error('API not found (Are you using "vercel dev" instead of "npm run dev"?)');
        } else if (res.status === 401) {
          throw new Error('Invalid master password.');
        } else {
          const errorData = await res.json().catch(() => ({}));
          throw new Error(`Server error (${res.status}): ${errorData.error || 'Unknown error'}`);
        }
      }

      // 2. Derive AES key (using a consistent salt for the prototype. In production, 
      // the salt could be returned from a public /api/salt endpoint).
      const mockSalt = new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]); 
      const { key } = await deriveKey(password, mockSalt);
      
      onUnlock({ key, password });
    } catch (err) {
      setError(err.message || 'Failed to unlock vault.');
    } finally {
      setIsUnlocking(false);
    }
  };

  return (
    <div className={styles.container}>
      <form onSubmit={handleUnlock} className={styles.form}>
        <div className={styles.iconContainer}>
          <Lock size={32} className={styles.icon} />
        </div>
        <h1 className={styles.title}>Unlock Vault</h1>
        <p className={styles.subtitle}>Enter your master password to decrypt your files.</p>
        
        <div className={styles.inputGroup}>
          <input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            placeholder="Master Password"
            className={styles.input}
            disabled={isUnlocking}
            autoFocus
          />
        </div>

        {error && <p className={styles.error}>{error}</p>}

        <button 
          type="submit" 
          className={styles.button}
          disabled={isUnlocking || !password}
        >
          {isUnlocking ? 'Unlocking...' : 'Unlock'}
        </button>
      </form>
    </div>
  );
}
