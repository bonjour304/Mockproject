const { app, pool } = require('./app');
const seed = require('./seed.json');

const COLS = ['title', 'year', 'genre', 'description', 'poster_url', 'trailer_url'];

async function init() {
  await pool.query(`CREATE TABLE IF NOT EXISTS movies(
    id SERIAL PRIMARY KEY, title TEXT NOT NULL, year INT, genre TEXT, description TEXT,
    poster_url TEXT, trailer_url TEXT, created_at TIMESTAMPTZ DEFAULT now())`);
  const { rows } = await pool.query('SELECT count(*)::int AS n FROM movies');
  if (rows[0].n === 0) {
    for (const m of seed) {
      await pool.query(
        `INSERT INTO movies(${COLS.join(', ')}) VALUES($1, $2, $3, $4, $5, $6)`,
        COLS.map(c => m[c] || null));
    }
  }
  app.listen(8000, () => console.log('ILoveHK Movie API on :8000'));
  for (const m of seed) {
    await pool.query(
      `UPDATE movies SET poster_url = $1 WHERE title = $2 AND poster_url LIKE 'https://placehold.co/%'`,
      [m.poster_url, m.title]);
  }
}
init().catch(err => { console.error(err); process.exit(1); });
