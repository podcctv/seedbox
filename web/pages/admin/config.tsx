import { useState, useEffect, ChangeEvent } from 'react';

interface Config {
  download_dir: string;
  ffmpeg_preset: string;
}

export default function ConfigPage() {
  const [config, setConfig] = useState<Config>({ download_dir: '', ffmpeg_preset: '' });

  useEffect(() => {
    fetch('http://localhost:8000/admin/config', {
      headers: { Authorization: 'Bearer fake-jwt' }
    })
      .then((res) => res.json())
      .then(setConfig);
  }, []);

  const onChange = (field: keyof Config) => (e: ChangeEvent<HTMLInputElement>) => {
    setConfig({ ...config, [field]: e.target.value });
  };

  const save = async () => {
    await fetch('http://localhost:8000/admin/config', {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer fake-jwt'
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
