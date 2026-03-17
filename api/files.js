import { createClient } from '@libsql/client';

const db = createClient({
  url: process.env.TURSO_DATABASE_URL,
  authToken: process.env.TURSO_AUTH_TOKEN,
});

export default async function handler(req, res) {
  // Simple Master Password authentication
  const authHeader = req.headers.authorization;
  if (!authHeader || authHeader !== `Bearer ${process.env.MASTER_PASSWORD}`) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  try {
    // Ensure table exists (useful for initial deployment)
    await db.execute(`
      CREATE TABLE IF NOT EXISTS files (
        id TEXT PRIMARY KEY,
        encrypted_metadata TEXT,
        metadata_iv TEXT,
        cloudinary_url TEXT,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
      )
    `);

    if (req.method === 'GET') {
      const result = await db.execute('SELECT * FROM files ORDER BY created_at DESC');
      return res.status(200).json(result.rows);
    }

    if (req.method === 'POST') {
      const { id, encrypted_metadata, metadata_iv, cloudinary_url } = req.body;
      
      if (!id || !encrypted_metadata || !metadata_iv || !cloudinary_url) {
        return res.status(400).json({ error: 'Missing required fields' });
      }

      await db.execute({
        sql: 'INSERT INTO files (id, encrypted_metadata, metadata_iv, cloudinary_url) VALUES (?, ?, ?, ?)',
        args: [id, encrypted_metadata, metadata_iv, cloudinary_url]
      });

      return res.status(201).json({ success: true });
    }

    if (req.method === 'PUT') {
      const { id, encrypted_metadata, metadata_iv, cloudinary_url } = req.body;
      
      if (!id || !encrypted_metadata || !metadata_iv) {
        return res.status(400).json({ error: 'Missing required fields' });
      }

      if (cloudinary_url) {
        await db.execute({
          sql: 'UPDATE files SET encrypted_metadata = ?, metadata_iv = ?, cloudinary_url = ? WHERE id = ?',
          args: [encrypted_metadata, metadata_iv, cloudinary_url, id]
        });
      } else {
        await db.execute({
          sql: 'UPDATE files SET encrypted_metadata = ?, metadata_iv = ? WHERE id = ?',
          args: [encrypted_metadata, metadata_iv, id]
        });
      }

      return res.status(200).json({ success: true });
    }

    res.status(405).json({ error: 'Method Not Allowed' });
  } catch (error) {
    console.error('Database error:', error);
    res.status(500).json({ error: 'Internal Server Error' });
  }
}
