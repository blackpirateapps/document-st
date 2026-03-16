import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

/// Crypto utilities matching the web app's crypto.js exactly.
/// Uses AES-GCM 256-bit with PBKDF2 key derivation.
class CryptoService {
  /// Static salt matching the web app's MasterPassword.jsx exactly:
  /// `new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16])`
  static final Uint8List _staticSalt = Uint8List.fromList([
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    11,
    12,
    13,
    14,
    15,
    16,
  ]);

  /// Derive a 256-bit AES key from the master password using PBKDF2-SHA256.
  /// Matches: crypto.subtle.deriveKey with PBKDF2, 100000 iterations, SHA-256.
  static Uint8List deriveKeyBytes(String password) {
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
    pbkdf2.init(Pbkdf2Parameters(_staticSalt, 100000, 32));

    final passwordBytes = utf8.encode(password);
    return pbkdf2.process(Uint8List.fromList(passwordBytes));
  }

  /// Encrypt a file's raw bytes using AES-GCM.
  /// Returns: { encryptedBytes, iv (12 bytes) }
  static Map<String, dynamic> encryptFileBytes(
    Uint8List plainBytes,
    Uint8List keyBytes,
  ) {
    final iv = _generateIV();
    final encrypted = _aesGcmEncrypt(plainBytes, keyBytes, iv);
    return {'encryptedBytes': encrypted, 'iv': iv};
  }

  /// Decrypt a file's encrypted bytes using AES-GCM.
  static Uint8List decryptFileBytes(
    Uint8List encryptedBytes,
    Uint8List keyBytes,
    List<int> ivList,
  ) {
    final iv = Uint8List.fromList(ivList);
    return _aesGcmDecrypt(encryptedBytes, keyBytes, iv);
  }

  /// Encrypt metadata JSON to base64 string, matching the web app's encryptMetadata.
  /// Returns: { data: base64String, iv: List<int> }
  static Map<String, dynamic> encryptMetadata(
    Map<String, dynamic> metadata,
    Uint8List keyBytes,
  ) {
    final jsonStr = jsonEncode(metadata);
    final plainBytes = utf8.encode(jsonStr);
    final iv = _generateIV();
    final encrypted = _aesGcmEncrypt(
      Uint8List.fromList(plainBytes),
      keyBytes,
      iv,
    );
    final base64Data = base64Encode(encrypted);
    return {'data': base64Data, 'iv': iv.toList()};
  }

  /// Decrypt metadata from base64 string, matching the web app's decryptMetadata.
  static Map<String, dynamic> decryptMetadata(
    String encryptedBase64,
    List<int> ivList,
    Uint8List keyBytes,
  ) {
    final encryptedBytes = base64Decode(encryptedBase64);
    final iv = Uint8List.fromList(ivList);
    final decrypted = _aesGcmDecrypt(
      Uint8List.fromList(encryptedBytes),
      keyBytes,
      iv,
    );
    final jsonStr = utf8.decode(decrypted);
    return jsonDecode(jsonStr) as Map<String, dynamic>;
  }

  /// AES-GCM encrypt (matching Web Crypto AES-GCM with 128-bit tag).
  static Uint8List _aesGcmEncrypt(
    Uint8List plain,
    Uint8List keyBytes,
    Uint8List iv,
  ) {
    final cipher = GCMBlockCipher(AESEngine());
    final params = AEADParameters(
      KeyParameter(keyBytes),
      128, // 128-bit auth tag (Web Crypto default)
      iv,
      Uint8List(0),
    );
    cipher.init(true, params);

    final output = Uint8List(cipher.getOutputSize(plain.length));
    final len = cipher.processBytes(plain, 0, plain.length, output, 0);
    cipher.doFinal(output, len);
    return output;
  }

  /// AES-GCM decrypt.
  static Uint8List _aesGcmDecrypt(
    Uint8List encrypted,
    Uint8List keyBytes,
    Uint8List iv,
  ) {
    final cipher = GCMBlockCipher(AESEngine());
    final params = AEADParameters(
      KeyParameter(keyBytes),
      128,
      iv,
      Uint8List(0),
    );
    cipher.init(false, params);

    final output = Uint8List(cipher.getOutputSize(encrypted.length));
    final len = cipher.processBytes(encrypted, 0, encrypted.length, output, 0);
    final finalLen = cipher.doFinal(output, len);
    return Uint8List.fromList(output.sublist(0, len + finalLen));
  }

  /// Generate a 12-byte IV (matching web's generateIV which uses crypto.getRandomValues).
  static Uint8List _generateIV() {
    final random = Random.secure();
    final iv = Uint8List(12);
    for (int i = 0; i < 12; i++) {
      iv[i] = random.nextInt(256);
    }
    return iv;
  }
}
