export default async function handler(req, res) {
  if (req.method !== 'GET') {
    return res.status(405).json({ error: 'Method Not Allowed' });
  }

  const authHeader = req.headers.authorization;
  if (!authHeader || authHeader !== `Bearer ${process.env.MASTER_PASSWORD}`) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (!process.env.CLOUDINARY_CLOUD_NAME) {
    return res.status(500).json({ error: 'Cloudinary not configured' });
  }

  return res.status(200).json({
    cloudName: process.env.CLOUDINARY_CLOUD_NAME,
    uploadPreset: 'vercel',
    resourceType: 'raw',
  });
}
