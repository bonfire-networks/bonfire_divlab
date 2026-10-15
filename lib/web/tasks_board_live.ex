defmodule Bonfire.Divlab.Web.TasksBoardLive do
  @moduledoc """
  The views of a group's tasks on its Tasks page, and their rows (D8b and D9 in tasks-v1.md). It loads the four views of open tasks, so each tab can show its count, and Done only on its own tab; `Bonfire.Divlab.LiveHandler` reloads them after every row action, since a task can leave one view and enter another.
  """
  use Bonfire.UI.Common.Web, :stateful_component

  alias Bonfire.Divlab.Tasks
  alias Bonfire.Divlab.Web.CreateTaskLive

  prop category, :any, required: true
  prop view, :atom, default: :mine

  data lists, :map, default: %{}
  data deletable, :any, default: MapSet.new()
  data members, :list, default: []
  data members_of, :any, default: nil

  @doc "The views in tab order, with the path segment each has under `/&group/tasks`."
  def views,
    do: [inbox: "inbox", mine: "mine", waiting: "waiting", due_soon: "due-soon", done: "done"]

  @doc """
  The view a path segment names, or Mine, the day-to-day list (D8a), when it names none.

      iex> Bonfire.Divlab.Web.TasksBoardLive.view_for("due-soon")
      :due_soon

      iex> Bonfire.Divlab.Web.TasksBoardLive.view_for(nil)
      :mine
  """
  def view_for(slug),
    do: Enum.find_value(views(), :mine, fn {view, view_slug} -> view_slug == slug && view end)

  # the members, for every row's Assign…, are only looked up when the group changes
  def update(assigns, socket) do
    socket = assign(socket, assigns)
    group = socket.assigns.category

    socket =
      if socket.assigns.members_of == id(group),
        do: socket,
        else:
          assign(socket,
            members:
              group
              |> CreateTaskLive.members(socket.assigns[:__context__])
              # the viewer first, since taking a task is the most common assignment
              |> Enum.sort_by(&(&1.id != current_user_id(socket.assigns[:__context__]))),
            members_of: id(group)
          )

    {:ok, load(socket)}
  end

  @doc "Loads the four views of open tasks, and Done when it's the one shown, with each task's owner, and which tasks the current user may delete."
  def load(socket) do
    me = current_user(socket)
    group_id = id(socket.assigns.category)

    lists =
      views()
      |> Keyword.keys()
      # Done has no count, so it's only loaded on its own tab (D9a)
      |> Enum.filter(&(&1 != :done or socket.assigns.view == :done))
      |> Map.new(fn view ->
        {:ok, tasks} = Tasks.list(view, group_id, current_user: me)
        {view, tasks}
      end)

    # a task can be in several views, so each is loaded with its owner once for all of them
    tasks =
      lists
      |> Map.values()
      |> List.flatten()
      |> Enum.uniq_by(& &1.id)
      |> repo().maybe_preload(provider: [:profile, :character])
      |> Map.new(&{&1.id, &1})

    assign(socket,
      lists: Map.new(lists, fn {view, view_tasks} -> {view, Enum.map(view_tasks, &tasks[&1.id])} end),
      deletable: for({id, task} <- tasks, Tasks.may_delete?(me, task), into: MapSet.new(), do: id)
    )
  end

  defp view_label(:inbox), do: l("Inbox")
  defp view_label(:mine), do: l("Mine")
  defp view_label(:waiting), do: l("Waiting on")
  defp view_label(:due_soon), do: l("Due soon")
  defp view_label(:done), do: l("Done")

  defp empty_message(:inbox), do: l("Nothing in the Inbox: every open task has an owner.")
  defp empty_message(:mine), do: l("You have no open tasks in this group.")
  defp empty_message(:waiting), do: l("You're not waiting on anyone.")
  defp empty_message(:due_soon), do: l("Nothing is due in the next 7 days.")
  defp empty_message(:done), do: l("No finished tasks yet.")
end
