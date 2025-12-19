defmodule VibeSeaterWeb.StreamLive.Index do
  @moduledoc """
  LiveView for listing and managing streams.
  """
  use VibeSeaterWeb, :live_view

  alias VibeSeater.Streaming

  @impl true
  def mount(_params, _session, socket) do
    streams = Streaming.list_streams()
    {:ok, assign(socket, streams: streams)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Vibe Seater - Streams")
  end

  defp status_color("active"), do: "bg-green-100 text-green-800"
  defp status_color("inactive"), do: "bg-gray-100 text-gray-800"
  defp status_color("paused"), do: "bg-yellow-100 text-yellow-800"
  defp status_color("completed"), do: "bg-blue-100 text-blue-800"
  defp status_color(_), do: "bg-gray-100 text-gray-800"
end
