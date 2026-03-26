<p align="center">
  <h1 align="center">plate.sh</h1>
  <p align="center">One command. Full-stack project. Go + React + Tailwind + Postgres migrations.</p>
  <p align="center">
    <img src="https://img.shields.io/badge/build-passing%20(probably)-brightgreen" alt="build passing" />
    <img src="https://img.shields.io/badge/vite-react-blue" alt="vite react" />
    <img src="https://img.shields.io/badge/tailwind-v4-38bdf8" alt="tailwind v4" />
    <img src="https://img.shields.io/badge/go-1.22+-00ADD8" alt="go" />
    <img src="https://img.shields.io/badge/migrations-supabase%20style-3ecf8e" alt="migrations" />
  </p>
</p>

---

## Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/imranparuk/boiler/refs/heads/main/plate.sh | bash -s myproject
```

That's it. You now have a full-stack project.

## Usage

```bash
# Basic — React + Go backend
./plate.sh myproject

# With TypeScript
./plate.sh myproject --template react-ts

# With Vue instead of React
./plate.sh myproject --template vue

# With a custom Go module path
./plate.sh myproject --module github.com/me/myproject
```

| Flag | Default | Description |
|------|---------|-------------|
| `myproject` (first arg) | *required* | Project name |
| `--template` | `react` | Vite template (`react`, `react-ts`, `vue`, `vue-ts`, `svelte`, etc.) |
| `--module` | `<project-name>` | Go module path for `go mod init` |

## What You Get

```
myproject/
├── .env                          # DATABASE_URL + VITE_API_URL (local)
├── .env.dev                      # dev environment
├── .env.main                     # production environment
├── .gitignore
│
├── backend/
│   ├── go.mod
│   ├── cmd/
│   │   └── server/
│   │       └── main.go           # HTTP server with /health endpoint
│   └── internal/
│       └── config/
│           └── config.go         # env-aware config loader
│
├── database/
│   ├── go.mod
│   ├── migrate.go                # migration runner
│   ├── seed.sql                  # seed data
│   └── migrations/
│       └── 20260326XXXXXX_initial_setup.sql
│
├── src/                          # Vite + React + Tailwind v4
│   ├── main.jsx
│   ├── App.jsx
│   └── index.css                 # @import "tailwindcss"
│
├── index.html
├── vite.config.js                # React + Tailwind + /api proxy
└── package.json
```

## Running the Project

### Frontend

```bash
cd myproject
npm run dev
```

### Backend

```bash
cd myproject/backend
go run ./cmd/server
```

The Vite dev server proxies `/api` requests to `localhost:8080` automatically.

### Migrations

```bash
cd myproject

# Run pending migrations
go run ./database/

# Check status
go run ./database/ --status

# Target an environment
go run ./database/ --env dev
go run ./database/ --env main

# Nuclear option — drop everything, re-run all
go run ./database/ --reset
```

Migrations are Supabase-style: single `.sql` files named `YYYYMMDDHHMMSS_description.sql`. No up/down files. Tracked in a `_migrations` table so each file only runs once.

## Connect to GitHub

After creating a repo on GitHub:

```bash
cd myproject
git remote add origin git@github.com:you/myproject.git
git push -u origin main
```

The script already runs `git init` and makes an initial commit for you.

## Requirements

- [Go](https://go.dev/) 1.22+
- [Node.js](https://nodejs.org/) 18+
- npm

---

<p align="center">
  <sub>by <a href="https://github.com/imranparuk">@imranparuk</a></sub>
</p>
