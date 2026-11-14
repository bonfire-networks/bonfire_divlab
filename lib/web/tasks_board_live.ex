defmodule Bonfire.Divlab.Web.TasksBoardLive do
  @moduledoc """
  The two views of a group's tasks on its Tasks page, Lists and My tasks, and their rows (D8b and D9 in tasks-v1.md; the Inbox, Waiting on and Done tabs went on 2026-11-13, for a page with less to choose from). It loads the group's lists and my open tasks, for both views' counts and each list's "N yours", and my done tasks only on My tasks; `Bonfire.Divlab.LiveHandler` reloads them after every row action, since a task can leave one view and enter another.
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
  # how many of my open tasks each list holds, for its card's "N yours"
  data mine_by_list, :map, default: %{}
  data deletable, :any, default: MapSet.new()
  data members, :list, default: []
  data members_of, :any, default: nil

  @doc "The views in tab order; each is also its path segment under `/&group/tasks`."
  def views, do: [:lists, :mine]

  @doc """
  The view a path segment names, or Lists when it names none: people see the group's lists first, not a pile of items (tasks-v2 §1).

      iex> Bonfire.Divlab.Web.TasksBoardLive.view_for("mine")
      :mine

      iex> Bonfire.Divlab.Web.TasksBoardLive.view_for("inbox")
      :lists

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
              |> Enum.sort_by(fn {_label, %{id: id}} ->
                id != current_user_id(socket.assigns[:__context__])
              end),
            members_of: id(group)
          )

    {:ok, load(socket)}
  end

  @doc "The PubSub topic on which a group's Tasks page hears that tasks were added elsewhere, such as from the composer."
  def tasks_topic(group_id), do: "bonfire_divlab_tasks:#{group_id}"

  @doc "Loads my open tasks, and on My tasks my done ones, on Lists the open tasks nobody has that are in no list, with each task's owner and list, the group's lists and the progress the view shows, and which tasks the current user may delete."
  def load(socket) do
    me = current_user(socket)
    group_id = id(socket.assigns.category)
    view = socket.assigns.view

    lists =
      # Lists are Processes, loaded below; my done tasks have no count, so they're only loaded where they show (D9a)
      if(view == :mine, do: [:mine, :mine_done], else: [:mine, :inbox])
      |> Map.new(fn view ->
        {:ok, tasks} = Tasks.list(view, group_id, current_user: me)
        {view, tasks}
      end)
      # of the Inbox, only the tasks from before every task had a list: no list page shows them (tasks-v2 §15)
      |> then(fn lists ->
        case Map.pop(lists, :inbox) do
          {nil, lists} -> lists
          {inbox, lists} -> Map.put(lists, :loose, Enum.filter(inbox, &is_nil(&1.input_of_id)))
        end
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

    {:ok, task_lists} = Tasks.lists(group_id, current_user: me)
    mine_by_list = Enum.frequencies_by(lists[:mine], & &1.input_of_id)

    assign(socket,
      task_lists: task_lists,
      mine_by_list: mine_by_list,
      # every card's progress on Lists; on My tasks only the lists heading my tasks
      progress:
        task_lists
        |> Enum.map(& &1.id)
        |> then(&if(view == :mine, do: Enum.filter(&1, fn id -> mine_by_list[id] end), else: &1))
        |> Tasks.progress(current_user: me),
      lists:
        Map.new(lists, fn {view, view_tasks} -> {view, Enum.map(view_tasks, &tasks[&1.id])} end),
      deletable: Tasks.deletable(me, Map.values(tasks))
    )
  end

  # a list's `{done, total}`, from the one count query of `load/1`
  defp counts(progress, list), do: Map.get(progress, id(list), {0, 0})

  # a list card's "2 of 5 done"
  defp list_progress(progress, list) do
    {done, total} = counts(progress, list)
    Bonfire.Divlab.Web.Preview.ListLive.progress_label(done, total)
  end

  defp complete?(progress, list), do: match?({done, done} when done > 0, counts(progress, list))

  # My tasks under the list each is in, in the lists' order; tasks in no list, or in one I can't see, come last under no name, so none goes missing
  defp by_list(tasks, task_lists) do
    shown = MapSet.new(task_lists, & &1.id)

    groups =
      Enum.group_by(tasks, &if(MapSet.member?(shown, &1.input_of_id), do: &1.input_of_id))

    (Enum.map(task_lists, &{&1, Map.get(groups, id(&1), [])}) ++
       [{nil, Map.get(groups, nil, [])}])
    |> Enum.reject(fn {_list, tasks} -> tasks == [] end)
  end

  # `Tasks.list(:mine_done, …)` stops at its latest 50, which the count says
  defp done_count(done) when length(done) >= 50, do: "50+"
  defp done_count(done), do: length(done)

  defp view_label(:lists), do: l("Lists")
  defp view_label(:mine), do: l("My tasks")

  # the open lists, as the switch counts them; closed ones sit apart
  defp view_count(:lists, task_lists, _lists), do: Enum.count(task_lists, &(!&1.finished))
  defp view_count(:mine, _task_lists, lists), do: length(lists[:mine] || [])

  # the open lists, then the closed ones under their own heading, leaving out an empty group
  defp open_and_closed(task_lists) do
    {closed, open} = Enum.split_with(task_lists, & &1.finished)
    Enum.reject([{open, false}, {closed, true}], &match?({[], _}, &1))
  end

  defp empty_message(:lists), do: l("No lists yet: Add tasks, then pick New list.")
  defp empty_message(:mine), do: l("You have no open tasks in this group.")

  @doc "The first 100 members of `group`, as the owner menus' `LiveSelect` options: the shape the picker's search gives (`Bonfire.UI.Boundaries.SetBoundariesLive.results_for_multiselect/1`), built once per page rather than per row."
  def members(nil, _context), do: []

  def members(group, context) do
    group
    |> Categories.list_members(current_user: current_user(context), pagination: [limit: 100])
    |> e(:edges, [])
    |> Bonfire.UI.Boundaries.SetBoundariesLive.results_for_multiselect()
  end
end
