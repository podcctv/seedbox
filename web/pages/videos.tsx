import { useEffect, useState } from 'react';

interface Video {
  content_id: string;
  title: string;
  type: string;
  year?: string | null;
  torrent_id: string;
  torrent_name: string;
  infohash: string;
  size: number;
}

export default function Videos() {
  const [videos, setVideos] = useState<Video[]>([]);

  useEffect(() => {
    const apiBase = process.env.NEXT_PUBLIC_API_BASE_URL || '';
    fetch(`${apiBase}/videos`)
      .then((res) => res.json())
      .then((data) => setVideos(data.videos || []))
      .catch((err) => {
        console.error('videos fetch failed', err);
        setVideos([]);
      });
  }, []);

  return (
    <main style={{ padding: '2rem' }}>
      <h1>Videos</h1>
      <ul>
        {videos.map((m) => (
          <li key={`${m.content_id}-${m.torrent_id}`}>
            {m.title} {m.year ? `(${m.year})` : ''} - {m.torrent_name}
          </li>
        ))}
      </ul>
    </main>
  );
}
