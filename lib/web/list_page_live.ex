defmodule Bonfire.Divlab.Web.ListPageLive do
  @moduledoc """
  A list's own page (tasks-v2 §1, §14 to §16, decision 26): its name and description (written in place by those who may edit), whether it's closed and its progress, a menu to rename, close, reopen or delete it, its items as lines to write in, and a trailing line to add one. It's what `Bonfire.Divlab.Web.Preview.ListLive` shows when the list is the main object of its discussion page, so replies follow below it as on any discussion.

  Rows are `Bonfire.Divlab.Web.TaskRowLive` in its `editable` mode, so ticking and owners work as on the Tasks page; their events come back here, and `load/1` reloads the list after each. The `ListLines` hook (`list_page_live.hooks.js`) handles the lines: Enter goes to the next new line (items keep the order they were written, decision 13), and a line is renamed on Enter or blur.
  """
  use Bonfire.UI.Common.Web, :stateful_component

  alias Bonfire.Divlab.Tasks
  alias Bonfire.Divlab.Web.TasksBoardLive
  alias Bonfire.Divlab.Web.Preview.ListLive

  prop list, :any, required: true

  data items, :list, default: []
  data members, :list, default: []
  data deletable, :any, default: MapSet.new()
  data may_edit, :boolean, default: false
  # the list's creator, or someone its boundaries give `:delete` (`Tasks.delete_list/2`)
  data may_delete_list, :boolean, default: false
  # the group's default audience for items written here, as the composer picks it (`Bonfire.Classify.Boundaries.list_post_audiences/1`)
  data boundary, :any, default: nil
  # the list this page loaded: once mounted, the page owns its list, which its own events change. The discussion passes its copy of `list` again whenever it re-renders (each new reply), which would bring old values back and reload every item
  data loaded_id, :any, default: nil

  def update(%{list: %{id: list_id}} = assigns, %{assigns: %{loaded_id: list_id}} = socket),
    do: {:ok, assign(socket, Map.delete(assigns, :list))}

  # a row's owner picker asks its parent to reload (`send_update(parent, %{})`): only the items changed, not the group, its members or the audience
  def update(assigns, %{assigns: %{loaded_id: loaded_id}} = socket)
      when not is_map_key(assigns, :list) and not is_nil(loaded_id),
      do: {:ok, socket |> assign(assigns) |> load()}

  def update(assigns, socket) do
    socket = assign(socket, assigns)
    list = socket.assigns.list
    context = socket.assigns[:__context__]
    group = load_group(list.context_id, context)

    {:ok,
     socket
     |> assign(
       loaded_id: list.id,
       members: TasksBoardLive.members(group, context),
       may_edit: Bonfire.Boundaries.can?(current_user(context), :tag, list.context_id) == true,
       may_delete_list: Tasks.may_delete?(current_user(context), list),
       boundary: group && group |> Bonfire.Classify.Boundaries.list_post_audiences() |> List.first()
     )
     |> load()}
  end

  @doc "Loads the list's items, with each one's owner and replies count, and which of them the current user may delete."
  def load(socket) do
    me = current_user(socket)
    list = socket.assigns.list

    {:ok, items} = Tasks.items(id(list), current_user: me)
    items = repo().maybe_preload(items, provider: [:profile, :character], replied: [])

    assign(socket, items: items, deletable: Tasks.deletable(me, items))
  end

  defp load_group(nil, _context), do: nil

  defp load_group(group_id, context) do
    case Bonfire.Classify.Categories.get(group_id, [:default, current_user: current_user(context)]) do
      {:ok, group} -> group
      _ -> nil
    end
  end

  defp done_count(items), do: Enum.count(items, &(&1.finished == true))

  defp progress_label(items), do: ListLive.progress_label(done_count(items), length(items))
end
