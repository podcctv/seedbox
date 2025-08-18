import { FormEvent, useState } from 'react';
import Link from 'next/link';

interface SearchResult {
  id: string;
  title?: string;
  name?: string;
}

export default function Home() {
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<SearchResult[]>([]);
  const [loading, setLoading] = useState(false);

  async function onSearch(e: FormEvent) {
    e.preventDefault();
    setLoading(true);
    try {
      const apiBase = process.env.NEXT_PUBLIC_API_BASE_URL || '';
      const res = await fetch(`${apiBase}/search?q=${encodeURIComponent(query)}`);
      const data = await res.json();
      setResults(data.results || []);
    } catch (err) {
      console.error('search failed', err);
      setResults([]);
    } finally {
      setLoading(false);
    }
  }

  return (
    <main style={{ padding: '2rem' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <h1>Media Search</h1>
        <Link href="/login">Login</Link>
      </div>
      <form onSubmit={onSearch} style={{ marginBottom: '1rem' }}>
        <input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search..."
          style={{ padding: '0.5rem', width: '60%' }}
        />
        <button type="submit" style={{ marginLeft: '0.5rem', padding: '0.5rem 1rem' }}>
          Go
        </button>
      </form>
      {loading && <p>Loading...</p>}
      {!loading && (
        <ul>
          {results.map((r) => (
            <li key={r.id}>{r.title || r.name || r.id}</li>
          ))}
        </ul>
      )}
    </main>
  );
}

