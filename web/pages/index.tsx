import { useRouter } from 'next/router';
import VideoPlayer from '../components/VideoPlayer';

export default function Home() {
  const router = useRouter();
  const { src } = router.query;
  const streamSrc = typeof src === 'string' ? src : '/hls/sample.m3u8';

  return (
    <main style={{ padding: '2rem', textAlign: 'center' }}>
      <h1>Seedbox Player</h1>
      <VideoPlayer src={streamSrc} />
    </main>
  );
}
