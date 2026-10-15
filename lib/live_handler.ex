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

  # the composer's form is `as: :post`, so unwrap once
  def handle_event("create_task", %{"post" => post_params} = params, socket),
    do:
      handle_event(
        "create_task",
        params |> Map.merge(post_params) |> Map.drop(["post"]),
        socket
      )

  # the owner is the id the chip picked; `RequireGroup` refuses anyone who isn't a member of the group
  def handle_event("create_task", params, socket) do
    case Bonfire.Divlab.Tasks.create(
           current_user: current_user_required!(socket),
           context_id: e(params, "context_id", nil),
           boundary: e(params, "to_boundaries", nil) |> List.wrap() |> List.first(),
           task_attrs: task_attrs(params)
         ) do
      {:ok, _task} ->
        {:noreply,
         socket
         |> Bonfire.UI.Common.SmartInput.LiveHandler.reset_input()
         |> assign_flash(:info, l("Task added"))}

      e ->
        error(e, "Could not add the task")
        {:noreply, assign_error(socket, l("Could not add the task"))}
    end
  end

  # The task composer's chips come from `CreateTaskLive` (`phx-target={@myself}`), so `socket` is the component's: their choice stays in its assigns, which the composer's re-render on every keystroke doesn't reset, and its hidden inputs send it with the task.

  def handle_event("pick_task_owner", %{"owner" => username}, socket) do
    case Bonfire.Divlab.Web.CreateTaskLive.resolve_member(
           e(assigns(socket), :members, []),
           String.trim(username),
           e(assigns(socket), :group, nil)
         ) do
      nil -> {:noreply, assign_error(socket, l("The owner has to be a member of this group"))}
      member -> {:noreply, assign(socket, task_owner: member)}
    end
  end

  def handle_event("clear_task_owner", _params, socket),
    do: {:noreply, assign(socket, task_owner: nil)}

  # clearing the chip's date input means no date, as "No date" does
  def handle_event("pick_task_due", %{"due" => ""}, socket),
    do: handle_event("clear_task_due", %{}, socket)

  def handle_event("pick_task_due", %{"due" => day}, socket) do
    case Date.from_iso8601(day || "") do
      {:ok, date} -> {:noreply, assign(socket, task_due: date)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("clear_task_due", _params, socket),
    do: {:noreply, assign(socket, task_due: nil)}

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

  # the same rule as the composer's owner box: a member of the group, from the board's list or looked up past it
  def handle_event("assign", %{"task_id" => task_id, "owner" => username}, socket) do
    case Bonfire.Divlab.Web.CreateTaskLive.resolve_member(
           e(assigns(socket), :members, []),
           String.trim(username),
           e(assigns(socket), :category, nil)
         ) do
      nil ->
        {:noreply, assign_error(socket, l("The owner has to be a member of this group"))}

      member ->
        task_id
        |> Bonfire.Divlab.Tasks.assign(member.id, current_user: current_user_required!(socket))
        |> after_row_action(socket, l("Task assigned"))
    end
  end

  # clearing the date input means no date, as "No date" does
  def handle_event("set_due", %{"task_id" => task_id, "due" => ""}, socket),
    do: handle_event("clear_due", %{"task_id" => task_id}, socket)

  def handle_event("set_due", %{"task_id" => task_id, "due" => day}, socket) do
    case parse_due(day) do
      nil ->
        {:noreply, assign_error(socket, l("Pick a date"))}

      due ->
        task_id
        |> Bonfire.Divlab.Tasks.set_due(due, current_user: current_user_required!(socket))
        |> after_row_action(socket, l("Date set"))
    end
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

  def handle_event("clear_due", %{"task_id" => task_id}, socket) do
    task_id
    |> Bonfire.Divlab.Tasks.clear_due(current_user: current_user_required!(socket))
    |> after_row_action(socket, l("Date cleared"))
  end

  def handle_event("delete", %{"task_id" => task_id}, socket) do
    task_id
    |> Bonfire.Divlab.Tasks.delete(current_user: current_user_required!(socket))
    |> after_row_action(socket, l("Task deleted"))
  end

  defp after_row_action({:ok, _}, socket, message),
    do:
      {:noreply,
       socket
       |> Bonfire.Divlab.Web.TasksBoardLive.load()
       |> assign_flash(:info, message)}

  defp after_row_action({:error, :owner_not_a_member}, socket, _message),
    do: {:noreply, assign_error(socket, l("The owner has to be a member of this group"))}

  defp after_row_action(error, socket, _message) do
    error(error, "Could not change the task")
    {:noreply, assign_error(socket, l("Could not change the task"))}
  end

  # only the fields the form offers, so nothing else the composer sends reaches the Intent
  defp task_attrs(params) do
    %{
      name: e(params, "post_content", "name", nil),
      note: blank_to_nil(params["note"]),
      provider_id: e(params, "owner_id", nil),
      due: parse_due(params["due"])
    }
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  # a date input sends a day; midnight UTC that day is when it's due
  defp parse_due(day) when is_binary(day) do
    case Date.from_iso8601(day) do
      {:ok, date} -> DateTime.new!(date, ~T[00:00:00.000000], "Etc/UTC")
      _ -> nil
    end
  end

  defp parse_due(_), do: nil
end
