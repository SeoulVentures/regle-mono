# Repository Guidelines

## Project Structure & Module Organization
This workspace is a multi-project repository. Each top-level app is largely self-contained and often has its own `.git` history.

- `regle-mcp-server/`: Bun + TypeScript MCP server (`src/`, builds to `dist/`).
- `tm-regle.kr/` and `regle-co-kr/`: Vite + Vue frontends (`src/`, static assets in `public/` when present).
- `review-moai-refactoring/`: Python review pipeline and API (`regle/`, `tests/`, `lambda-api/`).
- `SeoulVenturesGroupware/`, `sv-nova-master/`: larger legacy/production apps with their own conventions.
- Root JSON/log files are operational artifacts; avoid modifying them unless required.

When in doubt, work inside the relevant project directory and check its local config files first.

## Build, Test, and Development Commands
Run commands from the target project directory.

- MCP server (`regle-mcp-server/`): `bun run dev` (watch mode), `bun run typecheck` (`tsc --noEmit`), `bun run lint` (ESLint on `src/`).
- Vue apps (`tm-regle.kr/`, `regle-co-kr/`): `npm run dev` (Vite dev server), `npm run build` (production build; includes `vue-tsc` in `tm-regle.kr/`).
- Python pipeline (`review-moai-refactoring/`): `pytest` (tests from `pytest.ini`), `python -m regle.<module>` (run modules directly).

## Coding Style & Naming Conventions
Follow the tooling already configured per project.

- TypeScript/Bun: prefer explicit types, small modules, and named exports. Use `eslint` and `tsc`.
- Vue: components in `PascalCase.vue`; composables like `useThing.ts`.
- Python: format with `black` (line length 120) and sort imports with `isort`; lint with `ruff`.

## Testing Guidelines
- Python tests live in `review-moai-refactoring/tests/` and follow `test_*.py` (see `pytest.ini`).
- Frontend and MCP-server testing is lighter; add focused unit tests where a framework already exists, and at minimum run lint/typecheck before submitting changes.

## Commit & Pull Request Guidelines
Multiple subprojects use Conventional Commit prefixes in history (for example: `feat:`, `fix:`, `chore:` with optional scopes like `feat(oauth): ...`).

- Prefer: `type(scope): concise summary`.
- Keep commits scoped to a single project directory.
- PRs should include: purpose, affected directories, how to run/verify, and any required env vars or migrations.

## Agent-Specific Instructions
- Treat each top-level directory as its own project and avoid cross-project refactors unless explicitly requested.
- Never run destructive Git commands at the workspace root; use project-local Git history instead.
- Default to Korean for all user-facing responses in this repository.
- Do not reveal private chain-of-thought; provide concise Korean summaries of reasoning, key assumptions, and next steps instead.
