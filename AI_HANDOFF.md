# E2EE Document Vault - AI Handoff & Architecture Guide

## Overview
This is a personal, Zero-Knowledge End-to-End Encrypted (E2EE) Document Vault with two clients:
1. **Web App** (React/Vite) — Fully complete, deployed on Vercel.
2. **Flutter Mobile App** (Android) — Cupertino-themed, shares the same backend and encrypted vault data. Built via GitHub Actions CI.

Both clients implement identical encryption: same AES-GCM 256-bit, same PBKDF2 key derivation, same static salt. A file encrypted by one client can be decrypted by the other.

## Core Architecture
- **Web Frontend:** React built with Vite.
- **Mobile Frontend:** Flutter (Dart) with Cupertino widgets — NO Material design.
- **Styling (Web):** Vanilla CSS Modules with a strict, Cupertino-inspired (Apple HIG) dark mode aesthetic — frosted glass, vibrancy, spring animations, SF Pro typography scale.
- **Styling (Mobile):** Flutter Cupertino widgets with custom dark theme matching web design tokens.
- **Backend/API:** Vercel Serverless Functions (`/api`). Base URL: `https://document-st.vercel.app`
- **Database:** Turso DB (LibSQL) for storing encrypted metadata. Uses `files` and `folders` tables.
- **Object Storage:** Cloudinary for storing encrypted file blobs.
- **Cryptography (Web):** Native Browser Web Crypto API (AES-GCM 256-bit, PBKDF2).
- **Cryptography (Mobile):** PointyCastle library (AES-GCM 256-bit, PBKDF2) — output-compatible with Web Crypto.
- **Icons (Web):** `lucide-react` (standardized — do not add other icon packages).
- **Utilities (Web):** `clsx` for conditional class names.

## Security & Encryption Flow (Zero-Knowledge)
1. **Master Password:** The user enters a master password on the client (web or mobile).
2. **Authentication:** The client sends the raw password as a Bearer token to `/api/files` and `/api/folders` to authenticate.
3. **Key Derivation:** Locally, the client derives a 256-bit AES-GCM key from the master password using PBKDF2 (100,000 iterations, SHA-256) with a **static salt**: `[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]`. **CRITICAL:** Both clients must use this exact salt or derived keys will differ and cross-client decryption will fail.
4. **Password Rotation Recovery (Web + Mobile):** If API auth succeeds but all encrypted records fail decryption, the app treats it as a key mismatch (typically caused by rotating `MASTER_PASSWORD`). It prompts for the *previous* decryption password, decrypts file/folder metadata and file blobs locally, then re-encrypts everything with the current key and updates server records.
5. **File Encryption (Upload):**
   - The selected `File` object is converted to an `ArrayBuffer` and encrypted locally via `crypto.subtle.encrypt` (AES-GCM).
   - The *encrypted blob* is sent to the Vercel API (`/api/upload`) and stored directly in Cloudinary. Cloudinary only sees random bytes.
6. **Metadata & Folder Encryption:**
   - Sensitive metadata (original filename, file type, file size, folder location, starred status, description, custom properties, and the IV used to encrypt the blob) is bundled into a JSON object.
   - This JSON object is encrypted locally using the same AES key.
   - The *encrypted metadata string* (Base64) and the Cloudinary URL are sent to Turso DB (`/api/files`). Folder names and parent IDs are similarly encrypted and sent to `folders` table.
7. **Decryption (Download/View):**
   - The frontend fetches all encrypted metadata records from Turso.
   - It decrypts the metadata locally using the key in memory to restore the file and folder lists.
   - When a user clicks "Download", the app fetches the encrypted blob from Cloudinary, decrypts it locally using the AES key and the specific IV stored in the decrypted metadata, and triggers a local browser download via `URL.createObjectURL`.
    - **PDF Previews:** For PDFs, the blob is decrypted into memory and fed to an iframe via an Object URL, enabling secure, local previewing.

### Recovery/Re-Encryption API Support
- `PUT /api/files` now accepts optional `cloudinary_url` so migration can replace both encrypted metadata and encrypted blob location in one update.
- `PUT /api/folders` is now implemented so folder metadata can be re-encrypted during password-rotation recovery.

## Encrypted Metadata Schema

### File Metadata JSON (encrypted client-side)
```json
{
  "originalName": "document.pdf",
  "originalType": "application/pdf",
  "size": 123456,
  "folderId": "inbox",
  "fileIv": [1, 2, 3, ...],
  "starred": false,
  "description": "",
  "properties": [{ "key": "Client", "value": "Acme Corp" }],
  "dateAdded": "2026-01-15T10:30:00.000Z"
}
```

### Folder Metadata JSON (encrypted client-side)
```json
{
  "name": "My Folder",
  "parentId": null,
  "dateAdded": "2026-01-15T10:30:00.000Z"
}
```

**Backward Compatibility:** When decrypting older records that don't have `starred`, `description`, `properties`, or `parentId`, defaults are applied (`false`, `''`, `[]`, `null` respectively). This ensures existing vault data remains accessible after feature additions.

## Features

### Core Features
- **Upload & Decrypt:** Full E2EE flow — files encrypted locally before upload, decrypted locally on download.
- **Global Drag-and-Drop Upload:** Users can drag files anywhere in the app window to upload. Dropped files are encrypted locally and uploaded to the currently selected folder.
- **Custom Folders:** Users can create custom virtual folders. Folder names are encrypted.
- **Subfolders:** Folders support a `parentId` field for nested hierarchy. The sidebar renders a recursive tree with expand/collapse chevrons and per-folder "add subfolder" buttons.
- **Move & Rename:** Achieved by updating the local metadata JSON, re-encrypting it, and using a `PUT` request to update the database record. The underlying secure blob remains untouched.
- **Copy:** Achieved by duplicating the metadata (appending " Copy"), encrypting it, and creating a new DB record that points to the exact *same* `cloudinary_url` and uses the same `fileIv`.
- **Trash:** Moves the file to a virtual `folderId: 'trash'`.

### Starred Documents
- Each file has a `starred` boolean in its encrypted metadata.
- Star toggle is available: per-row in the file list, in the top bar of the detail view, and is persisted by re-encrypting metadata and PUTting to `/api/files`.
- The "Starred" sidebar folder is a virtual view that filters all starred non-trash files across all folders.

### PDF Preview
- Clicking a PDF row in the file list opens the PdfPreviewModal directly.
- The PDF preview modal decrypts the blob in-memory and renders it via iframe Object URL.
- PDF preview is also accessible from the file detail view via a "Preview PDF" button, and from the context menu.

### File Detail View
- Clicking a non-PDF file row (or selecting "Details" from context menu) opens a detail page.
- **Editable description:** Free-text textarea persisted in encrypted metadata.
- **Custom properties:** Key-value pairs that can be added/removed, stored as `[{ key, value }]` in encrypted metadata.
- **Star toggle:** In the top bar.
- **File metadata display:** Read-only table showing name, type, size, folder, date added, and file ID.
- **Save button:** Re-encrypts all metadata fields and PUTs to `/api/files`. Button is disabled when no changes are detected.
- All changes maintain zero-knowledge — description, properties, and star status never leave the browser unencrypted.

## UI Design System

### Design Language
Full Apple/Cupertino dark mode aesthetic:
- **Vibrancy/Translucency:** Sidebar and modals use `backdrop-filter: blur() saturate()` for frosted glass effects.
- **Typography:** SF Pro font stack with Apple HIG type scale (caption2 through large-title).
- **Colors:** iOS/macOS system colors — `--accent-blue: #0A84FF`, `--danger-red: #FF453A`, `--system-orange: #FF9F0A`, etc.
- **Radius:** Apple-style border radii from 4px to 20px.
- **Animations:** Spring easing curves (`cubic-bezier(0.22, 1, 0.36, 1)`), scale transforms on press.
- **Shadows:** Multi-layer shadows with blue glow effects for interactive elements.

### Design Tokens
All design tokens are defined in `src/index.css` `:root`. Components reference CSS custom properties — never hardcode colors or sizes.

### Responsive Behavior
- On mobile widths, the sidebar becomes a slide-in drawer with a menu button and backdrop dismiss.
- The file list collapses secondary columns (size/date) to keep touch targets large and legible.
- The detail page uses grouped cards and a sticky bottom save bar on mobile.
- Shared modals adapt to bottom-sheet spacing on narrow screens.

### Shared Modal Stylesheet
`UploadModal.module.css` is the **shared modal stylesheet** — imported by ActionModal, FolderModal, and PdfPreviewModal. All modal-related styles (overlay, modal container, header, close button, form controls) live here.

## Key Files & Responsibilities

### Source Components
- `src/App.jsx` — Root component. Manages vault state, folder navigation, file/folder decryption, selected file state for detail view. Hides FAB when detail view is open.
- `src/App.jsx` — Also contains the web vault recovery UI/workflow: detects decryption mismatch after successful auth, prompts for previous password, then re-encrypts all file blobs + metadata and folder metadata.
- `src/components/RecoverySettings.jsx` — Web-only settings panel for per-entry recovery: scans for file rows that fail decryption with current key, lets user provide previous password for one selected entry, decrypts + re-encrypts that item, and writes updated blob+metadata.
- `src/components/MasterPassword.jsx` — Unlock screen with master password input and key derivation.
- `src/components/Sidebar.jsx` — Navigation sidebar with default folders, recursive `FolderTreeItem` for custom folder hierarchy, expand/collapse, subfolder creation.
- `src/components/FileList.jsx` — File table with star toggle, click-to-open (PDF -> preview, others -> detail), context menu (preview, details, rename, move, copy, trash), download.
- `src/components/FileDetailView.jsx` — Detail page for individual files: editable description, custom key-value properties, star toggle, file metadata, save, download, PDF preview button.
- `src/components/UploadModal.jsx` — Multi-step upload flow: local encryption -> Cloudinary upload -> metadata encryption -> Turso DB save. Includes default `starred: false`, `description: ''`, `properties: []`.
- `src/components/ActionModal.jsx` — Rename and move operations. Preserves `starred`, `description`, `properties` fields during re-encryption.
- `src/components/FolderModal.jsx` — Create folders and subfolders. Accepts `parentId` prop for subfolder creation.
- `src/components/PdfPreviewModal.jsx` — Secure in-browser PDF viewer via decrypted Object URL in iframe.

### Crypto (CRITICAL)
- `src/utils/crypto.js` — Contains all Web Crypto API logic (`deriveKey`, `encryptFile`, `decryptFile`, `encryptMetadata`, `decryptMetadata`, `generateUUID`). **Any changes to these functions must maintain backward compatibility or all existing vault data will be permanently lost.**

### Stylesheets
- `src/index.css` — Global design tokens and reset.
- `src/App.module.css` — App layout and FAB.
- `src/components/Sidebar.module.css` — Sidebar, folder tree, chevrons.
- `src/components/FileList.module.css` — File table, star column, dropdown menu.
- `src/components/FileDetailView.module.css` — Detail view layout, description, properties, metadata table.
- `src/components/UploadModal.module.css` — **Shared modal styles** (overlay, modal, header, form controls, PDF preview modal).
- `src/components/MasterPassword.module.css` — Unlock screen with frosted glass.

### Server API (Vercel Serverless)
- `api/cloudinary-config.js` — Returns Cloudinary upload settings (`cloudName`, unsigned `uploadPreset`, `resourceType`) after Bearer auth for direct client uploads.
- `api/upload.js` — Parses encrypted file upload via `formidable` and pushes to Cloudinary.
- `api/files.js` — Turso DB endpoints for file records (GET, POST, PUT). `PUT` supports optional `cloudinary_url` updates for migration.
- `api/folders.js` — Turso DB endpoints for folder records (GET, POST, PUT).

## Environment Variables Required (Vercel)
- `MASTER_PASSWORD`: Used to authenticate API requests.
- `TURSO_DATABASE_URL`: Connection string for LibSQL.
- `TURSO_AUTH_TOKEN`: Auth token for Turso.
- `CLOUDINARY_CLOUD_NAME`: Cloudinary config.
- `CLOUDINARY_API_KEY`: Cloudinary config.
- `CLOUDINARY_API_SECRET`: Cloudinary config.

## Navigation Model
The app has no client-side router. Navigation is state-driven:
- `currentFolder` state determines which folder's files to display.
- `selectedFile` state determines whether the file detail view is shown (non-null) or the file list (null).
- Selecting a sidebar folder clears `selectedFile` back to null.
- The FAB (upload button) is hidden when the detail view is open.

## Future Development & AI Agent Guidelines
- **Strict Scope:** Maintain the Zero-Knowledge principle. Never send unencrypted data, filenames, or file types to the backend APIs.
- **Aesthetics:** Adhere to the existing Cupertino dark mode theme (`src/index.css`). Do not introduce brutalism, light mode, or complex colorful themes. Keep it minimalist.
- **State Management:** The AES key (`vaultContext`) must only ever reside in React state memory. NEVER persist it to `localStorage`, `sessionStorage`, or cookies.
- **Dependencies:** Always check package usage before adding new ones. Standardize on `lucide-react` for icons.
- **Metadata Evolution:** When adding new fields to the encrypted metadata JSON, always provide fallback defaults during decryption to maintain backward compatibility with existing records.
- **Shared Modal Styles:** All modals import from `UploadModal.module.css`. Add new modal styles there, not in separate files.
- **Password Rotation Migration:** If auth password changes and decryption fails, use the built-in recovery flow to migrate all metadata + blobs to the new key instead of treating vault data as lost.

---

## Flutter Mobile App (Android)

### Status
The mobile app code is **written but not yet tested/built**. It must be built in GitHub Actions CI because the developer's machine cannot build Android apps locally. The GitHub Actions workflow (`.github/workflows/build-apk.yml`) triggers on pushes to `main` that modify files under `mobile/`.

### Design Constraints
- **Cupertino ONLY:** Uses `CupertinoApp`, `CupertinoPageScaffold`, `CupertinoNavigationBar`, `CupertinoTextField`, `CupertinoActionSheet`, etc. NO Material widgets (`MaterialApp`, `Scaffold`, `AppBar`, `TextField`, etc.) are allowed. The goal is to match the web app's Apple HIG dark aesthetic on Android.
- **Zero-Knowledge:** All encryption/decryption happens on-device. Never send unencrypted data to the backend.
- **Crypto Compatibility:** The Flutter `CryptoService` must produce output byte-for-byte compatible with the web `crypto.js`. Same AES-GCM 256-bit, same PBKDF2 (100k iterations, SHA-256), same static salt `[1..16]`, same 12-byte IV, same 128-bit auth tag.

### Tech Stack
- **Framework:** Flutter 3.24+ (Dart)
- **State Management:** Provider (`ChangeNotifierProvider` + `VaultProvider`)
- **HTTP:** `http` package
- **Crypto:** `pointycastle` (AES-GCM, PBKDF2)
- **PDF Viewer:** `flutter_pdfview`
- **File Picker:** `file_picker`
- **UUIDs:** `uuid`
- **Path Utilities:** `path`
- **Offline Cache:** `shared_preferences`

### Project Structure
```
mobile/
├── pubspec.yaml                    # Dependencies & app config
├── analysis_options.yaml           # Dart lint rules
├── test/
│   └── widget_test.dart            # Placeholder test
├── android/
│   ├── build.gradle                # Root Gradle config (AGP 8.6.1, Kotlin 1.9.24)
│   ├── settings.gradle             # Flutter Gradle plugin loader
│   ├── gradle.properties           # Gradle JVM args
│   ├── gradle/wrapper/
│   │   └── gradle-wrapper.properties  # Gradle 8.9
│   └── app/
│       ├── build.gradle            # App-level (compileSdk 35, targetSdk 35, minSdk 24, NDK 26.1.10909125)
│       └── src/main/
│           ├── AndroidManifest.xml  # INTERNET permission, network security config
│           ├── kotlin/.../MainActivity.kt  # FlutterActivity entry point
│           └── res/                 # Launch icons, styles, network config
└── lib/
    ├── main.dart                   # App entry: CupertinoApp + Provider + auth gating
    ├── theme/
    │   └── app_theme.dart          # Dark Cupertino theme tokens matching web CSS vars
    ├── models/
    │   ├── vault_file.dart         # VaultFile data model (fromDecryptedMeta, toMetadataJson)
    │   └── vault_folder.dart       # VaultFolder data model
    ├── services/
    │   ├── crypto_service.dart     # AES-GCM + PBKDF2 (PointyCastle). CRITICAL FILE.
    │   ├── api_service.dart        # HTTP client for all Vercel API endpoints
    │   └── vault_provider.dart     # ChangeNotifier: unlock, fetch, decrypt, CRUD, star, move, offline cache, upload queue, sidebar state, lock
    └── screens/
        ├── unlock_screen.dart      # Master password input
        ├── home_screen.dart        # Main layout: responsive sidebar/drawer + content area + upload progress
        ├── file_list_screen.dart   # File list with star, multi-file upload, colored icons, actions, PDF click-to-preview
        ├── file_detail_screen.dart # Redesigned detail view: hero card, quick actions, frosted-glass sections, sticky save
        ├── pdf_preview_screen.dart # Decrypt-and-view PDF via flutter_pdfview (nightMode fixed)
        └── settings_screen.dart    # Settings: batch upload, sync, clear cache, lock vault, about
```

### Key Mobile Files

#### `lib/services/crypto_service.dart` (CRITICAL)
Mirrors `src/utils/crypto.js` exactly:
- `deriveKeyBytes(password)` — PBKDF2-SHA256, 100k iterations, static salt `[1..16]`, produces 32-byte key.
- `encryptFileBytes(plain, key)` — AES-GCM encrypt with random 12-byte IV, 128-bit auth tag. Returns `{encryptedBytes, iv}`.
- `decryptFileBytes(encrypted, key, ivList)` — AES-GCM decrypt.
- `encryptMetadata(metadata, key)` — JSON encode -> encrypt -> base64. Returns `{data, iv}`.
- `decryptMetadata(encryptedBase64, ivList, key)` — base64 decode -> decrypt -> JSON parse.

**Any changes to this file must maintain byte-level compatibility with the web app's crypto.js, or cross-client decryption will break.**

#### `lib/services/api_service.dart`
HTTP client targeting `https://document-st.vercel.app`:
- `authenticate(password)` — `GET /api/files` with Bearer token.
- `fetchFiles(password)` — `GET /api/files` returns all encrypted file records.
- `fetchFolders(password)` — `GET /api/folders` returns all encrypted folder records.
- `createFile(...)` — `POST /api/files` with encrypted metadata + Cloudinary URL.
- `updateFile(...)` — `PUT /api/files` with updated encrypted metadata (and optional migrated `cloudinary_url`).
- `createFolder(...)` — `POST /api/folders`.
- `updateFolder(...)` — `PUT /api/folders` with updated encrypted folder metadata.
- `fetchCloudinaryConfig()` — `GET /api/cloudinary-config` for direct upload parameters.
- `uploadEncryptedFile(...)` — uploads encrypted bytes directly to Cloudinary unsigned upload endpoint using preset `vercel`.
- `fetchRawFile(url)` — `GET` the encrypted blob from Cloudinary.

#### `lib/services/vault_provider.dart`
ChangeNotifier that manages all app state:
- Holds `_keyBytes`, `_password`, `_files`, `_folders`, `_currentFolderId`, `_selectedFile`, `_sidebarOpen`, `_uploadQueue`.
- `unlock(password)` — authenticates and derives key; if server auth passes but decryption fails for all rows, returns a recovery-required state instead of unlocking.
- `recoverVaultWithPreviousPassword(previousPassword)` — decrypts all server rows with old key, re-encrypts with current key, uploads new encrypted blobs, updates file and folder records, and refreshes local cache.
- CRUD operations: `uploadFile`, `uploadFiles` (batch), `renameFile`, `moveFile`, `copyFile`, `trashFile`, `toggleStar`, `createFolder`, `deleteFolder`.
- All mutations re-encrypt metadata and PUT/POST to the API, then call `_saveToCache()` to persist locally.
- **Offline caching:** Uses `shared_preferences` with keys `vault_cached_files`, `vault_cached_folders`, `vault_cache_ts`. Decrypted vault data is cached as JSON after every mutation.
- **Upload queue:** `UploadTask` class tracks `id`, `fileName`, `progress`, `status` (encrypting/uploading/saving/done/error), `error`. `_processUpload()` runs asynchronously and non-blocking. Completed tasks auto-dismiss after 3 seconds.
- **Sidebar state:** `sidebarOpen`, `toggleSidebar()`, `closeSidebar()` — controls the mobile drawer.
- **Lock:** `lock()` clears all sensitive data (key, password, files, folders, cache) from memory.

#### `lib/screens/home_screen.dart`
Main layout with responsive behavior:
- **Wide screens (>=600px):** Permanent left sidebar.
- **Phone screens (<600px):** Overlay drawer with dark backdrop, opened via hamburger menu button in `file_list_screen.dart`.
- Sidebar contents: folder tree (recursive with expand/collapse), default folders (All Files, Starred, Trash), file count badges per folder, create folder dialog, settings gear icon.
- Upload progress section in sidebar: shows active `UploadTask` items with status icons, file names, custom progress bars. Completed tasks auto-dismiss after 3 seconds; error tasks can be manually dismissed.
- Right content area: switches between `FileListScreen`, `FileDetailScreen`, `SettingsScreen` based on state.

### GitHub Actions CI
**File:** `.github/workflows/build-apk.yml`
- **Triggers:** Push to `main` (paths: `mobile/**`), PRs to `main`, manual `workflow_dispatch`.
- **Steps:** Checkout -> Java 17 (Temurin) -> Flutter 3.24 (stable, cached) -> `flutter pub get` -> `flutter analyze` -> `flutter test` -> `flutter build apk --release` -> Upload artifact.
- **Artifact:** `document-vault-release-apk` (APK retained for 30 days).
- **Note:** `flutter analyze` and `flutter test` have `continue-on-error: true` to not block APK builds during initial development.

### Known Issues & Future Work
- **Web per-entry recovery hardening (Mar 2026):** Recovery now handles legacy `fileIv` formats (JSON string vs array) and surfaces targeted errors for metadata-decrypt vs blob-decrypt failures instead of generic WebCrypto operation errors.
- **Web granular recovery added (Mar 2026):** Settings now includes a per-entry recovery tool for failed file decryptions when full-vault migration is not available or previously failed.
- **Direct Cloudinary uploads implemented (Mar 2026):** Web and Flutter now upload encrypted blobs directly to Cloudinary using unsigned preset `vercel` (via `/api/cloudinary-config`) to avoid Vercel function upload timeouts.
- **Mobile vault visibility bug fixed (Mar 2026):** Adjusted recovery-trigger detection so empty decrypt results caused by schema/data edge cases no longer hide valid uploads/trash views.
- **Password rotation recovery implemented (Mar 2026):** Both web and Flutter now detect all-row decryption failure after successful auth and prompt for the previous decryption password to migrate data.
- **Migration write-paths expanded (Mar 2026):** Added `PUT /api/folders` and optional `cloudinary_url` updates in `PUT /api/files` to support full blob + metadata re-encryption.
- **Release build breakage fixed (Mar 2026):** `CupertinoIcons.key_fill` is not available in Flutter 3.24, so `mobile/lib/screens/file_detail_screen.dart` now uses `CupertinoIcons.key` in the Encryption section to keep `assembleRelease` compiling.
- **CI Android toolchain finding resolved:** Plugins now require NDK `26.1.10909125`; app config pins this NDK version explicitly in `android/app/build.gradle`.
- **CI resource linking finding resolved:** Missing launcher icon resource (`@mipmap/ic_launcher`) was added via XML drawable resources under `android/app/src/main/res/`.
- **PDF preview** depends on writing a temp file to device storage; may need storage permissions on some Android versions. PDF dark mode bug was fixed (`nightMode: false` with white background).
- **IV generation** uses `Random.secure()` from `dart:math` — cryptographically secure on Android.
- **The `_generateIV` method** does NOT use PointyCastle's `FortunaRandom` — it uses Dart's `Random.secure()` which is backed by the OS CSPRNG, which is simpler and equally secure.
- **Offline mode implemented** — vault data is cached locally via `shared_preferences` after first unlock. App works without network on subsequent opens; syncs from server in background when connectivity is available.
- **Non-blocking uploads** — upload progress is displayed in the sidebar with per-task status indicators. The rest of the app remains usable during uploads.
- **Settings page** — batch file upload, sync vault, clear cache, lock vault, and about section with encryption info.
- **File detail redesign** — hero card with file type icon (color-coded by MIME type), quick action buttons, frosted-glass sections, sticky save bar.
- **No biometric lock** — could be added as a future enhancement.
