defmodule Bonfire.Divlab.Web.TaskOwnerPickerLive do
  @moduledoc """
  The search in a task row's owner menu: Bonfire's `LiveSelect` user picker, as `Bonfire.UI.Groups.Settings.AddPersonLive` uses it. It lists the group's members before anyone types, searches people and keeps the group's members, and picking someone assigns the task (`Bonfire.Divlab.Tasks.assign/3`, which checks membership again), then tells `parent` (the board or the list page) to reload its rows.
  """
  use Bonfire.UI.Common.Web, :stateful_component

  alias Bonfire.Divlab.Tasks

  prop task, :any, required: true
  # the page's members as options (`TasksBoardLive.members/2`), shown before anyone types
  prop members, :list, default: []
  # the stateful component the row's events go to: it reloads its rows after an assignment
  prop parent, :any, required: true

  def handle_event("live_select_change", %{"id" => live_select_id, "text" => search}, socket)
      when is_binary(search) and byte_size(search) >= 2 do
    maybe_send_update(LiveSelect.Component, live_select_id,
      options: options(search, socket.assigns.task.context_id)
    )

    {:noreply, socket}
  end

  def handle_event("live_select_change", _params, socket), do: {:noreply, socket}

  # LiveSelect single selection (via the form's phx-change): one form per row, named after the task, so each row's picker has its own ids while the field (which LiveSelect turns into an atom) stays the same
  def handle_event("change", %{"_target" => [form_name, "owner"]} = params, socket)
      when is_binary(form_name) do
    case decode_selected_id(e(params, form_name, "owner", nil)) do
      nil -> {:noreply, socket}
      user_id -> assign_owner(user_id, socket)
    end
  end

  def handle_event("change", _params, socket), do: {:noreply, socket}

  @doc "Who the search offers: people matching `search` who are members of `group` (one query for the whole page of results, not a check per person)."
  def options(search, group) do
    users =
      # the database's matches too: a search index (Sonic) can answer with a few users and miss the members, and `Users.search/2` only falls back to the database on an empty answer, so `db_merge` (`Bonfire.Search.search_by_type/3`) asks both
      Bonfire.Me.Users.search(search, db_merge: true)
      |> Enum.map(fn
        %Needle.Pointer{activity: %{object: user}} -> user
        other -> other
      end)

    members =
      case users != [] && Bonfire.Classify.Categories.members_circle(group) do
        {:ok, circle} -> Bonfire.Boundaries.Circles.encircled_subset(users, circle)
        _ -> MapSet.new()
      end

    users
    |> Enum.filter(&MapSet.member?(members, id(&1)))
    |> Bonfire.UI.Boundaries.SetBoundariesLive.results_for_multiselect()
  end

  @doc "The row's form, named after its task so its LiveSelect ids are its own."
  def owner_form(task), do: to_form(%{}, as: "owner_#{id(task)}")

  defp assign_owner(user_id, socket) do
    case Tasks.assign(id(socket.assigns.task), user_id,
           current_user: current_user_required!(socket)
         ) do
      {:ok, _} ->
        # the parent's `update/2` reloads its rows, as after any row action
        send_update(socket.assigns.parent, %{})
        {:noreply, assign_flash(socket, :info, l("Task assigned"))}

      {:error, :owner_not_a_member} ->
        {:noreply, assign_error(socket, l("The owner has to be a member of this group"))}

      error ->
        error(error, "Could not assign the task")
        {:noreply, assign_error(socket, l("Could not change the task"))}
    end
  end

  defp decode_selected_id(json_string) when is_binary(json_string) and json_string != "" do
    case Jason.decode(json_string) do
      {:ok, data} -> data["id"] || data[:id]
      _ -> nil
    end
  end

  defp decode_selected_id(_), do: nil
end
