import { useEffect, useState } from 'react';
import './App.css';

const empty = { title: '', year: '', genre: '', description: '', poster_url: '', trailer_url: '' };

// Lấy ID 11 ký tự từ link YouTube (watch?v=, youtu.be/, embed/, shorts/)
const youtubeId = url =>
  (String(url || '').match(/(?:youtu\.be\/|youtube\.com\/(?:watch\?(?:.*&)?v=|embed\/|shorts\/))([\w-]{11})/) || [])[1];

export default function App() {
  const [movies, setMovies] = useState([]);
  const [q, setQ] = useState('');
  const [selected, setSelected] = useState(null);
  const [form, setForm] = useState(null);           // null = ẩn form thêm phim

  const load = () =>
    fetch(`/api/movies?q=${encodeURIComponent(q)}`).then(r => r.json()).then(setMovies);
  useEffect(() => { load(); }, [q]);

  const save = async e => {
    e.preventDefault();
    await fetch('/api/movies', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ...form, year: Number(form.year),
        poster_url: form.poster_url || `https://placehold.co/300x450?text=${encodeURIComponent(form.title)}` }),
    });
    setForm(null);
    load();
  };

  return (
    <div className="app">
      <header>
        <h1>ILoveHK Movie</h1>
        <input placeholder="Tìm phim..." value={q} onChange={e => setQ(e.target.value)} />
        <button onClick={() => setForm(empty)}>+ Thêm phim</button>
      </header>

      {form && (
        <form className="add" onSubmit={save}>
          {['title', 'year', 'genre', 'description', 'poster_url', 'trailer_url'].map(k => (
            <input key={k} placeholder={k} value={form[k]}
              onChange={e => setForm({ ...form, [k]: e.target.value })} />
          ))}
          <button type="submit">Lưu</button>
        </form>
      )}

      <main className="grid">
        {movies.map(m => (
          <div key={m.id} className="card" onClick={() => setSelected(m)}>
            <img src={m.poster_url} alt={m.title} />
            <h3>{m.title}</h3>
            <p>{m.year} · {m.genre}</p>
          </div>
        ))}
      </main>

      {selected && (
        <div className="modal" onClick={() => setSelected(null)}>
          <div className="modal-body" onClick={e => e.stopPropagation()}>
            <h2>{selected.title} ({selected.year})</h2>
            <p>{selected.description}</p>
            {youtubeId(selected.trailer_url)
              ? <iframe className="player" title="Trailer"
                  src={`https://www.youtube-nocookie.com/embed/${youtubeId(selected.trailer_url)}?rel=0`}
                  allow="autoplay; encrypted-media; picture-in-picture; fullscreen" allowFullScreen
                  referrerPolicy="strict-origin-when-cross-origin" />
              : <div className="player">Phim này chưa có trailer</div>}
          </div>
        </div>
      )}

      <footer>ILoveHK Movie · Mock Project DevOps · v1</footer>
    </div>
  );
}
