import { useState, useEffect, ChangeEvent } from 'react';
import Link from 'next/link';

interface Config {
  download_dir: string;
  ffmpeg_preset: string;
  postgres_dsn: string;
}

export default function PostgresPage() {
  const [config, setConfig] = useState<Config>({
    download_dir: '',
    ffmpeg_preset: '',
    postgres_dsn: ''
  });
  const [sql, setSql] = useState('');
  const [rows, setRows] = useState<any[]>([]);
  const [error, setError] = useState('');

  const apiBase = process.env.NEXT_PUBLIC_API_BASE_URL || '';

  useEffect(() => {
    const token = localStorage.getItem('token');
    fetch(`${apiBase}/admin/config`, {
      headers: { Authorization: `Bearer ${token}` }
    })
      .then((res) => res.json())
      .then(setConfig);
  }, []);

  const onChange = (e: ChangeEvent<HTMLInputElement>) => {
    setConfig({ ...config, postgres_dsn: e.target.value });
  };

  const save = async () => {
    const token = localStorage.getItem('token');
    await fetch(`${apiBase}/admin/config`, {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${token}`
      },
      body: JSON.stringify(config)
    });
    alert('saved');
  };

  const runQuery = async () => {
    const token = localStorage.getItem('token');
    const res = await fetch(`${apiBase}/admin/query`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${token}`
      },
      body: JSON.stringify({ sql })
    });
    if (res.ok) {
      const data = await res.json();
      setRows(data.rows || []);
      setError('');
    } else {
      const text = await res.text();
      setError(text);
      setRows([]);
    }
  };

  return (
    <main style={{ padding: '2rem' }}>
      <nav style={{ marginBottom: '1rem' }}>
        <Link href="/admin/config">User Config</Link>
      </nav>
      <h1>Postgres Config</h1>
      <div>
        <label>
          DSN
          <input value={config.postgres_dsn} onChange={onChange} style={{ width: '100%' }} />
        </label>
        <button onClick={save}>Save</button>
      </div>
      <h2>Query</h2>
      <textarea
        value={sql}
        onChange={(e) => setSql(e.target.value)}
        rows={5}
        style={{ width: '100%' }}
      />
      <button onClick={runQuery}>Run</button>
      {error && <pre>{error}</pre>}
      <ul>
        {rows.map((r, i) => (
          <li key={i}>{JSON.stringify(r)}</li>
        ))}
      </ul>
    </main>
  );
}
