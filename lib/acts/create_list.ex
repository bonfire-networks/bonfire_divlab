defmodule Bonfire.Divlab.Acts.CreateList do
  @moduledoc """
  Builds the `ValueFlows.Process` changeset for the `:create_list` epic and registers it for insertion, as `Bonfire.Divlab.Acts.CreateTask` does for an Intent.

  The id is set here because `Bonfire.Social.Acts.Threaded` uses it as the new thread's id before the insert. The spike (tasks-v2 §4 step 1) showed a Process takes the post acts as an Intent does.
  """
  use Arrows
  import Bonfire.Epics

  alias Bonfire.Ecto.Acts.Work
  alias Bonfire.Epics.Epic
  alias ValueFlows.Process

  def run(%{errors: [_ | _]} = epic, act) do
    maybe_debug(epic, act, length(epic.errors), "Skipping due to epic errors")
    epic
  end

  def run(epic, act) do
    options = epic.assigns[:options]
    on = Keyword.get(act.options, :on, :list)

    case Bonfire.Common.Utils.current_user(options) do
      %{id: _} = creator ->
        attrs =
          options
          |> Keyword.get(Keyword.get(act.options, :attrs, :list_attrs), %{})
          |> Map.new()
          |> Map.take([:name, :note])
          |> Map.put(:context_id, options[:context_id])

        Process.create_changeset(creator, attrs)
        |> Bonfire.Divlab.Tasks.validate_name()
        |> Ecto.Changeset.put_change(:id, Needle.ULID.generate())
        |> Map.put(:action, :insert)
        |> Epic.assign(epic, on, ...)
        |> Work.add(on)

      _ ->
        Epic.add_error(epic, act, :missing_current_user)
    end
  end
end
