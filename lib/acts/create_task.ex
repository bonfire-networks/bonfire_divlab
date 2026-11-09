defmodule Bonfire.Divlab.Acts.CreateTask do
  @moduledoc """
  Builds the Intent changeset for the `:create_item` epic and registers it for insertion.

  Intent's own `creator_id` stands in for the `Creator` act, which can't run on an Intent (no `created` mixin). The id is set here because `Bonfire.Social.Acts.Threaded` uses it as the new thread's id before the insert.
  """
  use Arrows
  import Bonfire.Epics

  alias Bonfire.Ecto.Acts.Work
  alias Bonfire.Epics.Epic
  alias ValueFlows.Planning.Intent

  # every task is the same kind of ValueFlows intent: someone doing work
  @action_id "work"

  def run(%{errors: [_ | _]} = epic, act) do
    maybe_debug(epic, act, length(epic.errors), "Skipping due to epic errors")
    epic
  end

  def run(epic, act) do
    options = epic.assigns[:options]
    on = Keyword.get(act.options, :on, :task)

    case Bonfire.Common.Utils.current_user(options) do
      %{id: _} = creator ->
        attrs =
          options
          |> Keyword.get(Keyword.get(act.options, :attrs, :task_attrs), %{})
          |> Map.put(:action_id, @action_id)
          |> Map.put(:context_id, options[:context_id])

        Intent.create_changeset(creator, attrs)
        |> Bonfire.Divlab.Tasks.validate_name()
        # a batch passes increasing ids, so its items keep the order they were written in (ULIDs only order by the millisecond)
        |> Ecto.Changeset.put_change(:id, attrs[:id] || Needle.ULID.generate())
        |> Map.put(:action, :insert)
        |> Epic.assign(epic, on, ...)
        |> Work.add(on)

      _ ->
        Epic.add_error(epic, act, :missing_current_user)
    end
  end
end
