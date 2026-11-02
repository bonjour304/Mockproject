const express = require('express');
const { Pool } = require('pg');
const client = require('prom-client');

const pool = new Pool({
  host: process.env.DB_HOST, port: 5432,
  user: process.env.DB_USER, password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  ssl: process.env.DB_SSL === 'true' ? { rejectUnauthorized: false } : false, // RDS: true
});

const app = express();
app.use(express.json());
client.collectDefaultMetrics();

const COLS = ['title', 'year', 'genre', 'description', 'poster_url', 'trailer_url'];

app.get('/api/health', (req, res) => res.json({ status: 'ok' }));

app.get('/api/metrics', async (req, res) => {
  res.set('Content-Type', client.register.contentType);
  res.end(await client.register.metrics());
});

app.get('/api/movies', async (req, res) => {
  const { rows } = await pool.query(
    'SELECT * FROM movies WHERE title ILIKE $1 ORDER BY year DESC',
    [`%${req.query.q || ''}%`]);
  res.json(rows);
});

app.get('/api/movies/:id', async (req, res) => {
  const { rows } = await pool.query('SELECT * FROM movies WHERE id = $1', [req.params.id]);
  rows[0] ? res.json(rows[0]) : res.status(404).json({ error: 'Not found' });
});

app.post('/api/movies', async (req, res) => {
  const { rows } = await pool.query(
    `INSERT INTO movies(${COLS.join(', ')}) VALUES($1, $2, $3, $4, $5, $6) RETURNING *`,
    COLS.map(c => req.body[c] || null));
  res.status(201).json(rows[0]);
});

// Chỉ để demo auto scaling – mặc định tắt
app.get('/api/stress', (req, res) => {
  if (process.env.ENABLE_STRESS !== 'true') return res.status(404).end();
  const end = Date.now() + 200;
  while (Date.now() < end) Math.sqrt(Math.random());
  res.json({ pod: require('os').hostname() });
});

module.exports = { app, pool };
