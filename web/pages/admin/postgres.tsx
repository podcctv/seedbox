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
  // keyword based query string
  const [keyword, setKeyword] = useState('');
  const [rows, setRows] = useState<any[]>([]);
  const [error, setError] = useState('');
  const [logs, setLogs] = useState<string[]>([]);

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
    // escape single quotes to avoid breaking the SQL string
    const safe = keyword.replace(/'/g, "''");
    const sql =
      "SELECT encode(info_hash, 'hex') AS id, name FROM public.torrents WHERE name ILIKE '%" +
      safe +
      "%' LIMIT 20";
    setLogs((prev) => [...prev, `Executing: ${sql}`]);
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
      setLogs((prev) => [...prev, `Rows: ${data.rows?.length || 0}`]);
    } else {
      const text = await res.text();
      setError(text);
      setRows([]);
      setLogs((prev) => [...prev, `Error: ${text}`]);
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
      <input
        value={keyword}
        onChange={(e) => setKeyword(e.target.value)}
        placeholder="Enter keyword"
        style={{ width: '100%' }}
      />
      <button onClick={runQuery}>Search</button>
      {error && <pre>{error}</pre>}
      <ul>
        {rows.map((r, i) => (
          <li key={i}>{JSON.stringify(r)}</li>
        ))}
      </ul>
      <h2>Logs</h2>
      <pre>{logs.join('\n')}</pre>
    </main>
  );
}
