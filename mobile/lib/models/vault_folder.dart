/// Data model for a decrypted folder record.
class VaultFolder {
  final String id;
  final String name;
  final String? parentId;
  final String dateAdded;

  VaultFolder({
    required this.id,
    required this.name,
    this.parentId,
    required this.dateAdded,
  });

  VaultFolder copyWith({
    String? name,
    bool setParentId = false,
    String? parentId,
  }) {
    return VaultFolder(
      id: id,
      name: name ?? this.name,
      parentId: setParentId ? parentId : this.parentId,
      dateAdded: dateAdded,
    );
  }

  Map<String, dynamic> toMetadataJson() {
    return {'name': name, 'parentId': parentId, 'dateAdded': dateAdded};
  }

  factory VaultFolder.fromDecryptedMeta({
    required String id,
    required Map<String, dynamic> meta,
    required String fallbackDate,
  }) {
    return VaultFolder(
      id: id,
      name: meta['name']?.toString() ?? 'Unnamed',
      parentId: meta['parentId']?.toString(),
      dateAdded: meta['dateAdded']?.toString() ?? fallbackDate,
    );
  }
}
