defmodule Bonfire.Divlab.Tasks do
  @moduledoc """
  Group tasks, stored as `ValueFlows.Planning.Intent`s and created through the `:create` epic in `Bonfire.Divlab.RuntimeConfig`, so a task gets the same audience as a post in its group.
  """

  import Bonfire.Common.Config, only: [repo: 0]

  alias Bonfire.Common.Enums
  use Bonfire.Common.Settings
  alias ValueFlows.Planning.Intent
  alias ValueFlows.Planning.Intent.Intents

  @doc """
  Creates a task in a group.

  Options: `:current_user`, `:context_id` (the group), `:boundary` (as the composer sends it, which decides the feeds), and `:task_attrs` (Intent fields such as `:name`, `:note`, `:provider_id`, `:due`).

  Returns `{:error, _}` when the group doesn't resolve or the creator can't post in it, rather than creating a task with no group audience.
  """
  def create(opts) do
    Bonfire.Epics.run_epic(__MODULE__, :create, Keyword.put(opts, :on, :task))
  end

  @doc """
  Lists a group's tasks for one of the Tasks tab's views, through the tasks' boundaries.

  Views of open tasks: `:inbox` (nobody has taken it, newest first), `:mine` (I'm doing it), `:waiting` (I asked someone else to do it) and `:due_soon` (overdue, or due in the next 7 days); the last three are soonest first, undated last. `:done` is the latest 50 finished tasks, most recently changed first.
  """
  def list(view, group_id, opts) do
    me = Bonfire.Common.Utils.current_user(opts)

    case view_filters(view, Enums.id(me)) do
      # Mine and Waiting on are about the viewer, so a guest has neither
      nil ->
        {:ok, []}

      filters ->
        # not the `:default` preset: its ordering would come before each view's
        [:deleted, user: me, context_id: group_id]
        |> Kernel.++(filters)
        |> Intents.many()
    end
  end

  @doc """
  Makes `user_id` the task's provider, who does it. Assigning someone else also makes the assigner its receiver when it has none, so it shows in their Waiting on.

  Needs `:tag` on the task's group, as creating a task does, and `user_id` must be one of its members (`may_own?/2`).
  """
  def assign(task_id, user_id, opts) do
    me = Bonfire.Common.Utils.current_user(opts)

    with {:ok, task} <- fetch_to_triage(task_id, me),
         :ok <- may_own(user_id, task.context_id) do
      update_task(task, assign_attrs(task, user_id, Enums.id(me)))
    end
  end

  @doc "Whether `user` (a user or an id) may own a task in `group` (a group or an id): one of its members, as the owner menus offer (D10)."
  def may_own?(user, group), do: Bonfire.Classify.Categories.member?(user, group) == true

  @doc "Marks the task finished, which moves it from the open views to Done. Needs `:tag` on its group."
  def done(task_id, opts), do: triage(task_id, %{finished: true}, opts)

  @doc "Marks a finished task open again, back in whichever views it matches. Needs `:tag` on its group."
  def reopen(task_id, opts), do: triage(task_id, %{finished: false}, opts)

  @doc "Takes the owner off the task, which puts it back in the Inbox, and forgets who was waiting on it, so whoever takes it next doesn't land in their Waiting on. Needs `:tag` on its group."
  def unassign(task_id, opts), do: triage(task_id, %{provider_id: nil, receiver_id: nil}, opts)

  @doc "Sets the next date someone has to look at the task. Needs `:tag` on its group."
  def set_due(task_id, %DateTime{} = due, opts), do: triage(task_id, %{due: due}, opts)

  @doc "Clears the task's date, which takes it off Due soon. Needs `:tag` on its group."
  def clear_due(task_id, opts), do: triage(task_id, %{due: nil}, opts)

  @doc "Soft-deletes the task and removes its activities from the feeds. Only its creator, or someone its boundaries give `:delete` (moderators), may."
  def delete(task_id, opts) do
    me = Bonfire.Common.Utils.current_user(opts)

    with {:ok, task} <- Intents.by_id(task_id, me),
         :ok <- may_delete(me, task),
         {:ok, deleted} <- Bonfire.Common.Repo.Delete.soft_delete(task) do
      # feeds don't hide a soft-deleted Intent, so its create activity and the group's boost of it go, as `Bonfire.Social.Objects.do_delete/2` does for a post
      Bonfire.Social.Activities.delete_by_object(task.id)
      {:ok, deleted}
    end
  end

  @doc "Whether `user` may delete `task`: its creator, or someone its boundaries give `:delete` (moderators)."
  def may_delete?(%{id: id}, %{creator_id: id}), do: true
  def may_delete?(user, task), do: Bonfire.Boundaries.can?(user, :delete, task) == true

  @doc """
  Whether `group` has Tasks turned on. Whether the instance has them at all is divlab's `modularity` config, which `GroupLive.tab_component/1` and the settings row check.
  """
  def enabled_for?(group, _opts), do: group_enabled?(group)

  @doc """
  Turns Tasks on or off for `group`. Only its managers may: creator, `:edit` or `:mediate` (`Bonfire.Classify.ensure_update_allowed/2`).
  """
  def set_enabled(group, enabled?, opts) when is_boolean(enabled?) do
    # `Settings.put/3` doesn't check who may write to a scope it's handed, so the check is here
    if Bonfire.Classify.ensure_update_allowed(Bonfire.Common.Utils.current_user(opts), group),
      do: Settings.put([__MODULE__, :enabled], enabled?, scope: group),
      else: {:error, :not_permitted}
  end

  defp view_filters(view, nil) when view in [:mine, :waiting], do: nil

  defp view_filters(:inbox, _me_id), do: [status: :open, provider_id: :none, order: [desc: :id]]

  defp view_filters(:mine, me_id) when is_binary(me_id),
    do: [status: :open, provider_id: me_id, order: [asc_nulls_last: :due]]

  defp view_filters(:waiting, me_id) when is_binary(me_id),
    do: [
      status: :open,
      receiver_id: me_id,
      provider_id: {:not, [me_id]},
      order: [asc_nulls_last: :due]
    ]

  defp view_filters(:due_soon, _me_id),
    do: [
      status: :open,
      due_before: DateTime.add(DateTime.utc_now(), 7, :day),
      order: [asc: :due]
    ]

  # Done only grows, so the latest 50 (D9b); `updated_at` is when it was last changed, usually when it was checked off
  defp view_filters(:done, _me_id),
    do: [status: :closed, order: [desc: :updated_at], limit: 50]

  defp triage(task_id, attrs, opts) do
    me = Bonfire.Common.Utils.current_user(opts)

    with {:ok, task} <- fetch_to_triage(task_id, me) do
      update_task(task, attrs)
    end
  end

  # read through the task's boundaries first, so someone who can't see it gets `:not_found` rather than learning it exists
  defp fetch_to_triage(task_id, me) do
    with {:ok, task} <- Intents.by_id(task_id, me) do
      if Bonfire.Boundaries.can?(me, :tag, task.context_id),
        do: {:ok, task},
        else: {:error, :not_permitted}
    end
  end

  # not `Intents.update/4`, which federates an Update for every change
  defp update_task(task, attrs) do
    task
    |> Intent.update_changeset(attrs)
    |> repo().update()
  end

  defp assign_attrs(%{receiver_id: nil}, user_id, me_id) when user_id != me_id,
    do: %{provider_id: user_id, receiver_id: me_id}

  defp assign_attrs(_task, user_id, _me_id), do: %{provider_id: user_id}

  # reloaded, because `Settings.get/3` reads the settings on the struct it's given, and a group loaded before the last change would read the old value
  defp group_enabled?(group) do
    group
    |> repo().preload(:settings, force: true)
    |> then(&Settings.get([__MODULE__, :enabled], false, scope: &1))
    |> Kernel.==(true)
  end

  defp may_own(user_id, group_id),
    do: if(may_own?(user_id, group_id), do: :ok, else: {:error, :owner_not_a_member})

  defp may_delete(me, task),
    do: if(may_delete?(me, task), do: :ok, else: {:error, :not_permitted})
end
