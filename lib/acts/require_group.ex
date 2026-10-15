defmodule Bonfire.Divlab.Acts.RequireGroup do
  @moduledoc """
  Stops the task `:create` epic when its group isn't among the categories the `Tag` act kept, ie. the group doesn't exist or the creator lacks `:tag` on it (`Bonfire.Social.Tags.maybe_boostable_categories/2`), when the group hasn't turned Tasks on (`Bonfire.Divlab.Tasks.enabled_for?/2`), or when the task's owner isn't one of the group's members (`Bonfire.Divlab.Tasks.may_own?/2`).

  A post in that case is still created, outside the group. A task would get no ACLs and land in the Local feed, so it's refused instead. Runs after `Tag`, before `SetBoundaries`.
  """
  import Bonfire.Epics

  alias Bonfire.Common.Enums
  alias Bonfire.Epics.Epic

  def run(%{errors: [_ | _]} = epic, act) do
    maybe_debug(epic, act, length(epic.errors), "Skipping due to epic errors")
    epic
  end

  def run(epic, act) do
    on = Keyword.get(act.options, :on, :task)
    group_id = epic.assigns[:options][:context_id]

    kept =
      epic.assigns
      |> Map.get(:categories_auto_boost)
      |> List.wrap()
      |> Enum.find(&(Enums.id(&1) == group_id))

    cond do
      is_nil(kept) ->
        Epic.add_error(epic, act, :group_not_found_or_not_permitted)

      not Bonfire.Divlab.Tasks.enabled_for?(kept, epic.assigns[:options]) ->
        Epic.add_error(epic, act, :tasks_not_enabled)

      not owner_allowed?(epic.assigns[on], kept) ->
        Epic.add_error(epic, act, :owner_not_a_member)

      true ->
        epic
    end
  end

  # the owner on the task `CreateTask` built, whichever option its attrs came from; nobody, the Inbox, is always fine
  defp owner_allowed?(changeset, group) do
    case Ecto.Changeset.get_field(changeset, :provider_id) do
      nil -> true
      owner_id -> Bonfire.Divlab.Tasks.may_own?(owner_id, group)
    end
  end
end
