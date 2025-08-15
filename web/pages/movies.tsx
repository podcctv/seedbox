import { useEffect, useState } from 'react';

interface Movie {
  content_id: string;
  title: string;
  year?: string | null;
  torrent_id: string;
  torrent_name: string;
  infohash: string;
  size: number;
}

export default function Movies() {
  const [movies, setMovies] = useState<Movie[]>([]);

  useEffect(() => {
    const apiBase = process.env.NEXT_PUBLIC_API_BASE_URL || '';
    fetch(`${apiBase}/movies`)
      .then((res) => res.json())
      .then((data) => setMovies(data.movies || []))
      .catch((err) => {
        console.error('movies fetch failed', err);
        setMovies([]);
      });
  }, []);

  return (
    <main style={{ padding: '2rem' }}>
      <h1>Movies</h1>
      <ul>
        {movies.map((m) => (
          <li key={`${m.content_id}-${m.torrent_id}`}>
            {m.title} {m.year ? `(${m.year})` : ''} - {m.torrent_name}
          </li>
        ))}
      </ul>
    </main>
  );
}
