import { v2 as cloudinary } from 'cloudinary';

cloudinary.config({
  cloud_name: process.env.CLOUDINARY_CLOUD_NAME,
  api_key: process.env.CLOUDINARY_API_KEY,
  api_secret: process.env.CLOUDINARY_API_SECRET,
});

export default async function handler(req, res) {
  if (req.method !== 'GET') {
    return res.status(405).json({ error: 'Method Not Allowed' });
  }

  const authHeader = req.headers.authorization;
  if (!authHeader || authHeader !== `Bearer ${process.env.MASTER_PASSWORD}`) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (
    !process.env.CLOUDINARY_CLOUD_NAME ||
    !process.env.CLOUDINARY_API_KEY ||
    !process.env.CLOUDINARY_API_SECRET
  ) {
    return res.status(503).json({ error: 'Cloudinary admin usage unavailable' });
  }

  try {
    const usage = await cloudinary.api.usage();
    return res.status(200).json({ usage });
  } catch (error) {
    console.error('Cloudinary usage fetch failed:', error);
    return res.status(502).json({ error: 'Failed to fetch Cloudinary usage' });
  }
}
