# Recall

Privacy-first, on-device semantic search and chat over your personal content (emails, messages, documents, and notes). Recall embeds your data locally using a Core ML sentence-transformer and stores vectors in SQLite with the sqlite-vec extension. A local assistant (Apple Intelligence Foundation Models) uses tools to search, cite sources, and expand full threads.


## [Check out a demo!](https://www.linkedin.com/posts/mordecaim_i-recently-built-a-personal-ai-assistant-activity-7358489394686611457-vLY9?utm_source=share&utm_medium=member_desktop&rcm=ACoAADRxJy8BuW_A9tIfzNPTadCH1Ksx3ZCEwr0)

### [And the blog post!](https://blog.m16b.com/posts/recall/)

## Highlights
- On-device embeddings with Core ML (`all-MiniLM-L6-v2`, 384 dims)
- Vector search via SQLite + `sqlite-vec` (no server)
- Semantic chunking of threads with overlap for recall accuracy
- Chat UI powered by Foundation Models tools: semantic search + full-thread retrieval
- Import and browse content; view original context with citations

## Tech Stack
- Swift, SwiftUI
- Core ML (Sentence-Transformers `all-MiniLM-L6-v2.mlpackage`)
- SQLite3 + `sqlite-vec` C extension (compiled and loaded in-app)
- Apple Foundation Models (`FoundationModels` framework) and Tools API
- Concurrency: Swift Concurrency (`Task`, `TaskGroup`)

## Architecture
- `EmbeddingService` (`sqlite/Services/EmbeddingService.swift`)
  - BERT-style tokenizer (WordPiece) using bundled `vocab.txt`
  - Encodes text to 384-dim embeddings via Core ML model class `all_MiniLM_L6_v2`
  - Thread chunking: 512-token window with configurable overlap; stores start/end character positions per chunk
- `SQLiteService` (`sqlite/Services/SQLiteService.swift`)
  - Opens database at `Documents/knowledge_base.sqlite` with WAL
  - Loads `sqlite-vec` via `sqlite3_vec_init` (bridged in `sqlite/sqlite-vec/`)
  - Schema for items (`Document`, `Email`, `Message`, `Note`), threads, and `Chunk` virtual table with `embedding float[384]`
  - Provides batch inserts and vector search (`embedding MATCH vec_f32(?)`)
- `ContentService` (`sqlite/Services/ContentService.swift`)
  - Single entry point for imports, reads, and semantic search
  - On import: inserts raw items → creates `Thread` aggregates → chunks + embeds → inserts `Chunk`
  - Search flow: query → embed → vector search → hydrate `SearchResult` (thread, items, distance)
- Tools (`sqlite/Tools/Tools.swift`)
  - `SemanticSearchTool` and `GetFullThreadTool` implement the Foundation Models `Tool` protocol
  - The chat model is prompted to chain tools: search → pull full thread when relevant
- UI (`sqlite/Views/...`)
  - Tabs: Chat (`HomeView`), Search, Library, Import
  - Chat shows tool usage chips and expandable source cards; opens content detail sheets

## Database
Location
- Path: `Documents/knowledge_base.sqlite` (see `sqlite/constants.swift` → `defaultDBPath`)
- Schema versioning: `schemaVersion` (UserDefaults) triggers drop-and-migrate on change

Schema (excerpt)
```sql
CREATE VIRTUAL TABLE IF NOT EXISTS Chunk USING vec0(
  id TEXT PRIMARY KEY,
  thread_id TEXT NOT NULL,
  parent_ids TEXT NOT NULL,
  type TEXT NOT NULL CHECK(content_type IN ('document','email','message','note')),
  chunk_index INTEGER,
  startPosition INTEGER,
  endPosition INTEGER,
  +content TEXT,
  embedding float[384]
);
```

Vector search (excerpt)
```sql
SELECT id, thread_id, distance
FROM Chunk
WHERE type IN (?,?,?)
  AND chunk_index = 0
  AND embedding MATCH vec_f32(?)
ORDER BY distance
LIMIT ?;
```

Notes
- Embedding dimension must match both the model and the `Chunk.embedding` column (defaults to 384)
- Chunking uses window 512 and default overlap 128 (see `ChunkingConfig`)

## Requirements
- Xcode 16+ (recommended)
- iOS 18 (device or simulator) or macOS 15 for development
- Foundation Models availability (Apple Intelligence) for the Chat tab
  - If not available, Chat shows status (e.g., device not eligible, not enabled, model not ready)

## Getting Started
1. Open `sqlite.xcodeproj` in Xcode.
2. Build and run on an iOS 18 device/simulator (or macOS 15 if targeting Mac).
3. On first launch, the app creates the database and loads the ML model and `sqlite-vec`.

## Usage
- Chat (recommended start)
  - Ask in natural language; the assistant may call `semanticSearch` and then `getFullThread`.
  - Tap “sources” to view citations; open a source to see details.
- Search
  - Run keyword/semantic searches directly; browse results and open details.
- Library
  - Browse all imported content by type.
- Import
  - Add Documents, Emails, Messages, and Notes using the Import tab.

## Data Flow
1. Import raw content → `Item`
2. Group by `threadId` → `Thread`
3. Chunk + embed (`EmbeddingService`) → `ThreadChunk`
4. Persist to SQLite/vec (`SQLiteService`)
5. Query: text → embed → `Chunk` vector search → hydrate `SearchResult` → UI
6. Chat: model tool-call(s) → results → optional full-thread expansion

## Testing
- Unit tests under `sqliteTests/`
- Run: Product → Test (⌘U) in Xcode

## Troubleshooting
- Foundation model unavailable
  - Ensure Apple Intelligence is enabled and device/simulator supports Foundation Models
- `vocab.txt` or ML model not found
  - Verify `sqlite/ML/all-MiniLM-L6-v2.mlpackage` and `sqlite/ML/vocab.txt` are included in the app bundle
- `sqlite-vec` init fails
  - Confirm bridged headers in `sqlite/sqlite-vec/` are compiled and `sqlite3_vec_init` succeeds on startup
- DB reset on launch
  - `schemaVersion` changed; the app intentionally migrates by recreating the DB when versions differ

## Configuration
- Embedding dims: set in `EmbeddingService.embeddingDimensions` and passed to `SQLiteService`
- DB path and schema version: `sqlite/constants.swift`
- Chunking overlap: `ChunkingConfig(overlapSize: 128)`

## Privacy
- All data, embeddings, and search run locally on-device. No network calls are performed by the app.

## Folder Guide
- `sqlite/Services/` core services (content, embeddings, database)
- `sqlite/Models/` data models (`Item`, `Thread`, `Email`, `Message`, `Note`, `SearchResult`)
- `sqlite/Tools/` Foundation Models tools (`SemanticSearchTool`, `GetFullThreadTool`)
- `sqlite/Views/` SwiftUI views (Chat, Search, Library, Import)
- `sqlite/ML/` Core ML model + tokenizer vocab
- `sqlite/sqlite-vec/` bundled `sqlite-vec` extension sources and bridging

---

If you run into issues, open the Debug console in Xcode; services print helpful messages during DB setup, inserts, and tool calls.
