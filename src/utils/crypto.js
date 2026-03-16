export const generateSalt = () => crypto.getRandomValues(new Uint8Array(16));
export const generateIV = () => crypto.getRandomValues(new Uint8Array(12));

export const deriveKey = async (password, existingSalt = null) => {
  const enc = new TextEncoder();
  const keyMaterial = await crypto.subtle.importKey(
    'raw',
    enc.encode(password),
    { name: 'PBKDF2' },
    false,
    ['deriveBits', 'deriveKey']
  );

  const salt = existingSalt ? existingSalt : generateSalt();

  const key = await crypto.subtle.deriveKey(
    {
      name: 'PBKDF2',
      salt: salt,
      iterations: 100000,
      hash: 'SHA-256',
    },
    keyMaterial,
    { name: 'AES-GCM', length: 256 },
    true,
    ['encrypt', 'decrypt']
  );

  return { key, salt };
};

export const encryptFile = async (file, key) => {
  const arrayBuffer = await file.arrayBuffer();
  const iv = generateIV();
  
  const encryptedBuffer = await crypto.subtle.encrypt(
    { name: 'AES-GCM', iv },
    key,
    arrayBuffer
  );

  return {
    encryptedBlob: new Blob([encryptedBuffer]),
    iv: Array.from(iv), // Store as array for JSON serialization later
    originalName: file.name,
    originalType: file.type,
    size: file.size
  };
};

export const decryptFile = async (encryptedBlob, key, ivArray, type) => {
  const arrayBuffer = await encryptedBlob.arrayBuffer();
  const iv = new Uint8Array(ivArray);

  const decryptedBuffer = await crypto.subtle.decrypt(
    { name: 'AES-GCM', iv },
    key,
    arrayBuffer
  );

  return new Blob([decryptedBuffer], { type });
};

export const encryptMetadata = async (metadata, key) => {
  const enc = new TextEncoder();
  const encodedMetadata = enc.encode(JSON.stringify(metadata));
  const iv = generateIV();

  const encryptedBuffer = await crypto.subtle.encrypt(
    { name: 'AES-GCM', iv },
    key,
    encodedMetadata
  );

  // Convert buffer to base64 string for easy storage
  const encryptedBase64 = btoa(String.fromCharCode(...new Uint8Array(encryptedBuffer)));
  
  return {
    data: encryptedBase64,
    iv: Array.from(iv)
  };
};

export const decryptMetadata = async (encryptedBase64, ivArray, key) => {
  const encryptedBuffer = new Uint8Array(
    atob(encryptedBase64).split('').map(char => char.charCodeAt(0))
  );
  const iv = new Uint8Array(ivArray);

  const decryptedBuffer = await crypto.subtle.decrypt(
    { name: 'AES-GCM', iv },
    key,
    encryptedBuffer
  );

  const dec = new TextDecoder();
  const decryptedString = dec.decode(decryptedBuffer);
  return JSON.parse(decryptedString);
};

export const generateUUID = () => crypto.randomUUID();
