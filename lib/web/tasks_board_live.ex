defmodule Bonfire.Divlab.Web.TasksBoardLive do
  @moduledoc """
  The views of a group's tasks on its Tasks page, and their rows (D8b and D9 in tasks-v1.md). It loads the group's lists, the three views of open tasks, so each tab can show its count, and Done only on its own tab; `Bonfire.Divlab.LiveHandler` reloads them after every row action, since a task can leave one view and enter another.
  """
  use Bonfire.UI.Common.Web, :stateful_component

  alias Bonfire.Classify.Categories
  alias Bonfire.Divlab.Tasks

  prop category, :any, required: true
  prop view, :atom, default: :lists

  data lists, :map, default: %{}
  # the group's lists (Processes), for the Lists view, and how far along each is
  data task_lists, :list, default: []
  data progress, :map, default: %{}
  data deletable, :any, default: MapSet.new()
  data members, :list, default: []
  data members_of, :any, default: nil

  @doc "The views in tab order; each is also its path segment under `/&group/tasks`."
  def views, do: [:lists, :inbox, :mine, :waiting, :done]

  @doc """
  The view a path segment names, or Lists when it names none: people see the group's lists first, not a pile of items (tasks-v2 §1).

      iex> Bonfire.Divlab.Web.TasksBoardLive.view_for("waiting")
      :waiting

      iex> Bonfire.Divlab.Web.TasksBoardLive.view_for(nil)
      :lists
  """
  def view_for(slug),
    do: Enum.find(views(), :lists, &(to_string(&1) == slug))

  # the members, for every row's Assign…, are only looked up when the group changes
  def update(assigns, socket) do
    socket = assign(socket, assigns)
    group = socket.assigns.category

    socket =
      if socket.assigns.members_of == id(group),
        do: socket,
        else:
          socket
          # the composer runs in its own LiveView, so it tells this page through the group's topic when it adds tasks (`Bonfire.Divlab.LiveHandler`'s `create_tasks`); a component runs in its page's process, so this subscribes the page
          |> tap(&Bonfire.Common.PubSub.subscribe(tasks_topic(id(group)), &1))
          |> assign(
            members:
              group
              |> members(socket.assigns[:__context__])
              # the viewer first, since taking a task is the most common assignment
              |> Enum.sort_by(fn {_label, %{id: id}} -> id != current_user_id(socket.assigns[:__context__]) end),
            members_of: id(group)
          )

    {:ok, load(socket)}
  end

  @doc "The PubSub topic on which a group's Tasks page hears that tasks were added elsewhere, such as from the composer."
  def tasks_topic(group_id), do: "bonfire_divlab_tasks:#{group_id}"

  @doc "Loads the views of open tasks, and Done when it's the one shown, with each task's owner, and which tasks the current user may delete."
  def load(socket) do
    me = current_user(socket)
    group_id = id(socket.assigns.category)

    lists =
      views()
      # Lists are Processes, loaded below; Done has no count, so it's only loaded on its own tab (D9a)
      |> Enum.filter(&(&1 != :lists and (&1 != :done or socket.assigns.view == :done)))
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
      # the list each task is in, which its row names (tasks-v2 §1)
      |> repo().maybe_preload(provider: [:profile, :character], input_of: [])
      |> Map.new(&{&1.id, &1})

    # the lists for the Lists tab's count; their progress only where it shows
    {:ok, task_lists} = Tasks.lists(group_id, current_user: me)

    assign(socket,
      task_lists: task_lists,
      progress:
        if(socket.assigns.view == :lists,
          do: Tasks.progress(Enum.map(task_lists, & &1.id), current_user: me),
          else: %{}
        ),
      lists:
        Map.new(lists, fn {view, view_tasks} -> {view, Enum.map(view_tasks, &tasks[&1.id])} end),
      deletable: Tasks.deletable(me, Map.values(tasks))
    )
  end

  # a list row's "2 of 5 done", from the one count query of `load/1`
  defp list_progress(progress, list) do
    {done, total} = Map.get(progress, id(list), {0, 0})
    Bonfire.Divlab.Web.Preview.ListLive.progress_label(done, total)
  end

  defp view_label(:lists), do: l("Lists")
  defp view_label(:inbox), do: l("Inbox")
  defp view_label(:mine), do: l("Mine")
  defp view_label(:waiting), do: l("Waiting on")
  defp view_label(:done), do: l("Done")

  defp empty_message(:lists), do: l("No lists yet: Add tasks, then pick New list.")
  defp empty_message(:inbox), do: l("Nothing in the Inbox: every open task has an owner.")
  defp empty_message(:mine), do: l("You have no open tasks in this group.")
  defp empty_message(:waiting), do: l("You're not waiting on anyone.")
  defp empty_message(:done), do: l("No finished tasks yet.")

  @doc "The first 100 members of `group`, as the owner menus' `LiveSelect` options: the shape the picker's search gives (`Bonfire.UI.Boundaries.SetBoundariesLive.results_for_multiselect/1`), built once per page rather than per row."
  def members(nil, _context), do: []

  def members(group, context) do
    group
    |> Categories.list_members(current_user: current_user(context), pagination: [limit: 100])
    |> e(:edges, [])
    |> Bonfire.UI.Boundaries.SetBoundariesLive.results_for_multiselect()
  end
end
