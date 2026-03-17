import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

/// API service that talks to the Vercel serverless endpoints.
class ApiService {
  static const String baseUrl = 'https://document-st.vercel.app';

  final String authPassword;

  ApiService({required this.authPassword});

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $authPassword',
    'Content-Type': 'application/json',
  };

  Map<String, String> get _authOnly => {
    'Authorization': 'Bearer $authPassword',
  };

  // ── Files ──

  /// GET /api/files — returns list of raw DB rows.
  Future<List<Map<String, dynamic>>> fetchFiles() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/files'),
      headers: _authOnly,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch files: ${response.statusCode}');
    }
    final List<dynamic> data = jsonDecode(response.body);
    return data.cast<Map<String, dynamic>>();
  }

  /// POST /api/files — create new file record.
  Future<void> createFile({
    required String id,
    required String encryptedMetadata,
    required String metadataIv,
    required String cloudinaryUrl,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/files'),
      headers: _headers,
      body: jsonEncode({
        'id': id,
        'encrypted_metadata': encryptedMetadata,
        'metadata_iv': metadataIv,
        'cloudinary_url': cloudinaryUrl,
      }),
    );
    if (response.statusCode != 201) {
      throw Exception('Failed to create file: ${response.statusCode}');
    }
  }

  /// PUT /api/files — update file metadata.
  Future<void> updateFile({
    required String id,
    required String encryptedMetadata,
    required String metadataIv,
    String? cloudinaryUrl,
  }) async {
    final payload = <String, dynamic>{
      'id': id,
      'encrypted_metadata': encryptedMetadata,
      'metadata_iv': metadataIv,
    };
    if (cloudinaryUrl != null) {
      payload['cloudinary_url'] = cloudinaryUrl;
    }

    final response = await http.put(
      Uri.parse('$baseUrl/api/files'),
      headers: _headers,
      body: jsonEncode(payload),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to update file: ${response.statusCode}');
    }
  }

  // ── Folders ──

  /// GET /api/folders
  Future<List<Map<String, dynamic>>> fetchFolders() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/folders'),
      headers: _authOnly,
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch folders: ${response.statusCode}');
    }
    final List<dynamic> data = jsonDecode(response.body);
    return data.cast<Map<String, dynamic>>();
  }

  /// POST /api/folders
  Future<void> createFolder({
    required String id,
    required String encryptedMetadata,
    required String metadataIv,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/folders'),
      headers: _headers,
      body: jsonEncode({
        'id': id,
        'encrypted_metadata': encryptedMetadata,
        'metadata_iv': metadataIv,
      }),
    );
    if (response.statusCode != 201) {
      throw Exception('Failed to create folder: ${response.statusCode}');
    }
  }

  /// PUT /api/folders
  Future<void> updateFolder({
    required String id,
    required String encryptedMetadata,
    required String metadataIv,
  }) async {
    final response = await http.put(
      Uri.parse('$baseUrl/api/folders'),
      headers: _headers,
      body: jsonEncode({
        'id': id,
        'encrypted_metadata': encryptedMetadata,
        'metadata_iv': metadataIv,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to update folder: ${response.statusCode}');
    }
  }

  // ── Upload ──

  /// POST /api/upload — upload encrypted blob, returns { url }.
  Future<String> uploadEncryptedBlob(Uint8List encryptedBytes) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/upload'),
    );
    request.headers['Authorization'] = 'Bearer $authPassword';
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        encryptedBytes,
        filename: 'encrypted_blob',
        contentType: MediaType('application', 'octet-stream'),
      ),
    );

    final streamed = await request.send();
    if (streamed.statusCode != 200) {
      throw Exception('Failed to upload: ${streamed.statusCode}');
    }
    final respBody = await streamed.stream.bytesToString();
    final data = jsonDecode(respBody);
    return data['url'] as String;
  }

  /// Fetch raw bytes from a URL (for downloading encrypted blobs from Cloudinary).
  Future<Uint8List> fetchRawBytes(String url) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('Failed to fetch blob: ${response.statusCode}');
    }
    return response.bodyBytes;
  }
}
