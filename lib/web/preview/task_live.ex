defmodule Bonfire.Divlab.Web.Preview.TaskLive do
  @moduledoc "A task in a feed (D8e in tasks-v1.md): its title, description, owner, date and whether it's done, linking to its group's Tasks page until tasks have a page of their own."
  use Bonfire.UI.Common.Web, :stateless_component

  alias Bonfire.Divlab.Web.TaskRowLive

  prop object, :any
  prop activity_component_id, :any, default: nil
  prop activity, :any, default: nil
  prop viewing_main_object, :boolean, default: false
  prop showing_within, :atom, default: nil
  prop cw, :boolean, default: nil
  prop is_remote, :boolean, default: false
  prop thread_title, :any, default: nil
  prop hide_actions, :boolean, default: false
  prop activity_inception, :boolean, default: false
  prop permalink, :string, default: nil

  @doc "What the feed preloads for each task (`Bonfire.Social.Feeds.LiveHandler.object_preloads/1`): its creator, whom the activity's author line shows, and its owner."
  def preloads, do: [creator: [:profile, :character], provider: [:profile, :character]]

  def render(assigns) do
    assigns
    |> assign(
      done?: e(assigns.object, :finished, false) == true,
      tasks_path: tasks_path(assigns.object)
    )
    |> render_sface()
  end

  # `path/1` caches the pointer lookup, so a feed of tasks from one group looks the group up once
  defp tasks_path(%{context_id: context_id}) when is_binary(context_id) do
    case path(context_id) do
      group_path when is_binary(group_path) -> group_path <> "/tasks"
      _ -> nil
    end
  end

  defp tasks_path(_object), do: nil
end
