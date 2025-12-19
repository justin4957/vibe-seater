defmodule VibeSeater.Streaming.Stream do
  @moduledoc """
  Represents a live stream being monitored and overlaid with multi-source data.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @stream_types ~w(youtube twitch news custom)
  @statuses ~w(inactive active paused completed)

  schema "streams" do
    field(:title, :string)
    field(:stream_url, :string)
    field(:stream_type, :string)
    field(:status, :string, default: "inactive")
    field(:started_at, :utc_datetime_usec)
    field(:ended_at, :utc_datetime_usec)
    field(:metadata, :map, default: %{})

    many_to_many(:sources, VibeSeater.Sources.Source,
      join_through: VibeSeater.Streaming.StreamSource
    )

    has_many(:stream_sources, VibeSeater.Streaming.StreamSource)
    has_many(:events, VibeSeater.Events.Event)

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(stream, attrs) do
    stream
    |> cast(attrs, [:title, :stream_url, :stream_type, :status, :started_at, :ended_at, :metadata])
    |> validate_required([:title, :stream_url, :stream_type])
    |> validate_inclusion(:stream_type, @stream_types)
    |> validate_inclusion(:status, @statuses)
    |> validate_url(:stream_url)
  end

  defp validate_url(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      uri = URI.parse(value)

      case uri do
        %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and not is_nil(host) ->
          []

        _ ->
          [{field, "must be a valid URL"}]
      end
    end)
  end
end
