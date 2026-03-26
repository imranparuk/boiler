#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────
#  plate.sh — scaffold a Go + React (Vite) project
#  Author: github.com/imranparuk
#
#  Usage:  ./boilerplate.sh myproject
#          ./boilerplate.sh myproject --module github.com/me/myproject
#          ./boilerplate.sh myproject --template react-ts
#          ./boilerplate.sh myproject --module github.com/me/myproject --template vue
# ─────────────────────────────────────────────────────────────

NAME=""
MODULE=""
VITE_TEMPLATE="react"

# First positional arg is the project name
if [[ $# -gt 0 && ! "$1" =~ ^-- ]]; then
  NAME="$1"; shift
fi

while [[ $# -gt 0 ]]; do
  case $1 in
    --module) MODULE="$2"; shift 2 ;;
    --template) VITE_TEMPLATE="$2"; shift 2 ;;
    *) echo "Unknown flag: $1"; exit 1 ;;
  esac
done

if [[ -z "$NAME" ]]; then
  echo "Usage: ./boilerplate.sh <project-name> [--module <go-module>] [--template <vite-template>]"
  exit 1
fi

if [[ -z "$MODULE" ]]; then
  MODULE="$NAME"
fi

echo ""
echo "  ┌──────────────────────────────────────┐"
echo "  │  Scaffolding project: $NAME"
echo "  │  Go module:           $MODULE"
echo "  └──────────────────────────────────────┘"
echo ""

# ─────────────────────────────────────────────
#  Frontend — Vite + React + Tailwind
# ─────────────────────────────────────────────
echo "→ Scaffolding frontend with Vite..."
npx --yes create-vite "$NAME" --template "$VITE_TEMPLATE" --no-install

cd "$NAME"
PROJECT_ROOT="$(pwd)"

echo "→ Installing npm dependencies..."
npm install

echo "→ Installing Tailwind CSS v4..."
npm install tailwindcss @tailwindcss/vite

# ─────────────────────────────────────────────
#  .env files
# ─────────────────────────────────────────────
echo "→ Creating .env files..."

cat > .env <<'EOF'
DATABASE_URL=postgresql://postgres:postgres@localhost:54322/postgres
VITE_API_URL=http://localhost:8080
EOF

cat > .env.dev <<'EOF'
DATABASE_URL=postgresql://postgres:postgres@db.xxx.supabase.co:5432/postgres
VITE_API_URL=https://api-dev.example.com
EOF

cat > .env.main <<'EOF'
DATABASE_URL=postgresql://postgres:postgres@db.xxx.supabase.co:5432/postgres
VITE_API_URL=https://api.example.com
EOF

# ─────────────────────────────────────────────
#  .gitignore
# ─────────────────────────────────────────────
echo "→ Creating .gitignore..."

cat > .gitignore <<'EOF'
node_modules/
dist/
.env
.env.local
tmp/
*.exe
*.test
*.out
.DS_Store
EOF

# ─────────────────────────────────────────────
#  Backend — Go
# ─────────────────────────────────────────────
echo "→ Creating backend structure..."

mkdir -p backend/cmd/server
mkdir -p backend/internal/config

# --- backend/go.mod ---
cd "$PROJECT_ROOT/backend"
go mod init "${MODULE}/backend"
go get github.com/jackc/pgx/v5
go mod tidy

# --- backend/internal/config/config.go ---
cat > internal/config/config.go <<'GOEOF'
package config

import (
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
)

var (
	_, srcFile, _, _ = runtime.Caller(0)
	repoRoot         = filepath.Dir(filepath.Dir(filepath.Dir(filepath.Dir(srcFile))))
)

type Config struct {
	DatabaseURL string
	Port        string
}

func Load(env string) *Config {
	envFiles := map[string]string{
		"main":  filepath.Join(repoRoot, ".env.main"),
		"dev":   filepath.Join(repoRoot, ".env.dev"),
		"local": filepath.Join(repoRoot, ".env"),
	}

	vars := map[string]string{}

	envFile := envFiles[env]
	if env == "local" {
		localFile := filepath.Join(repoRoot, ".env.local")
		if _, err := os.Stat(localFile); err == nil {
			envFile = localFile
		}
	}

	if data, err := os.ReadFile(envFile); err == nil {
		for _, line := range strings.Split(string(data), "\n") {
			line = strings.TrimSpace(line)
			if strings.HasPrefix(line, "#") || !strings.Contains(line, "=") {
				continue
			}
			key, val, _ := strings.Cut(line, "=")
			vars[strings.TrimSpace(key)] = strings.TrimSpace(val)
		}
	}

	get := func(key, fallback string) string {
		if v, ok := vars[key]; ok {
			return v
		}
		if v := os.Getenv(key); v != "" {
			return v
		}
		return fallback
	}

	cfg := &Config{
		DatabaseURL: get("DATABASE_URL", ""),
		Port:        get("PORT", "8080"),
	}

	if cfg.DatabaseURL == "" {
		fmt.Fprintf(os.Stderr, "WARNING: DATABASE_URL not set (%s)\n", envFile)
	}

	return cfg
}
GOEOF

# --- backend/cmd/server/main.go ---
cat > cmd/server/main.go <<'GOEOF'
package main

import (
	"flag"
	"fmt"
	"log"
	"net/http"

	"MODPLACEHOLDER/backend/internal/config"
)

func main() {
	env := flag.String("env", "local", "Environment: local, dev, main")
	flag.Parse()

	cfg := config.Load(*env)

	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprintf(w, `{"status":"ok"}`)
	})

	addr := ":" + cfg.Port
	log.Printf("server listening on %s (env=%s)\n", addr, *env)
	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatal(err)
	}
}
GOEOF

# Replace module placeholder
if [[ "$(uname)" == "Darwin" ]]; then
  sed -i '' "s|MODPLACEHOLDER|${MODULE}|g" cmd/server/main.go
else
  sed -i "s|MODPLACEHOLDER|${MODULE}|g" cmd/server/main.go
fi

cd "$PROJECT_ROOT"

# ─────────────────────────────────────────────
#  Database — migrations
# ─────────────────────────────────────────────
echo "→ Creating database/migrations..."

mkdir -p database/migrations

# --- database/go.mod ---
cd "$PROJECT_ROOT/database"
go mod init "${MODULE}/database"
go get github.com/jackc/pgx/v5
go mod tidy

# --- database/migrate.go ---
cat > migrate.go <<'GOEOF'
// Run pending SQL migrations against a Postgres database.
//
// Tracks applied migrations in a _migrations table so each file only runs once.
// Also runs seed.sql if the seed hasn't been applied yet.
//
// Usage:
//
//    go run ./database/                      # local (default)
//    go run ./database/ --env dev            # uses .env.dev
//    go run ./database/ --env main           # uses .env.main
//    go run ./database/ --env local          # uses .env (or .env.local)
//    go run ./database/ --status             # show migration status
//    go run ./database/ --reset              # drop schema and re-run all
//    go run ./database/ --env dev --reset    # reset dev database
package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strings"

	"github.com/jackc/pgx/v5"
)

var (
	_, srcFile, _, _ = runtime.Caller(0)
	here             = filepath.Dir(srcFile)
	repoRoot         = filepath.Dir(here)
	migrationsDir    = filepath.Join(here, "migrations")
	seedFile         = filepath.Join(here, "seed.sql")
	envFiles         = map[string]string{
		"main":  filepath.Join(repoRoot, ".env.main"),
		"dev":   filepath.Join(repoRoot, ".env.dev"),
		"local": filepath.Join(repoRoot, ".env.local"),
	}
)

const trackingTable = `
CREATE TABLE IF NOT EXISTS _migrations (
    filename   TEXT PRIMARY KEY,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT now()
);`

func loadDatabaseURL(env string) string {
	envFile := envFiles[env]
	if env == "local" {
		if _, err := os.Stat(envFile); err != nil {
			envFile = filepath.Join(repoRoot, ".env")
		}
	}
	if data, err := os.ReadFile(envFile); err == nil {
		for _, line := range strings.Split(string(data), "\n") {
			line = strings.TrimSpace(line)
			if strings.HasPrefix(line, "#") || !strings.Contains(line, "=") {
				continue
			}
			key, val, _ := strings.Cut(line, "=")
			if strings.TrimSpace(key) == "DATABASE_URL" {
				return strings.TrimSpace(val)
			}
		}
	}
	if url := os.Getenv("DATABASE_URL"); url != "" {
		return url
	}
	fmt.Fprintf(os.Stderr, "ERROR: DATABASE_URL not found in %s\n", envFile)
	os.Exit(1)
	return ""
}

func connect(ctx context.Context, dbURL string) *pgx.Conn {
	conn, err := pgx.Connect(ctx, dbURL)
	if err != nil {
		fmt.Fprintf(os.Stderr, "ERROR: could not connect: %v\n", err)
		os.Exit(1)
	}
	return conn
}

func ensureTracking(ctx context.Context, conn *pgx.Conn) {
	if _, err := conn.Exec(ctx, trackingTable); err != nil {
		fmt.Fprintf(os.Stderr, "ERROR: could not create tracking table: %v\n", err)
		os.Exit(1)
	}
}

func getApplied(ctx context.Context, conn *pgx.Conn) map[string]bool {
	rows, err := conn.Query(ctx, "SELECT filename FROM _migrations")
	if err != nil {
		fmt.Fprintf(os.Stderr, "ERROR: %v\n", err)
		os.Exit(1)
	}
	defer rows.Close()
	applied := map[string]bool{}
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err == nil {
			applied[name] = true
		}
	}
	return applied
}

func getMigrationFiles() []string {
	entries, err := os.ReadDir(migrationsDir)
	if err != nil {
		fmt.Fprintf(os.Stderr, "ERROR: reading migrations dir: %v\n", err)
		os.Exit(1)
	}
	var files []string
	for _, e := range entries {
		if !e.IsDir() && strings.HasSuffix(e.Name(), ".sql") {
			files = append(files, e.Name())
		}
	}
	sort.Strings(files)
	return files
}

func applyFile(ctx context.Context, conn *pgx.Conn, path, name string) bool {
	data, err := os.ReadFile(path)
	if err != nil {
		fmt.Fprintf(os.Stderr, "    ERROR: %v\n", err)
		return false
	}
	sql := fmt.Sprintf(
		"BEGIN;\n%s\nINSERT INTO _migrations (filename) VALUES ('%s');\nCOMMIT;",
		string(data), name,
	)
	if _, err := conn.Exec(ctx, sql); err != nil {
		fmt.Fprintf(os.Stderr, "    ERROR: %v\n", err)
		return false
	}
	return true
}

func cmdMigrate(ctx context.Context, conn *pgx.Conn) {
	ensureTracking(ctx, conn)
	applied := getApplied(ctx, conn)
	files := getMigrationFiles()

	var pending []string
	for _, f := range files {
		if !applied[f] {
			pending = append(pending, f)
		}
	}

	_, seedErr := os.Stat(seedFile)
	if len(pending) == 0 && applied["seed.sql"] {
		fmt.Println("  ✓ Everything up to date.")
		return
	}

	if len(pending) > 0 {
		fmt.Printf("  %d pending migration(s):\n\n", len(pending))
		for _, f := range pending {
			fmt.Printf("    → %s ... ", f)
			if applyFile(ctx, conn, filepath.Join(migrationsDir, f), f) {
				fmt.Println("✓")
			} else {
				fmt.Println("✗ FAILED — aborting")
				os.Exit(1)
			}
		}
		fmt.Println()
	}

	if seedErr == nil && !applied["seed.sql"] {
		fmt.Printf("    → seed.sql ... ")
		if applyFile(ctx, conn, seedFile, "seed.sql") {
			fmt.Println("✓")
		} else {
			fmt.Println("✗ FAILED")
			os.Exit(1)
		}
		fmt.Println()
	}

	fmt.Println("  ✓ Done!")
}

func cmdStatus(ctx context.Context, conn *pgx.Conn) {
	ensureTracking(ctx, conn)
	applied := getApplied(ctx, conn)
	files := getMigrationFiles()

	fmt.Println()
	fmt.Printf("  %-50s STATUS\n", "FILE")
	fmt.Printf("  %s\n", strings.Repeat("─", 62))
	for _, f := range files {
		if applied[f] {
			fmt.Printf("  ✓ %-48s applied\n", f)
		} else {
			fmt.Printf("  • %-48s PENDING\n", f)
		}
	}
	if _, err := os.Stat(seedFile); err == nil {
		if applied["seed.sql"] {
			fmt.Printf("  ✓ %-48s applied\n", "seed.sql")
		} else {
			fmt.Printf("  • %-48s PENDING\n", "seed.sql")
		}
	}

	pending := 0
	for _, f := range files {
		if !applied[f] {
			pending++
		}
	}
	if _, err := os.Stat(seedFile); err == nil && !applied["seed.sql"] {
		pending++
	}
	fmt.Printf("\n  %d migration(s), %d pending\n\n", len(files), pending)
}

func cmdReset(ctx context.Context, conn *pgx.Conn) {
	fmt.Println("  ⚠ Dropping all objects in public schema...")
	if _, err := conn.Exec(ctx, "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"); err != nil {
		fmt.Fprintf(os.Stderr, "ERROR: %v\n", err)
		os.Exit(1)
	}
	fmt.Println("  Re-running all migrations...\n")
	cmdMigrate(ctx, conn)
}

func main() {
	env := flag.String("env", "local", "Target environment: local (default), dev, or main")
	status := flag.Bool("status", false, "Show migration status")
	reset := flag.Bool("reset", false, "Drop schema and re-run all")
	flag.Parse()

	dbURL := loadDatabaseURL(*env)
	envFileName := filepath.Base(envFiles[*env])

	fmt.Println()
	fmt.Println("  ┌──────────────────────────────────────┐")
	fmt.Printf("  │  env:  %-30s │\n", fmt.Sprintf("%s (%s)", *env, envFileName))
	if len(dbURL) > 30 {
		fmt.Printf("  │  db:   %-30s │\n", dbURL[:30]+"...")
	} else {
		fmt.Printf("  │  db:   %-30s │\n", dbURL)
	}
	fmt.Println("  └──────────────────────────────────────┘")
	fmt.Println()

	ctx := context.Background()
	conn := connect(ctx, dbURL)
	defer conn.Close(ctx)

	switch {
	case *status:
		cmdStatus(ctx, conn)
	case *reset:
		cmdReset(ctx, conn)
	default:
		cmdMigrate(ctx, conn)
	}
}
GOEOF

# --- Example migration ---
MIGRATION_DATE=$(date +%Y%m%d%H%M%S)
cat > "migrations/${MIGRATION_DATE}_initial_setup.sql" <<'SQLEOF'
-- Enable common extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Example: users table
CREATE TABLE IF NOT EXISTS users (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email       TEXT NOT NULL UNIQUE,
    name        TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Updated-at trigger
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();
SQLEOF

# --- seed.sql ---
cat > seed.sql <<'SQLEOF'
-- Seed data
INSERT INTO users (email, name) VALUES
    ('admin@example.com', 'Admin')
ON CONFLICT (email) DO NOTHING;
SQLEOF

cd "$PROJECT_ROOT"

# --- Patch vite.config.js for Tailwind v4 ---
cat > vite.config.js <<'JSEOF'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

export default defineConfig({
  plugins: [
    react(),
    tailwindcss(),
  ],
  server: {
    proxy: {
      '/api': {
        target: 'http://localhost:8080',
        changeOrigin: true,
      },
    },
  },
})
JSEOF

# --- Patch src/index.css for Tailwind v4 ---
cat > src/index.css <<'CSSEOF'
@import "tailwindcss";
CSSEOF

# --- Replace App.jsx with a minimal Tailwind-ready component ---
cat > src/App.jsx <<'JSXEOF'
function App() {
  return (
    <div className="min-h-screen bg-gray-50 flex items-center justify-center">
      <div className="text-center">
        <h1 className="text-4xl font-bold text-gray-900">Hello</h1>
        <p className="mt-2 text-gray-600">Edit src/App.jsx to get started.</p>
      </div>
    </div>
  )
}

export default App
JSXEOF

# Clean up default Vite assets we don't need
rm -f src/App.css public/vite.svg src/assets/react.svg 2>/dev/null

# ─────────────────────────────────────────────
#  Git — init + initial commit
# ─────────────────────────────────────────────
echo "→ Initializing git..."

git init
git add -A
git commit -m "initial scaffold"

# ─────────────────────────────────────────────
#  Done
# ─────────────────────────────────────────────
echo ""
echo "  ┌──────────────────────────────────────────────────┐"
echo "  │  ✓ Project '$NAME' is ready                      "
echo "  │                                                   "
echo "  │  Backend:                                         "
echo "  │    cd $NAME/backend && go run ./cmd/server        "
echo "  │                                                   "
echo "  │  Frontend:                                        "
echo "  │    cd $NAME && npm run dev                        "
echo "  │                                                   "
echo "  │  Migrations:                                      "
echo "  │    cd $NAME && go run ./database/                 "
echo "  │    go run ./database/ --status                    "
echo "  │    go run ./database/ --reset                     "
echo "  │    go run ./database/ --env dev                   "
echo "  │                                                   "
echo "  │  Connect to GitHub:                               "
echo "  │    git remote add origin <your-repo-url>          "
echo "  │    git push -u origin main                        "
echo "  └──────────────────────────────────────────────────┘"
echo ""
