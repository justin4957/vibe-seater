# Vibe Seater

Multi-dimensional stream overlay aggregator with persistent digital traces - synchronize live streams with multi-source commentary from social media, GitHub, Discord, and more.

## Vision

Vibe Seater enables a new way to experience live content by creating **time-synchronized overlays** of multiple data sources. Watch a news livestream while seeing what people are saying on Twitter, what's happening on related GitHub repositories, and discussions in Discord channels - all perfectly synchronized and replayable.

### Core Capabilities

- **Live Stream Aggregation**: Capture and monitor live streams from various sources (YouTube, Twitch, news outlets)
- **Multi-Source Overlays**: Aggregate data from:
  - Twitter/X feeds and hashtags
  - GitHub repository activity (commits, issues, PRs)
  - Discord channels
  - Reddit threads
  - TikTok hashtags
  - RSS feeds
  - Custom sources
- **Time Synchronization**: All events are timestamped and synchronized with the stream timeline
- **Persistent Replay**: Recorded streams can be replayed with synchronized commentary appearing at the exact moment it occurred
- **Multi-Dimensional Analysis**: View multiple perspectives on live events as they unfold across different platforms
- **Multi-User Collaboration**: Support for collaborative viewing and overlay creation

## Architecture

### Tech Stack

- **Backend**: Elixir/Phoenix with OTP for concurrent stream coordination
- **Frontend**: Phoenix LiveView for real-time UI updates
- **Database**: PostgreSQL with TimescaleDB extension for efficient time-series queries
- **Real-time**: Phoenix PubSub for live event broadcasting

### Core Domain

#### Streams
Represents a live stream being monitored. Contains:
- Stream URL and metadata
- Type (YouTube, Twitch, news, custom)
- Status (inactive, active, paused, completed)
- Temporal boundaries (started_at, ended_at)

#### Sources
Represents a data source that can be overlaid with streams:
- Source type (Twitter, GitHub, Discord, etc.)
- Configuration (hashtags, usernames, repo URLs)
- Active status

#### Events
Time-series data stored in a TimescaleDB hypertable:
- Event content from various sources
- Precise timestamps (occurred_at, ingested_at)
- Source and stream relationships
- External references and metadata

#### Stream-Source Relationships
Many-to-many relationships tracking which sources are monitored for each stream, with temporal tracking.

### Time-Series Architecture

Events are stored in a **TimescaleDB hypertable**, providing:
- Efficient time-range queries for replay
- Automatic data partitioning by time
- Optimized indexing for temporal operations
- Compression and retention policies

Key query patterns:
```elixir
# Get events for playback position
Events.get_synchronized_events(stream, playback_seconds, window_seconds)

# Get events in time range
Events.list_events_for_stream_in_range(stream, start_time, end_time)

# Stream statistics by source
Events.get_stream_statistics(stream)
```

## Getting Started

### Prerequisites

- Elixir 1.15+ and Erlang/OTP 26+
- PostgreSQL 14+ with TimescaleDB extension
- Node.js 18+ (for asset compilation)

### Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/justin4957/vibe-seater.git
   cd vibe-seater
   ```

2. Install dependencies:
   ```bash
   mix deps.get
   ```

3. Install TimescaleDB extension in PostgreSQL:
   ```bash
   # On macOS with Homebrew
   brew install timescaledb

   # Enable the extension
   psql -d postgres -c "CREATE EXTENSION IF NOT EXISTS timescaledb;"
   ```

4. Configure your database in `config/dev.exs`:
   ```elixir
   config :vibe_seater, VibeSeater.Repo,
     username: "postgres",
     password: "postgres",
     hostname: "localhost",
     database: "vibe_seater_dev"
   ```

5. Create and migrate the database:
   ```bash
   mix ecto.setup
   ```

6. Start the Phoenix server:
   ```bash
   mix phx.server
   ```

Visit [`localhost:4000`](http://localhost:4000) in your browser.

## Usage Example

### Creating a Stream with Sources

```elixir
# Create a stream
{:ok, stream} = Streaming.create_stream(%{
  title: "Presidential Debate 2024",
  stream_url: "https://youtube.com/watch?v=...",
  stream_type: "youtube"
})

# Create sources
{:ok, twitter_source} = Sources.create_source(%{
  name: "Debate Tweets",
  source_type: "twitter",
  config: %{"hashtag" => "#debate2024"}
})

{:ok, github_source} = Sources.create_source(%{
  name: "Fact-Check Repo",
  source_type: "github",
  config: %{"repo" => "factcheck/debate-2024"}
})

# Attach sources to stream
Streaming.attach_source(stream, twitter_source)
Streaming.attach_source(stream, github_source)

# Start the stream
Streaming.start_stream(stream)
```

### Replay with Synchronized Events

```elixir
# Get events at specific playback position (5 minutes in)
events = Events.get_synchronized_events(stream, 300, window_seconds: 5)

# Each event includes source info and precise timing
Enum.each(events, fn event ->
  IO.puts("#{event.source.name}: #{event.content}")
end)
```

## Development Roadmap

### Phase 1: Core Infrastructure (Current)
- [x] Database schema with TimescaleDB
- [x] Core domain contexts (Streams, Sources, Events)
- [x] Basic LiveView interface
- [ ] Stream ingestion pipeline
- [ ] Source adapters (Twitter, GitHub, etc.)

### Phase 2: Real-time Streaming
- [ ] Live event ingestion workers
- [ ] WebSocket event broadcasting
- [ ] Stream synchronization engine
- [ ] Event ticker component

### Phase 3: Replay & Analysis
- [ ] Stream recording and storage
- [ ] Playback controls with event overlay
- [ ] Timeline visualization
- [ ] Export capabilities

### Phase 4: Multi-User & Collaboration
- [ ] User authentication
- [ ] Collaborative stream sessions
- [ ] Shared annotations
- [ ] Permission management

## Contributing

We welcome contributions! Areas of interest:
- Source adapters for new platforms
- Stream ingestion improvements
- UI/UX enhancements
- Performance optimizations

## License

MIT License - see LICENSE file for details

## Learn More

- [Phoenix Framework](https://www.phoenixframework.org/)
- [TimescaleDB](https://www.timescale.com/)
- [Phoenix LiveView](https://hexdocs.pm/phoenix_live_view/)
