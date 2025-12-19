defmodule VibeSeaterWeb.PageController do
  use VibeSeaterWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
