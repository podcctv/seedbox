import { useState, useEffect, ChangeEvent } from 'react';
import { useRouter } from 'next/router';

interface Config {
  download_dir: string;
  ffmpeg_preset: string;
}

export default function ConfigPage() {
  const [config, setConfig] = useState<Config>({ download_dir: '', ffmpeg_preset: '' });
  const router = useRouter();

  useEffect(() => {
    const token = localStorage.getItem('token');
    if (!token) {
      router.push('/login');
      return;
    }
    const apiBase = process.env.NEXT_PUBLIC_API_BASE_URL || '';
    fetch(`${apiBase}/admin/config`, {
      headers: { Authorization: `Bearer ${token}` }
    })
      .then((res) => {
        if (res.status === 401 || res.status === 403) {
          router.push('/login');
          return null;
        }
        return res.json();
      })
      .then((data) => {
        if (data) setConfig(data);
      });
  }, [router]);

  const onChange = (field: keyof Config) => (e: ChangeEvent<HTMLInputElement>) => {
    setConfig({ ...config, [field]: e.target.value });
  };

  const save = async () => {
    const token = localStorage.getItem('token');
    const apiBase = process.env.NEXT_PUBLIC_API_BASE_URL || '';
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

  return (
    <main>
      <h1>Configuration</h1>
      <div>
        <label>
          Download Directory
          <input value={config.download_dir} onChange={onChange('download_dir')} />
        </label>
      </div>
      <div>
        <label>
          FFmpeg Preset
          <input value={config.ffmpeg_preset} onChange={onChange('ffmpeg_preset')} />
        </label>
      </div>
      <button onClick={save}>Save</button>
    </main>
  );
}
