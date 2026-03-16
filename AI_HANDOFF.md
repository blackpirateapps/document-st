# E2EE Document Vault - AI Handoff & Architecture Guide

## Overview
This is a personal, Zero-Knowledge End-to-End Encrypted (E2EE) Document Vault. It is built to ensure that the server, database, and storage providers never have access to unencrypted files or metadata. 

## Core Architecture
- **Frontend Framework:** React built with Vite.
- **Styling:** Vanilla CSS Modules with a strict, Cupertino-inspired (Apple/Things 3) dark mode aesthetic.
- **Backend/API:** Vercel Serverless Functions (`/api`).
- **Database:** Turso DB (LibSQL) for storing encrypted metadata.
- **Object Storage:** Cloudinary for storing encrypted file blobs.
- **Cryptography:** Native Browser Web Crypto API (AES-GCM 256-bit, PBKDF2).

## Security & Encryption Flow (Zero-Knowledge)
1. **Master Password:** The user enters a master password on the frontend.
2. **Authentication:** The frontend sends the raw password as a Bearer token to `/api/files` to authenticate.
3. **Key Derivation:** Locally, the frontend derives a 256-bit AES-GCM key from the master password using PBKDF2 and a static salt (Note: In a more robust production setup, the salt should be unique per user and fetched from an unauthenticated endpoint).
4. **File Encryption (Upload):**
   - The selected `File` object is converted to an `ArrayBuffer` and encrypted locally via `crypto.subtle.encrypt` (AES-GCM).
   - The *encrypted blob* is sent to the Vercel API (`/api/upload`) and stored directly in Cloudinary. Cloudinary only sees random bytes.
5. **Metadata Encryption (Upload):**
   - Sensitive metadata (original filename, file type, file size, folder location, and the IV used to encrypt the blob) is bundled into a JSON object.
   - This JSON object is encrypted locally using the same AES key.
   - The *encrypted metadata string* (Base64) and the Cloudinary URL are sent to Turso DB (`/api/files`). Turso only sees random strings and UUIDs.
6. **Decryption (Download/View):**
   - The frontend fetches all encrypted metadata records from Turso.
   - It decrypts the metadata locally using the key in memory to restore the file list UI.
   - When a user clicks "Download", the app fetches the encrypted blob from Cloudinary, decrypts it locally using the AES key and the specific IV stored in the decrypted metadata, and triggers a local browser download via `URL.createObjectURL`.

## Key Files & Responsibilities
- `src/utils/crypto.js`: Contains all Web Crypto API logic (`deriveKey`, `encryptFile`, `decryptFile`, `encryptMetadata`, `decryptMetadata`). *CRITICAL: Any changes to these functions must maintain backward compatibility or all existing vault data will be permanently lost.*
- `src/components/UploadModal.jsx`: Orchestrates the complex multi-step upload flow (local encryption -> Cloudinary upload -> metadata encryption -> Turso DB save).
- `src/components/FileList.jsx`: Handles the UI for the virtual folders and the download/decryption logic.
- `api/upload.js`: Vercel Serverless function. Uses `formidable` to parse the encrypted file upload and pushes it to Cloudinary.
- `api/files.js`: Vercel Serverless function. Handles saving and retrieving records from Turso DB.

## Environment Variables Required (Vercel)
- `MASTER_PASSWORD`: Used to authenticate API requests.
- `TURSO_DATABASE_URL`: Connection string for LibSQL.
- `TURSO_AUTH_TOKEN`: Auth token for Turso.
- `CLOUDINARY_CLOUD_NAME`: Cloudinary config.
- `CLOUDINARY_API_KEY`: Cloudinary config.
- `CLOUDINARY_API_SECRET`: Cloudinary config.

## Future Development & AI Agent Guidelines
- **Strict Scope:** Maintain the Zero-Knowledge principle. Never send unencrypted data, filenames, or file types to the backend APIs.
- **Aesthetics:** Adhere to the existing Cupertino dark mode theme (`src/index.css`). Do not introduce brutalism, light mode, or complex colorful themes. Keep it minimalist.
- **State Management:** The AES key (`vaultContext`) must only ever reside in React state memory. NEVER persist it to `localStorage`, `sessionStorage`, or cookies. 
- **Dependencies:** Always check package usage before adding new ones. Standardize on `lucide-react` for icons.
