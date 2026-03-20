import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/vault_file.dart';
import '../models/vault_folder.dart';
import 'api_service.dart';
import 'crypto_service.dart';

/// Represents an in-progress upload.
class UploadTask {
  final String id;
  final String fileName;
  double progress; // 0.0 to 1.0
  String status; // 'encrypting', 'uploading', 'saving', 'done', 'error'
  String? error;

  UploadTask({
    required this.id,
    required this.fileName,
    this.progress = 0.0,
    this.status = 'encrypting',
    this.error,
  });
}

enum UnlockStatus { success, invalidPassword, needsRecovery, failure }

class UnlockResult {
  final UnlockStatus status;
  final String? message;

  const UnlockResult(this.status, {this.message});
}

class RecoveryResult {
  final bool success;
  final String message;

  const RecoveryResult({required this.success, required this.message});
}

/// Central state manager for the vault.
class VaultProvider extends ChangeNotifier {
  ApiService? _api;
  Uint8List? _keyBytes;
  String? _authPassword;

  bool _isLoading = false;
  String? _error;
  String _currentFolder = 'all';
  VaultFile? _selectedFile;
  bool _sidebarOpen = false;

  List<VaultFile> _files = [];
  List<VaultFolder> _folders = [];
  List<UploadTask> _uploadQueue = [];
  bool _isCreatingFolder = false;
  final Set<String> _cachedFileIds = {};
  bool _needsRecovery = false;
  List<Map<String, dynamic>> _recoveryFileRows = [];
  List<Map<String, dynamic>> _recoveryFolderRows = [];

  // Getters
  bool get isUnlocked => _keyBytes != null && !_needsRecovery;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get currentFolder => _currentFolder;
  VaultFile? get selectedFile => _selectedFile;
  List<VaultFile> get files => _files;
  List<VaultFolder> get folders => _folders;
  Uint8List? get keyBytes => _keyBytes;
  String? get authPassword => _authPassword;
  bool get sidebarOpen => _sidebarOpen;
  List<UploadTask> get uploadQueue => List.unmodifiable(_uploadQueue);
  bool get needsRecovery => _needsRecovery;
  int get recoveryItemsCount =>
      _recoveryFileRows.length + _recoveryFolderRows.length;
  bool get hasActiveUploads =>
      _uploadQueue.any((t) => t.status != 'done' && t.status != 'error');
  bool get isCreatingFolder => _isCreatingFolder;

  /// Files filtered to current folder view.
  List<VaultFile> get currentFiles {
    if (_currentFolder == 'all') {
      return _files.where((f) => f.folderId != 'trash').toList();
    }
    if (_currentFolder == 'starred') {
      return _files.where((f) => f.starred && f.folderId != 'trash').toList();
    }
    return _files.where((f) => f.folderId == _currentFolder).toList();
  }

  List<VaultFolder> get currentSubfolders {
    if (_currentFolder == 'all' ||
        _currentFolder == 'starred' ||
        _currentFolder == 'trash') {
      return const [];
    }
    return _folders.where((f) => f.parentId == _currentFolder).toList();
  }

  /// Root-level custom folders (no parent).
  List<VaultFolder> get rootFolders => _folders
      .where((f) => f.parentId == null || f.parentId == 'null')
      .toList();

  /// Children of a folder.
  List<VaultFolder> childrenOf(String parentId) =>
      _folders.where((f) => f.parentId == parentId).toList();

  void toggleSidebar() {
    _sidebarOpen = !_sidebarOpen;
    notifyListeners();
  }

  void closeSidebar() {
    if (_sidebarOpen) {
      _sidebarOpen = false;
      notifyListeners();
    }
  }

  /// Unlock vault with master password.
  Future<UnlockResult> unlock(String password) async {
    try {
      _isLoading = true;
      _error = null;
      _needsRecovery = false;
      _recoveryFileRows = [];
      _recoveryFolderRows = [];
      notifyListeners();

      _keyBytes = CryptoService.deriveKeyBytes(password);
      _authPassword = password;
      _api = ApiService(authPassword: password);

      try {
        await _fetchData(rethrowOnError: true);
      } catch (e) {
        if (e.toString().contains('401')) {
          _keyBytes = null;
          _authPassword = null;
          _api = null;
          _isLoading = false;
          notifyListeners();
          return const UnlockResult(
            UnlockStatus.invalidPassword,
            message: 'Invalid master password.',
          );
        }

        final cached = await _loadFromCache();
        if (cached) {
          _isLoading = false;
          _error = 'Using offline cache. Unable to reach server.';
          notifyListeners();
          _fetchData(silent: true);
          return const UnlockResult(UnlockStatus.success);
        }
        rethrow;
      }

      if (_needsRecovery) {
        return const UnlockResult(
          UnlockStatus.needsRecovery,
          message:
              'Your vault was encrypted with a different password. Enter the previous decryption password to migrate data.',
        );
      }

      return const UnlockResult(UnlockStatus.success);
    } catch (e) {
      _keyBytes = null;
      _authPassword = null;
      _api = null;
      _error = 'Failed to unlock vault. Check your password.';
      _isLoading = false;
      notifyListeners();
      return const UnlockResult(UnlockStatus.failure);
    }
  }

  // ── Offline Cache ──

  static const String _cacheKeyFiles = 'vault_cached_files';
  static const String _cacheKeyFolders = 'vault_cached_folders';
  static const String _cacheKeyTimestamp = 'vault_cache_ts';
  static const String _cacheKeyBlobIds = 'vault_cached_blob_ids';

  Future<bool> _loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final filesJson = prefs.getString(_cacheKeyFiles);
      final foldersJson = prefs.getString(_cacheKeyFolders);
      if (filesJson == null || foldersJson == null) return false;

      final filesList = jsonDecode(filesJson) as List<dynamic>;
      _files = filesList.map<VaultFile>((raw) {
        final m = raw as Map<String, dynamic>;
        return VaultFile.fromDecryptedMeta(
          id: m['id'] as String,
          cloudinaryUrl: m['cloudinaryUrl'] as String,
          meta: m['meta'] as Map<String, dynamic>,
          fallbackDate: m['fallbackDate'] as String,
        );
      }).toList();

      final foldersList = jsonDecode(foldersJson) as List<dynamic>;
      _folders = foldersList.map<VaultFolder>((raw) {
        final m = raw as Map<String, dynamic>;
        return VaultFolder.fromDecryptedMeta(
          id: m['id'] as String,
          meta: m['meta'] as Map<String, dynamic>,
          fallbackDate: m['fallbackDate'] as String,
        );
      }).toList();

      final blobIdList = prefs.getStringList(_cacheKeyBlobIds) ?? const [];
      _cachedFileIds
        ..clear()
        ..addAll(blobIdList);

      return _files.isNotEmpty || _folders.isNotEmpty;
    } catch (e) {
      debugPrint('Cache load failed: $e');
      return false;
    }
  }

  Future<void> _saveToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final filesData = _files
          .map(
            (f) => {
              'id': f.id,
              'cloudinaryUrl': f.cloudinaryUrl,
              'meta': f.toMetadataJson(),
              'fallbackDate': f.dateAdded,
            },
          )
          .toList();
      await prefs.setString(_cacheKeyFiles, jsonEncode(filesData));

      final foldersData = _folders
          .map(
            (f) => {
              'id': f.id,
              'meta': f.toMetadataJson(),
              'fallbackDate': f.dateAdded,
            },
          )
          .toList();
      await prefs.setString(_cacheKeyFolders, jsonEncode(foldersData));
      await prefs.setString(
        _cacheKeyTimestamp,
        DateTime.now().toIso8601String(),
      );

      await prefs.setStringList(_cacheKeyBlobIds, _cachedFileIds.toList());
    } catch (e) {
      debugPrint('Cache save failed: $e');
    }
  }

  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKeyFiles);
    await prefs.remove(_cacheKeyFolders);
    await prefs.remove(_cacheKeyTimestamp);
    await prefs.remove(_cacheKeyBlobIds);
    await _purgeEncryptedBlobFiles();
    _cachedFileIds.clear();
  }

  // ── Data Fetching ──

  Future<void> _fetchData({
    bool silent = false,
    bool rethrowOnError = false,
  }) async {
    if (!silent) {
      _isLoading = true;
      notifyListeners();
    }

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

      // Fetch and decrypt folders
      final rawFolders = await _api!.fetchFolders();
      final decryptedFolders = <VaultFolder>[];
      var failedFiles = rawFiles.isNotEmpty;
      var failedFolders = rawFolders.isNotEmpty;
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
          failedFolders = false;
        } catch (e) {
          debugPrint('Failed to decrypt folder ${row['id']}: $e');
        }
      }

      if (decrypted.isNotEmpty) {
        failedFiles = false;
      }

      final totalRows = rawFiles.length + rawFolders.length;
      final totalDecrypted = decrypted.length + decryptedFolders.length;
      if (totalRows > 0 &&
          totalDecrypted == 0 &&
          (failedFiles || failedFolders)) {
        _needsRecovery = true;
        _recoveryFileRows = rawFiles;
        _recoveryFolderRows = rawFolders;
        _files = [];
        _folders = [];
        _error =
            'Vault data is encrypted with a different password. Migration required.';
        return;
      }

      _needsRecovery = false;
      _recoveryFileRows = [];
      _recoveryFolderRows = [];
      _files = decrypted;
      _folders = decryptedFolders;

      _error = null;

      // Save to cache for offline use
      await _saveToCache();
    } catch (e) {
      if (!silent) {
        _error = 'Failed to load vault data: $e';
      }
      if (rethrowOnError) {
        rethrow;
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Refresh data from server.
  Future<void> refresh() => _fetchData();

  Future<RecoveryResult> recoverVaultWithPreviousPassword(
    String previousPassword,
  ) async {
    if (_api == null || _keyBytes == null || !_needsRecovery) {
      return const RecoveryResult(
        success: false,
        message: 'No recovery operation is currently required.',
      );
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final oldKeyBytes = CryptoService.deriveKeyBytes(previousPassword);

      final fileRows = List<Map<String, dynamic>>.from(_recoveryFileRows);
      final folderRows = List<Map<String, dynamic>>.from(_recoveryFolderRows);

      final decryptedFileMeta = <Map<String, dynamic>>[];
      for (final row in fileRows) {
        try {
          final ivList = _parseIvList(row['metadata_iv']);
          final meta = CryptoService.decryptMetadata(
            row['encrypted_metadata'] as String,
            ivList,
            oldKeyBytes,
          );
          decryptedFileMeta.add(_normalizeFileMeta(meta, row['created_at']));
        } catch (_) {
          return const RecoveryResult(
            success: false,
            message: 'Previous decryption password is incorrect.',
          );
        }
      }

      final decryptedFolderMeta = <Map<String, dynamic>>[];
      for (final row in folderRows) {
        try {
          final ivList = _parseIvList(row['metadata_iv']);
          final meta = CryptoService.decryptMetadata(
            row['encrypted_metadata'] as String,
            ivList,
            oldKeyBytes,
          );
          decryptedFolderMeta.add(
            _normalizeFolderMeta(meta, row['created_at']),
          );
        } catch (_) {
          return const RecoveryResult(
            success: false,
            message: 'Previous decryption password is incorrect.',
          );
        }
      }

      final migratedFiles = <VaultFile>[];
      for (var i = 0; i < fileRows.length; i++) {
        final row = fileRows[i];
        final meta = decryptedFileMeta[i];

        final encryptedBlob = await _api!.fetchRawBytes(
          row['cloudinary_url'] as String,
        );
        final plainBytes = CryptoService.decryptFileBytes(
          encryptedBlob,
          oldKeyBytes,
          (meta['fileIv'] as List<dynamic>)
              .map<int>((e) => (e as num).toInt())
              .toList(),
        );

        final reencryptedBlob = CryptoService.encryptFileBytes(
          plainBytes,
          _keyBytes!,
        );
        final newEncryptedBytes =
            reencryptedBlob['encryptedBytes'] as Uint8List;
        final newFileIv = reencryptedBlob['iv'] as Uint8List;

        meta['fileIv'] = newFileIv.toList();
        final encryptedMeta = CryptoService.encryptMetadata(meta, _keyBytes!);
        final newCloudinaryUrl = await _api!.uploadEncryptedBlob(
          newEncryptedBytes,
        );

        await _api!.updateFile(
          id: row['id'] as String,
          encryptedMetadata: encryptedMeta['data'] as String,
          metadataIv: jsonEncode(encryptedMeta['iv']),
          cloudinaryUrl: newCloudinaryUrl,
        );

        migratedFiles.add(
          VaultFile.fromDecryptedMeta(
            id: row['id'] as String,
            cloudinaryUrl: newCloudinaryUrl,
            meta: meta,
            fallbackDate:
                row['created_at']?.toString() ??
                DateTime.now().toIso8601String(),
          ),
        );
      }

      final migratedFolders = <VaultFolder>[];
      for (var i = 0; i < folderRows.length; i++) {
        final row = folderRows[i];
        final meta = decryptedFolderMeta[i];
        final encryptedMeta = CryptoService.encryptMetadata(meta, _keyBytes!);
        await _api!.updateFolder(
          id: row['id'] as String,
          encryptedMetadata: encryptedMeta['data'] as String,
          metadataIv: jsonEncode(encryptedMeta['iv']),
        );

        migratedFolders.add(
          VaultFolder.fromDecryptedMeta(
            id: row['id'] as String,
            meta: meta,
            fallbackDate:
                row['created_at']?.toString() ??
                DateTime.now().toIso8601String(),
          ),
        );
      }

      _files = migratedFiles;
      _folders = migratedFolders;
      _selectedFile = null;
      _currentFolder = 'all';
      _needsRecovery = false;
      _recoveryFileRows = [];
      _recoveryFolderRows = [];
      _error = null;
      await _saveToCache();

      return const RecoveryResult(
        success: true,
        message: 'Vault re-encryption complete.',
      );
    } catch (e) {
      return RecoveryResult(success: false, message: 'Recovery failed: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  List<int> _parseIvList(dynamic rawIv) {
    final decoded = jsonDecode(rawIv as String) as List<dynamic>;
    return decoded.map<int>((e) => (e as num).toInt()).toList();
  }

  Map<String, dynamic> _normalizeFileMeta(
    Map<String, dynamic> meta,
    dynamic createdAt,
  ) {
    final fileIv = (meta['fileIv'] as List<dynamic>?) ?? const [];
    return {
      'originalName': meta['originalName']?.toString() ?? 'Unknown',
      'originalType':
          meta['originalType']?.toString() ?? 'application/octet-stream',
      'size': (meta['size'] as num?)?.toInt() ?? 0,
      'folderId': meta['folderId']?.toString() ?? 'inbox',
      'fileIv': fileIv.map<int>((e) => (e as num).toInt()).toList(),
      'starred': meta['starred'] == true,
      'description': meta['description']?.toString() ?? '',
      'properties': ((meta['properties'] as List<dynamic>?) ?? const [])
          .map<Map<String, String>>((p) {
            final m = p as Map<String, dynamic>;
            return {
              'key': m['key']?.toString() ?? '',
              'value': m['value']?.toString() ?? '',
            };
          })
          .toList(),
      'dateAdded':
          meta['dateAdded']?.toString() ??
          createdAt?.toString() ??
          DateTime.now().toIso8601String(),
    };
  }

  Map<String, dynamic> _normalizeFolderMeta(
    Map<String, dynamic> meta,
    dynamic createdAt,
  ) {
    return {
      'name': meta['name']?.toString() ?? 'Unnamed',
      'parentId': meta['parentId'],
      'dateAdded':
          meta['dateAdded']?.toString() ??
          createdAt?.toString() ??
          DateTime.now().toIso8601String(),
    };
  }

  void setCurrentFolder(String folderId) {
    _currentFolder = folderId;
    _selectedFile = null;
    _sidebarOpen = false;
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
    await _saveToCache();
    notifyListeners();
  }

  // ── Non-blocking Upload Queue ──

  /// Upload a new file (non-blocking — adds to queue and runs in background).
  Future<void> uploadFile(
    Uint8List fileBytes,
    String fileName,
    String mimeType,
  ) async {
    final taskId = const Uuid().v4();
    final task = UploadTask(id: taskId, fileName: fileName);
    _uploadQueue.add(task);
    notifyListeners();

    // Run upload asynchronously (non-blocking)
    _processUpload(task, fileBytes, fileName, mimeType);
  }

  /// Upload multiple files (batch).
  Future<void> uploadFiles(List<Map<String, dynamic>> filesToUpload) async {
    for (final entry in filesToUpload) {
      final bytes = entry['bytes'] as Uint8List;
      final name = entry['name'] as String;
      final mime = entry['mime'] as String;
      await uploadFile(bytes, name, mime);
      // Small delay between queuing to avoid overwhelming
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<void> _processUpload(
    UploadTask task,
    Uint8List fileBytes,
    String fileName,
    String mimeType,
  ) async {
    try {
      // Step 1: Encrypt
      task.status = 'encrypting';
      task.progress = 0.1;
      notifyListeners();

      final result = CryptoService.encryptFileBytes(fileBytes, _keyBytes!);
      final encryptedBytes = result['encryptedBytes'] as Uint8List;
      final iv = result['iv'] as Uint8List;

      task.progress = 0.3;
      notifyListeners();

      // Step 2: Upload encrypted blob
      task.status = 'uploading';
      task.progress = 0.4;
      notifyListeners();

      final cloudinaryUrl = await _api!.uploadEncryptedBlob(encryptedBytes);

      task.progress = 0.8;
      notifyListeners();

      // Step 3: Create metadata
      task.status = 'saving';
      task.progress = 0.9;
      notifyListeners();

      final newId = const Uuid().v4();
      final meta = {
        'originalName': fileName,
        'originalType': mimeType,
        'size': fileBytes.length,
        'folderId':
            _currentFolder == 'starred' ||
                _currentFolder == 'trash' ||
                _currentFolder == 'all'
            ? 'inbox'
            : _currentFolder,
        'fileIv': iv.toList(),
        'starred': false,
        'description': '',
        'properties': <Map<String, String>>[],
        'dateAdded': DateTime.now().toIso8601String(),
      };

      final encryptedMeta = CryptoService.encryptMetadata(meta, _keyBytes!);

      await _api!.createFile(
        id: newId,
        encryptedMetadata: encryptedMeta['data'] as String,
        metadataIv: jsonEncode(encryptedMeta['iv']),
        cloudinaryUrl: cloudinaryUrl,
      );

      // Step 4: Update local state
      _files.insert(
        0,
        VaultFile.fromDecryptedMeta(
          id: newId,
          cloudinaryUrl: cloudinaryUrl,
          meta: meta,
          fallbackDate: DateTime.now().toIso8601String(),
        ),
      );

      task.status = 'done';
      task.progress = 1.0;
      await _saveToCache();
      notifyListeners();

      // Remove completed task after a delay
      Future.delayed(const Duration(seconds: 3), () {
        _uploadQueue.removeWhere((t) => t.id == task.id);
        notifyListeners();
      });
    } catch (e) {
      task.status = 'error';
      task.error = e.toString();
      notifyListeners();
    }
  }

  void dismissUploadTask(String taskId) {
    _uploadQueue.removeWhere((t) => t.id == taskId);
    notifyListeners();
  }

  /// Create a new folder.
  Future<void> createFolder(String name, {String? parentId}) async {
    _isCreatingFolder = true;
    notifyListeners();
    final newId = const Uuid().v4();
    final meta = {
      'name': name,
      'parentId': parentId,
      'dateAdded': DateTime.now().toIso8601String(),
    };
    try {
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
      await _saveToCache();
    } finally {
      _isCreatingFolder = false;
      notifyListeners();
    }
  }

  Future<void> renameFolder(VaultFolder folder, String newName) async {
    final updated = folder.copyWith(name: newName);
    final encrypted = CryptoService.encryptMetadata(
      updated.toMetadataJson(),
      _keyBytes!,
    );
    await _api!.updateFolder(
      id: folder.id,
      encryptedMetadata: encrypted['data'] as String,
      metadataIv: jsonEncode(encrypted['iv']),
    );

    final idx = _folders.indexWhere((f) => f.id == folder.id);
    if (idx >= 0) {
      _folders[idx] = updated;
    }
    await _saveToCache();
    notifyListeners();
  }

  Future<void> moveFolder(VaultFolder folder, String? targetParentId) async {
    if (targetParentId == folder.id) return;
    final updated = folder.copyWith(
      setParentId: true,
      parentId: targetParentId,
    );
    final encrypted = CryptoService.encryptMetadata(
      updated.toMetadataJson(),
      _keyBytes!,
    );
    await _api!.updateFolder(
      id: folder.id,
      encryptedMetadata: encrypted['data'] as String,
      metadataIv: jsonEncode(encrypted['iv']),
    );

    final idx = _folders.indexWhere((f) => f.id == folder.id);
    if (idx >= 0) {
      _folders[idx] = updated;
    }
    await _saveToCache();
    notifyListeners();
  }

  bool _isFolderDescendant(String candidateId, String ancestorId) {
    String? cursor = candidateId;
    var guard = 0;
    while (cursor != null && guard < 200) {
      if (cursor == ancestorId) return true;
      final f = _folders.where((x) => x.id == cursor).firstOrNull;
      cursor = f?.parentId;
      guard += 1;
    }
    return false;
  }

  List<VaultFolder> validMoveParentsForFolder(String folderId) {
    return _folders
        .where((f) => f.id != folderId && !_isFolderDescendant(f.id, folderId))
        .toList();
  }

  String folderPathLabel(String folderId) {
    final parts = <String>[];
    String? cursor = folderId;
    var guard = 0;
    while (cursor != null && guard < 200) {
      final folder = _folders.where((f) => f.id == cursor).firstOrNull;
      if (folder == null) break;
      parts.insert(0, folder.name);
      cursor = folder.parentId;
      guard += 1;
    }
    if (parts.isEmpty) {
      return folderName(folderId);
    }
    return parts.join(' / ');
  }

  /// Decrypt file bytes for download/preview.
  Future<Uint8List> decryptFileForView(VaultFile file) async {
    final cached = await _readEncryptedBlobFromDisk(file.id);
    if (cached != null) {
      try {
        return CryptoService.decryptFileBytes(cached, _keyBytes!, file.fileIv);
      } catch (_) {
        await _deleteEncryptedBlobFromDisk(file.id);
      }
    }

    final encrypted = await _api!.fetchRawBytes(file.cloudinaryUrl);
    await _writeEncryptedBlobToDisk(file.id, encrypted);
    return CryptoService.decryptFileBytes(encrypted, _keyBytes!, file.fileIv);
  }

  Future<Uint8List?> _readEncryptedBlobFromDisk(String fileId) async {
    if (!_cachedFileIds.contains(fileId)) return null;
    try {
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/vault_enc_$fileId.bin');
      if (!await f.exists()) {
        _cachedFileIds.remove(fileId);
        return null;
      }
      return await f.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeEncryptedBlobToDisk(String fileId, Uint8List bytes) async {
    try {
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/vault_enc_$fileId.bin');
      await f.writeAsBytes(bytes, flush: true);
      _cachedFileIds.add(fileId);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_cacheKeyBlobIds, _cachedFileIds.toList());
    } catch (_) {}
  }

  Future<void> _deleteEncryptedBlobFromDisk(String fileId) async {
    try {
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/vault_enc_$fileId.bin');
      if (await f.exists()) {
        await f.delete();
      }
      _cachedFileIds.remove(fileId);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_cacheKeyBlobIds, _cachedFileIds.toList());
    } catch (_) {}
  }

  Future<void> _purgeEncryptedBlobFiles() async {
    try {
      final dir = await getTemporaryDirectory();
      for (final id in _cachedFileIds) {
        final f = File('${dir.path}/vault_enc_$id.bin');
        if (await f.exists()) {
          await f.delete();
        }
      }
    } catch (_) {}
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
    await _saveToCache();
    notifyListeners();
  }

  Future<void> deleteFilePermanently(VaultFile file) async {
    await _api!.deleteFile(file.id);
    _files.removeWhere((f) => f.id == file.id);
    if (_selectedFile?.id == file.id) {
      _selectedFile = null;
    }
    await _deleteEncryptedBlobFromDisk(file.id);
    await _saveToCache();
    notifyListeners();
  }

  /// Resolve folder name from ID.
  String folderName(String folderId) {
    const builtins = {
      'inbox': 'Inbox',
      'all': 'All Files',
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

  /// Lock the vault and clear all sensitive data.
  void lock() {
    _keyBytes = null;
    _authPassword = null;
    _api = null;
    _error = null;
    _files = [];
    _folders = [];
    _selectedFile = null;
    _currentFolder = 'all';
    _uploadQueue = [];
    _sidebarOpen = false;
    _needsRecovery = false;
    _recoveryFileRows = [];
    _recoveryFolderRows = [];
    _isCreatingFolder = false;
    _cachedFileIds.clear();
    notifyListeners();
  }
}
