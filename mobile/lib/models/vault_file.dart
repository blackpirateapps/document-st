/// Data model for a decrypted file record.
class VaultFile {
  final String id;
  final String cloudinaryUrl;
  final String originalName;
  final String originalType;
  final int size;
  final String folderId;
  final List<int> fileIv;
  final bool starred;
  final String description;
  final List<Map<String, String>> properties;
  final String dateAdded;

  VaultFile({
    required this.id,
    required this.cloudinaryUrl,
    required this.originalName,
    required this.originalType,
    required this.size,
    required this.folderId,
    required this.fileIv,
    this.starred = false,
    this.description = '',
    this.properties = const [],
    required this.dateAdded,
  });

  VaultFile copyWith({
    String? originalName,
    String? folderId,
    bool? starred,
    String? description,
    List<Map<String, String>>? properties,
  }) {
    return VaultFile(
      id: id,
      cloudinaryUrl: cloudinaryUrl,
      originalName: originalName ?? this.originalName,
      originalType: originalType,
      size: size,
      folderId: folderId ?? this.folderId,
      fileIv: fileIv,
      starred: starred ?? this.starred,
      description: description ?? this.description,
      properties: properties ?? this.properties,
      dateAdded: dateAdded,
    );
  }

  /// Serialize the metadata fields that get encrypted.
  Map<String, dynamic> toMetadataJson() {
    return {
      'originalName': originalName,
      'originalType': originalType,
      'size': size,
      'folderId': folderId,
      'fileIv': fileIv,
      'starred': starred,
      'description': description,
      'properties': properties
          .map((p) => {'key': p['key'], 'value': p['value']})
          .toList(),
      'dateAdded': dateAdded,
    };
  }

  factory VaultFile.fromDecryptedMeta({
    required String id,
    required String cloudinaryUrl,
    required Map<String, dynamic> meta,
    required String fallbackDate,
  }) {
    final rawProps = (meta['properties'] as List<dynamic>?) ?? [];
    final props = rawProps.map<Map<String, String>>((p) {
      final m = p as Map<String, dynamic>;
      return {
        'key': m['key']?.toString() ?? '',
        'value': m['value']?.toString() ?? '',
      };
    }).toList();

    final rawIv = (meta['fileIv'] as List<dynamic>?) ?? [];
    final ivList = rawIv.map<int>((e) => (e as num).toInt()).toList();

    return VaultFile(
      id: id,
      cloudinaryUrl: cloudinaryUrl,
      originalName: meta['originalName']?.toString() ?? 'Unknown',
      originalType:
          meta['originalType']?.toString() ?? 'application/octet-stream',
      size: (meta['size'] as num?)?.toInt() ?? 0,
      folderId: meta['folderId']?.toString() ?? 'inbox',
      fileIv: ivList,
      starred: meta['starred'] == true,
      description: meta['description']?.toString() ?? '',
      properties: props,
      dateAdded: meta['dateAdded']?.toString() ?? fallbackDate,
    );
  }
}
