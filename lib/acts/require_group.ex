defmodule Bonfire.Divlab.Acts.RequireGroup do
  @moduledoc """
  Stops the `:create_item` or `:create_list` epic when its group isn't among the categories the `Tag` act kept, ie. the group doesn't exist or the creator lacks `:tag` on it (`Bonfire.Social.Tags.maybe_boostable_categories/2`), or when the group hasn't turned Tasks on (`Bonfire.Divlab.Tasks.enabled_for?/2`). Items are created with no owner; `Bonfire.Divlab.Tasks.assign/3` checks the owner is a member.

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

      true ->
        epic
    end
  end
end
