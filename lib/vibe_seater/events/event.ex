defmodule VibeSeater.Events.Event do
  @moduledoc """
  Represents a time-series event from a source, synchronized with a stream.
  Stored in a TimescaleDB hypertable for efficient time-based queries.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @event_types ~w(tweet github_commit github_issue discord_message reddit_comment tiktok_video facebook_post rss_item custom)

  schema "events" do
    field(:event_type, :string)
    field(:content, :string)
    field(:author, :string)
    field(:external_id, :string)
    field(:external_url, :string)
    field(:metadata, :map, default: %{})
    field(:occurred_at, :utc_datetime_usec)
    field(:ingested_at, :utc_datetime_usec)

    belongs_to(:stream, VibeSeater.Streaming.Stream)
    belongs_to(:source, VibeSeater.Sources.Source)

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :event_type,
      :content,
      :author,
      :external_id,
      :external_url,
      :metadata,
      :occurred_at,
      :ingested_at,
      :stream_id,
      :source_id
    ])
    |> validate_required([:event_type, :occurred_at, :ingested_at, :stream_id, :source_id])
    |> validate_inclusion(:event_type, @event_types)
    |> foreign_key_constraint(:stream_id)
    |> foreign_key_constraint(:source_id)
    |> set_ingested_at_default()
  end

  defp set_ingested_at_default(changeset) do
    case get_field(changeset, :ingested_at) do
      nil -> put_change(changeset, :ingested_at, DateTime.utc_now())
      _ -> changeset
    end
  end
end
