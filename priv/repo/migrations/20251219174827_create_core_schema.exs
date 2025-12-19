defmodule VibeSeater.Repo.Migrations.CreateCoreSchema do
  use Ecto.Migration

  def change do
    # Streams table - represents live streams being monitored
    create table(:streams, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:title, :string, null: false)
      add(:stream_url, :text, null: false)
      add(:stream_type, :string, null: false)
      add(:status, :string, default: "inactive")
      add(:started_at, :utc_datetime_usec)
      add(:ended_at, :utc_datetime_usec)
      add(:metadata, :map, default: %{})

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:streams, [:status]))
    create(index(:streams, [:started_at]))

    # Sources table - represents different data sources
    create table(:sources, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:name, :string, null: false)
      add(:source_type, :string, null: false)
      add(:source_url, :text)
      add(:config, :map, default: %{})
      add(:active, :boolean, default: true)

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:sources, [:source_type]))
    create(index(:sources, [:active]))

    # Stream sources - many-to-many relationship
    create table(:stream_sources, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:stream_id, references(:streams, type: :uuid, on_delete: :delete_all), null: false)
      add(:source_id, references(:sources, type: :uuid, on_delete: :delete_all), null: false)
      add(:started_at, :utc_datetime_usec, null: false)
      add(:ended_at, :utc_datetime_usec)

      timestamps(type: :utc_datetime_usec)
    end

    create(index(:stream_sources, [:stream_id]))
    create(index(:stream_sources, [:source_id]))
    create(unique_index(:stream_sources, [:stream_id, :source_id]))

    # Events table - time-series data for all events
    create table(:events, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:stream_id, references(:streams, type: :uuid, on_delete: :delete_all), null: false)
      add(:source_id, references(:sources, type: :uuid, on_delete: :delete_all), null: false)
      add(:event_type, :string, null: false)
      add(:content, :text)
      add(:author, :string)
      add(:external_id, :string)
      add(:external_url, :text)
      add(:metadata, :map, default: %{})
      add(:occurred_at, :utc_datetime_usec, null: false)
      add(:ingested_at, :utc_datetime_usec, null: false)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # Convert events to TimescaleDB hypertable
    execute(
      "SELECT create_hypertable('events', 'occurred_at', chunk_time_interval => INTERVAL '1 day')",
      ""
    )

    create(index(:events, [:stream_id, :occurred_at]))
    create(index(:events, [:source_id, :occurred_at]))
    create(index(:events, [:event_type]))
    create(index(:events, [:external_id]))
  end
end
