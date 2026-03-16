import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/vault_file.dart';
import '../models/vault_folder.dart';
import 'api_service.dart';
import 'crypto_service.dart';

/// Central state manager for the vault.
class VaultProvider extends ChangeNotifier {
  ApiService? _api;
  Uint8List? _keyBytes;
  String? _authPassword;

  bool _isLoading = false;
  String? _error;
  String _currentFolder = 'inbox';
  VaultFile? _selectedFile;

  List<VaultFile> _files = [];
  List<VaultFolder> _folders = [];

  // Getters
  bool get isUnlocked => _keyBytes != null;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get currentFolder => _currentFolder;
  VaultFile? get selectedFile => _selectedFile;
  List<VaultFile> get files => _files;
  List<VaultFolder> get folders => _folders;
  Uint8List? get keyBytes => _keyBytes;
  String? get authPassword => _authPassword;

  /// Files filtered to current folder view.
  List<VaultFile> get currentFiles {
    if (_currentFolder == 'starred') {
      return _files.where((f) => f.starred && f.folderId != 'trash').toList();
    }
    return _files.where((f) => f.folderId == _currentFolder).toList();
  }

  /// Root-level custom folders (no parent).
  List<VaultFolder> get rootFolders => _folders
      .where((f) => f.parentId == null || f.parentId == 'null')
      .toList();

  /// Children of a folder.
  List<VaultFolder> childrenOf(String parentId) =>
      _folders.where((f) => f.parentId == parentId).toList();

  /// Unlock vault with master password.
  Future<bool> unlock(String password) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      _keyBytes = CryptoService.deriveKeyBytes(password);
      _authPassword = password;
      _api = ApiService(authPassword: password);

      // Test auth by fetching files
      await _fetchData();
      return true;
    } catch (e) {
      _keyBytes = null;
      _authPassword = null;
      _api = null;
      _error = 'Failed to unlock vault. Check your password.';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> _fetchData() async {
    _isLoading = true;
    notifyListeners();

    try {
      // Fetch and decrypt files
      final rawFiles = await _api!.fetchFiles();
      final decrypted = <VaultFile>[];
      for (final row in rawFiles) {
        try {
          final ivList =
              (jsonDecode(row['metadata_iv'] as String) as List<dynamic>)
                  .map<int>((e) => (e as num).toInt())
                  .toList();
          final meta = CryptoService.decryptMetadata(
            row['encrypted_metadata'] as String,
            ivList,
            _keyBytes!,
          );
          decrypted.add(
            VaultFile.fromDecryptedMeta(
              id: row['id'] as String,
              cloudinaryUrl: row['cloudinary_url'] as String,
              meta: meta,
              fallbackDate:
                  row['created_at']?.toString() ??
                  DateTime.now().toIso8601String(),
            ),
          );
        } catch (e) {
          debugPrint('Failed to decrypt file ${row['id']}: $e');
        }
      }
      _files = decrypted;

      // Fetch and decrypt folders
      final rawFolders = await _api!.fetchFolders();
      final decryptedFolders = <VaultFolder>[];
      for (final row in rawFolders) {
        try {
          final ivList =
              (jsonDecode(row['metadata_iv'] as String) as List<dynamic>)
                  .map<int>((e) => (e as num).toInt())
                  .toList();
          final meta = CryptoService.decryptMetadata(
            row['encrypted_metadata'] as String,
            ivList,
            _keyBytes!,
          );
          decryptedFolders.add(
            VaultFolder.fromDecryptedMeta(
              id: row['id'] as String,
              meta: meta,
              fallbackDate:
                  row['created_at']?.toString() ??
                  DateTime.now().toIso8601String(),
            ),
          );
        } catch (e) {
          debugPrint('Failed to decrypt folder ${row['id']}: $e');
        }
      }
      _folders = decryptedFolders;

      _error = null;
    } catch (e) {
      _error = 'Failed to load vault data: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Refresh data from server.
  Future<void> refresh() => _fetchData();

  void setCurrentFolder(String folderId) {
    _currentFolder = folderId;
    _selectedFile = null;
    notifyListeners();
  }

  void selectFile(VaultFile? file) {
    _selectedFile = file;
    notifyListeners();
  }

  void clearSelection() {
    _selectedFile = null;
    notifyListeners();
  }

  /// Toggle star on a file.
  Future<void> toggleStar(VaultFile file) async {
    final updated = file.copyWith(starred: !file.starred);
    await _updateFileMetadata(updated);
  }

  /// Save file detail edits (description, properties, starred).
  Future<void> saveFileDetails(
    VaultFile file, {
    required String description,
    required bool starred,
    required List<Map<String, String>> properties,
  }) async {
    final cleaned = properties
        .where(
          (p) =>
              (p['key']?.trim().isNotEmpty ?? false) ||
              (p['value']?.trim().isNotEmpty ?? false),
        )
        .toList();
    final updated = file.copyWith(
      description: description,
      starred: starred,
      properties: cleaned,
    );
    await _updateFileMetadata(updated);
  }

  /// Move file to a folder.
  Future<void> moveFile(VaultFile file, String targetFolderId) async {
    final updated = file.copyWith(folderId: targetFolderId);
    await _updateFileMetadata(updated);
  }

  /// Rename a file.
  Future<void> renameFile(VaultFile file, String newName) async {
    final updated = file.copyWith(originalName: newName);
    await _updateFileMetadata(updated);
  }

  /// Trash a file.
  Future<void> trashFile(VaultFile file) async {
    final updated = file.copyWith(folderId: 'trash');
    await _updateFileMetadata(updated);
  }

  /// Copy a file.
  Future<void> copyFile(VaultFile file) async {
    final newId = const Uuid().v4();
    final newMeta = {
      'originalName': file.originalName.replaceAllMapped(
        RegExp(r'(\.[\w\d_-]+)$'),
        (m) => ' Copy${m.group(0)}',
      ),
      'originalType': file.originalType,
      'size': file.size,
      'folderId': file.folderId,
      'fileIv': file.fileIv,
      'starred': false,
      'description': file.description,
      'properties': file.properties
          .map((p) => {'key': p['key'], 'value': p['value']})
          .toList(),
      'dateAdded': DateTime.now().toIso8601String(),
    };

    final encrypted = CryptoService.encryptMetadata(newMeta, _keyBytes!);
    await _api!.createFile(
      id: newId,
      encryptedMetadata: encrypted['data'] as String,
      metadataIv: jsonEncode(encrypted['iv']),
      cloudinaryUrl: file.cloudinaryUrl,
    );

    _files.add(
      VaultFile.fromDecryptedMeta(
        id: newId,
        cloudinaryUrl: file.cloudinaryUrl,
        meta: newMeta,
        fallbackDate: DateTime.now().toIso8601String(),
      ),
    );
    notifyListeners();
  }

  /// Upload a new file.
  Future<void> uploadFile(
    Uint8List fileBytes,
    String fileName,
    String mimeType,
  ) async {
    // 1. Encrypt the file
    final result = CryptoService.encryptFileBytes(fileBytes, _keyBytes!);
    final encryptedBytes = result['encryptedBytes'] as Uint8List;
    final iv = result['iv'] as Uint8List;

    // 2. Upload encrypted blob
    final cloudinaryUrl = await _api!.uploadEncryptedBlob(encryptedBytes);

    // 3. Create metadata
    final newId = const Uuid().v4();
    final meta = {
      'originalName': fileName,
      'originalType': mimeType,
      'size': fileBytes.length,
      'folderId': _currentFolder == 'starred' || _currentFolder == 'trash'
          ? 'inbox'
          : _currentFolder,
      'fileIv': iv.toList(),
      'starred': false,
      'description': '',
      'properties': <Map<String, String>>[],
      'dateAdded': DateTime.now().toIso8601String(),
    };

    // 4. Encrypt metadata
    final encryptedMeta = CryptoService.encryptMetadata(meta, _keyBytes!);

    // 5. Save to DB
    await _api!.createFile(
      id: newId,
      encryptedMetadata: encryptedMeta['data'] as String,
      metadataIv: jsonEncode(encryptedMeta['iv']),
      cloudinaryUrl: cloudinaryUrl,
    );

    // 6. Update local state
    _files.insert(
      0,
      VaultFile.fromDecryptedMeta(
        id: newId,
        cloudinaryUrl: cloudinaryUrl,
        meta: meta,
        fallbackDate: DateTime.now().toIso8601String(),
      ),
    );
    notifyListeners();
  }

  /// Create a new folder.
  Future<void> createFolder(String name, {String? parentId}) async {
    final newId = const Uuid().v4();
    final meta = {
      'name': name,
      'parentId': parentId,
      'dateAdded': DateTime.now().toIso8601String(),
    };
    final encrypted = CryptoService.encryptMetadata(meta, _keyBytes!);
    await _api!.createFolder(
      id: newId,
      encryptedMetadata: encrypted['data'] as String,
      metadataIv: jsonEncode(encrypted['iv']),
    );
    _folders.add(
      VaultFolder.fromDecryptedMeta(
        id: newId,
        meta: meta,
        fallbackDate: DateTime.now().toIso8601String(),
      ),
    );
    notifyListeners();
  }

  /// Decrypt file bytes for download/preview.
  Future<Uint8List> decryptFileForView(VaultFile file) async {
    final encrypted = await _api!.fetchRawBytes(file.cloudinaryUrl);
    return CryptoService.decryptFileBytes(encrypted, _keyBytes!, file.fileIv);
  }

  /// Internal: update file metadata on server and in local state.
  Future<void> _updateFileMetadata(VaultFile updated) async {
    final meta = updated.toMetadataJson();
    final encrypted = CryptoService.encryptMetadata(meta, _keyBytes!);
    await _api!.updateFile(
      id: updated.id,
      encryptedMetadata: encrypted['data'] as String,
      metadataIv: jsonEncode(encrypted['iv']),
    );

    final idx = _files.indexWhere((f) => f.id == updated.id);
    if (idx >= 0) {
      _files[idx] = updated;
    }
    if (_selectedFile?.id == updated.id) {
      _selectedFile = updated;
    }
    notifyListeners();
  }

  /// Resolve folder name from ID.
  String folderName(String folderId) {
    const builtins = {
      'inbox': 'Inbox',
      'starred': 'Starred',
      'documents': 'Documents',
      'photos': 'Photos',
      'taxes': 'Taxes',
      'trash': 'Trash',
    };
    if (builtins.containsKey(folderId)) return builtins[folderId]!;
    final f = _folders.where((f) => f.id == folderId).firstOrNull;
    return f?.name ?? folderId;
  }
}
