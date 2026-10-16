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
  # `ActivityLive` passes what the activity is shown within (eg. `"preview"`), not a boolean
  prop activity_inception, :any, default: nil
  prop permalink, :string, default: nil

  @doc "What the feed preloads for each task (`Bonfire.Social.Feeds.LiveHandler.object_preloads/1`): its creator, whom the activity's author line shows, and its owner."
  def preloads, do: [creator: [:profile, :character], provider: [:profile, :character]]

  def render(assigns) do
    assigns
    |> assign(
      done?: e(assigns.object, :finished, false) == true,
      # above a reply or inside a quote the task is context, so only its title shows; a thread (and the preview modal's) shows it in full
      compact?:
        !!assigns.activity_inception and !assigns.viewing_main_object and
          assigns.showing_within != :thread,
      tasks_path: tasks_path(assigns.object)
    )
    |> render_sface()
  end

  @doc """
  What the card says about who does `task`: you, its owner, or nobody yet. A finished task with no owner says nothing.

      iex> Bonfire.Divlab.Web.Preview.TaskLive.owner_label(%{provider: %{id: "u1", profile: %{name: "Mayel"}}}, "u2")
      "Assigned to Mayel"

      iex> Bonfire.Divlab.Web.Preview.TaskLive.owner_label(%{provider: %{id: "u1", profile: %{name: "Mayel"}}}, "u1")
      "Assigned to you"

      iex> Bonfire.Divlab.Web.Preview.TaskLive.owner_label(%{provider: nil, finished: false}, "u1")
      "Unassigned"

      iex> Bonfire.Divlab.Web.Preview.TaskLive.owner_label(%{provider: nil, finished: true}, "u1")
      nil
  """
  def owner_label(task, viewer_id) do
    case TaskRowLive.owner_name(task) do
      nil ->
        if e(task, :finished, false) != true, do: l("Unassigned")

      name ->
        if id(task.provider) == viewer_id,
          do: l("Assigned to you"),
          else: l("Assigned to %{name}", name: name)
    end
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
