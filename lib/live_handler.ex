defmodule Bonfire.Divlab.LiveHandler do
  use Bonfire.UI.Common.Web, :live_handler

  # the group comes from the page's own assigns, not from the form, so nobody can point the toggle at another group
  def handle_event("set_tasks_enabled", %{"enabled" => enabled}, socket) do
    with {:ok, _} <-
           Bonfire.Divlab.Tasks.set_enabled(e(assigns(socket), :category, nil), enabled == "true",
             current_user: current_user(socket)
           ) do
      {:noreply, assign_flash(socket, :info, l("Saved"))}
    end
  end

  # The composer's lines (tasks-v2 §13): `choices` in the order they were written, into the list or the new list `post[into]` names
  def handle_event("create_tasks", %{"post" => post} = params, socket) do
    me = current_user_required!(socket)

    opts = [
      current_user: me,
      context_id: e(params, "context_id", nil),
      boundary: e(params, "to_boundaries", nil) |> List.wrap() |> List.first()
    ]

    lines = lines(params["choices"])

    result =
      case post["into"] do
        "new" ->
          Bonfire.Divlab.Tasks.create_list(
            # a name and an optional description (tasks-v2 §15)
            %{name: e(post, "post_content", "name", nil), note: blank_to_nil(post["list_note"])},
            lines,
            opts
          )

        # an open list's id; the composer makes no items without a list (tasks-v2 decision 25), so a missing one is refused rather than read as "no list"
        into ->
          case blank_to_nil(into, ["none"]) do
            nil -> {:error, :no_list}
            list_id -> Bonfire.Divlab.Tasks.add_items(lines, Keyword.put(opts, :list_id, list_id))
          end
      end

    case result do
      {:ok, outcome} ->
        # the group's Tasks page, in another LiveView, reloads its board (`TasksBoardLive.tasks_topic/1`); the payload only names the group, the board reads through boundaries as always
        Bonfire.Common.PubSub.broadcast(
          Bonfire.Divlab.Web.TasksBoardLive.tasks_topic(opts[:context_id]),
          {{Bonfire.Divlab, :tasks_changed}, opts[:context_id]}
        )

        {:noreply,
         socket
         |> Bonfire.UI.Common.SmartInput.LiveHandler.reset_input()
         |> assign_flash(:info, created_message(outcome))}

      {:error, :no_list} ->
        {:noreply, assign_error(socket, l("Pick a list, or start a new one"))}

      e ->
        error(e, "Could not add the tasks")
        {:noreply, assign_error(socket, l("Could not add the tasks"))}
    end
  end

  # The composer's Into chip comes from `CreateTasksLive` (`phx-target={@myself}`), so `socket` is the component's: the choice stays in its assigns, which the composer's re-render on every keystroke doesn't reset, and its hidden input sends it with the lines.

  def handle_event("pick_into", %{"into" => into}, socket),
    do: {:noreply, assign(socket, into: into)}

  # A list's page (`ListPageLive`, `phx-target={@myself}`): closing, reopening, renaming and deleting it, its description (tasks-v2 §16, decisions 19, 22 and 26), and its lines from the `ListLines` hook

  def handle_event("close_list", _params, socket),
    do: change_list(socket, &Bonfire.Divlab.Tasks.close_list/2)

  def handle_event("reopen_list", _params, socket),
    do: change_list(socket, &Bonfire.Divlab.Tasks.reopen_list/2)

  # the name and the description save on Enter (the name only) or blur, as an item line does
  def handle_event("rename_list", %{"value" => value}, socket),
    do: set_list(socket, :name, blank_to_nil(value))

  def handle_event("set_list_note", %{"value" => value}, socket),
    do: set_list(socket, :note, blank_to_nil(value))

  # back to the group's Tasks page, since the list's own page is gone with it
  def handle_event("delete_list", _params, socket) do
    list = e(assigns(socket), :list, nil)

    case Bonfire.Divlab.Tasks.delete_list(list.id, current_user: current_user_required!(socket)) do
      :ok ->
        {:noreply,
         socket
         |> assign_flash(:info, l("List deleted"))
         |> redirect_to(Bonfire.Divlab.Web.Preview.TaskLive.tasks_path(list))}

      e ->
        error(e, "Could not delete the list")
        {:noreply, assign_error(socket, l("Could not delete the list"))}
    end
  end

  # the trailing line, or a pasted checklist: items into this list, with the group's default audience, as the composer sends them
  def handle_event("list_add", %{"text" => text}, socket) do
    list = e(assigns(socket), :list, nil)

    case Bonfire.Divlab.Tasks.add_items(text,
           current_user: current_user_required!(socket),
           context_id: list.context_id,
           list_id: list.id,
           boundary: e(assigns(socket), :boundary, nil)
         ) do
      {:ok, _items} ->
        {:noreply, Bonfire.Divlab.Web.ListPageLive.load(socket)}

      e ->
        error(e, "Could not add the item")
        {:noreply, assign_error(socket, l("Could not add the item"))}
    end
  end

  def handle_event("rename", %{"task_id" => task_id, "name" => name}, socket) do
    task_id
    |> Bonfire.Divlab.Tasks.rename(name, current_user: current_user_required!(socket))
    |> after_row_action(socket, nil)
  end

  # The Tasks page's row actions come from `TasksBoardLive` (`phx-target={@myself}`), so `socket` is the board's, and reloading it refreshes every view and count.

  def handle_event("take", %{"task_id" => task_id}, socket) do
    me = current_user_required!(socket)

    task_id
    |> Bonfire.Divlab.Tasks.assign(id(me), current_user: me)
    |> after_row_action(socket, l("Task taken"))
  end

  def handle_event("done", %{"task_id" => task_id}, socket) do
    task_id
    |> Bonfire.Divlab.Tasks.done(current_user: current_user_required!(socket))
    |> after_row_action(socket, l("Task done"))
  end

  def handle_event("reopen", %{"task_id" => task_id}, socket) do
    task_id
    |> Bonfire.Divlab.Tasks.reopen(current_user: current_user_required!(socket))
    |> after_row_action(socket, l("Task reopened"))
  end

  def handle_event("unassign", %{"task_id" => task_id}, socket) do
    task_id
    |> Bonfire.Divlab.Tasks.unassign(current_user: current_user_required!(socket))
    |> after_row_action(socket, l("Back in the Inbox"))
  end

  def handle_event("delete", %{"task_id" => task_id}, socket) do
    task_id
    |> Bonfire.Divlab.Tasks.delete(current_user: current_user_required!(socket))
    |> after_row_action(socket, l("Task deleted"))
  end

  # tasks added from the composer: this page's board reloads, every view and count
  def handle_info({:tasks_changed, _group_id}, socket) do
    maybe_send_update(Bonfire.Divlab.Web.TasksBoardLive, "group_tasks_board", %{})
    {:noreply, socket}
  end

  defp after_row_action({:ok, _}, socket, message),
    do:
      {:noreply,
       socket
       |> reload()
       |> then(&if(message, do: assign_flash(&1, :info, message), else: &1))}

  defp after_row_action({:error, :owner_not_a_member}, socket, _message),
    do: {:noreply, assign_error(socket, l("The owner has to be a member of this group"))}

  defp after_row_action(error, socket, _message) do
    error(error, "Could not change the task")
    {:noreply, assign_error(socket, l("Could not change the task"))}
  end

  # the list page's own list, changed by `fun` (`Tasks.close_list/2`, `update_list/3`…), which checks `:tag`. Only the list changed, so its items aren't read again
  defp change_list(socket, fun) do
    list = e(assigns(socket), :list, nil)

    case fun.(list.id, current_user: current_user_required!(socket)) do
      {:ok, updated} ->
        {:noreply, assign(socket, list: updated)}

      e ->
        error(e, "Could not change the list")
        {:noreply, assign_error(socket, l("Could not change the list"))}
    end
  end

  # a list always has a name, so a blank one is ignored; an unchanged value isn't written again (Enter, then the blur that follows)
  defp set_list(socket, :name, nil), do: {:noreply, socket}

  defp set_list(socket, field, value) do
    if value == e(assigns(socket), :list, field, nil),
      do: {:noreply, socket},
      else: change_list(socket, &Bonfire.Divlab.Tasks.update_list(&1, %{field => value}, &2))
  end

  # trimmed text, or `nil` when it's blank or one of `none`
  defp blank_to_nil(text, none \\ []) when is_binary(text) or is_nil(text) do
    case text && String.trim(text) do
      blank when blank in [nil, ""] -> nil
      text -> if text in none, do: nil, else: text
    end
  end

  # a row's actions come from the Tasks page's board or from a list's page (`ListPageLive`, which has a `list`), and reload whichever sent them
  defp reload(socket) do
    if e(assigns(socket), :list, nil),
      do: Bonfire.Divlab.Web.ListPageLive.load(socket),
      else: Bonfire.Divlab.Web.TasksBoardLive.load(socket)
  end

  # the composer's lines in the order they were written: the `Lines` hook numbers them `choices[i][name]`
  defp lines(choices) when is_map(choices) do
    choices
    |> Enum.sort_by(fn {index, _} ->
      with {n, _} <- Integer.parse(to_string(index)), do: n, else: (_ -> 0)
    end)
    |> Enum.map(fn {_, choice} -> e(choice, "name", nil) end)
    |> Enum.filter(&is_binary/1)
  end

  defp lines(_), do: []

  defp created_message(%{items: items}),
    do: l("List created with %{count} items", count: length(items))

  # `add_items/2` puts the list it read on each item
  defp created_message(items) do
    case items |> List.first() |> e(:input_of, :name, nil) do
      nil -> l("%{count} items added", count: length(items))
      name -> l("%{count} items added to %{list}", count: length(items), list: name)
    end
  end
end
