defmodule VibeSeater.Streaming do
  @moduledoc """
  The Streaming context manages live streams and their relationships with data sources.
  """

  import Ecto.Query, warn: false
  alias VibeSeater.Repo
  alias VibeSeater.Streaming.{Stream, StreamSource}
  alias VibeSeater.Sources.Source

  @doc """
  Returns the list of streams.
  """
  def list_streams do
    Repo.all(Stream)
  end

  @doc """
  Gets a single stream.
  """
  def get_stream!(id), do: Repo.get!(Stream, id)

  @doc """
  Gets a stream with preloaded sources.
  """
  def get_stream_with_sources!(id) do
    Stream
    |> where([s], s.id == ^id)
    |> preload(:sources)
    |> Repo.one!()
  end

  @doc """
  Creates a stream.
  """
  def create_stream(attrs \\ %{}) do
    %Stream{}
    |> Stream.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a stream.
  """
  def update_stream(%Stream{} = stream, attrs) do
    stream
    |> Stream.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a stream.
  """
  def delete_stream(%Stream{} = stream) do
    Repo.delete(stream)
  end

  @doc """
  Starts a stream, setting its status to active and recording the start time.
  """
  def start_stream(%Stream{} = stream) do
    update_stream(stream, %{
      status: "active",
      started_at: DateTime.utc_now()
    })
  end

  @doc """
  Stops a stream, setting its status to completed and recording the end time.
  """
  def stop_stream(%Stream{} = stream) do
    update_stream(stream, %{
      status: "completed",
      ended_at: DateTime.utc_now()
    })
  end

  @doc """
  Attaches a source to a stream.
  """
  def attach_source(%Stream{} = stream, %Source{} = source) do
    %StreamSource{}
    |> StreamSource.changeset(%{
      stream_id: stream.id,
      source_id: source.id,
      started_at: DateTime.utc_now()
    })
    |> Repo.insert()
  end

  @doc """
  Detaches a source from a stream.
  """
  def detach_source(%Stream{} = stream, %Source{} = source) do
    StreamSource
    |> where([ss], ss.stream_id == ^stream.id and ss.source_id == ^source.id)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      stream_source -> Repo.delete(stream_source)
    end
  end

  @doc """
  Lists all active streams.
  """
  def list_active_streams do
    Stream
    |> where([s], s.status == "active")
    |> preload(:sources)
    |> Repo.all()
  end
end
