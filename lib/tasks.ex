defmodule Bonfire.Divlab.Tasks do
  @moduledoc """
  Group tasks and their lists: an item is a `ValueFlows.Planning.Intent`, a list a `ValueFlows.Process` (tasks-v2). Both are created through the epics in `Bonfire.Divlab.RuntimeConfig`, so they get the same audience as a post in their group. Every read goes through boundaries, and nothing federates.
  """

  import Bonfire.Common.Config, only: [repo: 0]
  import Bonfire.Boundaries.Queries, only: [boundarise: 3]
  import Ecto.Query

  alias Bonfire.Common.Enums
  use Bonfire.Common.Settings
  alias ValueFlows.Planning.Intent
  alias ValueFlows.Planning.Intent.Intents

  @doc """
  Creates a list (a `ValueFlows.Process`) in a group, with its first items, all or nothing (tasks-v2 decision 7).

  `list_attrs` takes `:name` and an optional `:note` (its description). Lists have no dates (tasks-v2 §16): a list is open until someone closes it. `lines` are written items, as `parse_lines/1` reads them.

  Options: `:current_user`, `:context_id` (the group) and `:boundary` (as the composer sends it, which decides the feeds). Returns `{:error, _}` when the group doesn't resolve, the creator can't post in it or it hasn't turned Tasks on (`Bonfire.Divlab.Acts.RequireGroup`), rather than creating anything with no group audience.

  Returns `{:ok, %{list: list, items: items}}`, or `{:error, _}` with nothing created.
  """
  def create_list(list_attrs, lines, opts) do
    # every line is checked before anything runs: the group's boost of the list pushes to open feeds at once (`Bonfire.Social.Boosts`), so a batch failing on a later line would leave a phantom list there
    with {:ok, items} <- check_lines(lines) do
      repo().transact_with(fn ->
        with {:ok, list} <- run_epic(:create_list, :list, Keyword.put(opts, :list_attrs, list_attrs)),
             {:ok, items} <- insert_items(items, list.id, opts) do
          {:ok, %{list: list, items: items}}
        end
      end)
    end
  end

  @doc """
  Adds written items to a group, all or nothing: into the list `opts[:list_id]` (which must be an open one the user can see, in the same group: a closed list gives `{:error, :list_closed}`), or into no list when it's `nil`.

  Options as `create_list/3`, plus `:list_id`. Each item gets its own activity, and the group doesn't boost it (tasks-v2 decisions 5F and 10).
  """
  def add_items(lines, opts) do
    me = Bonfire.Common.Utils.current_user(opts)

    with {:ok, items} <- check_lines(lines),
         {:ok, list} <- list_in_group(opts[:list_id], opts[:context_id], me) do
      repo().transact_with(fn ->
        # holds off a `delete_list/2` of the same list until these items are in, so they go with it
        with :ok <- share_lock_list(Enums.id(list)),
             {:ok, items} <- insert_items(items, Enums.id(list), opts) do
          # the list it read, so a caller can name it without reading it again
          {:ok, Enum.map(items, &Map.put(&1, :input_of, list))}
        end
      end)
    end
  end

  @doc """
  Reads written lines into items: one per non-blank line, with `- `, `* ` and `+ ` bullets dropped, `[x]` done and `[ ]` open, as the pad has them. Takes a list of lines or a text.
  """
  def parse_lines(text) when is_binary(text), do: text |> String.split(~r/\R/) |> parse_lines()

  def parse_lines(lines) when is_list(lines) do
    Enum.flat_map(lines, fn line ->
      # a markdown rule (`---`, `***`, `___`) separates sections in a pad, it isn't an item
      if Regex.match?(~r/^\s*([-*_])(?:\s*\1){2,}\s*$/, line) do
        []
      else
        # a bullet with nothing after it (`-`, an empty pad line whose space an editor trimmed) is blank too
        case Regex.named_captures(~r/^\s*(?:[-*+](?:\s+|$))?(?:\[(?<box>[ xX])\]\s*)?(?<name>.*?)\s*$/u, line) do
          %{"name" => ""} -> []
          %{"box" => box, "name" => name} -> [%{name: name, finished: box in ["x", "X"]}]
        end
      end
    end)
  end

  @doc "Names are `varchar(255)` in the database, with no check in ValueFlows' changesets, so a long pasted line would otherwise raise."
  def validate_name(changeset), do: Ecto.Changeset.validate_length(changeset, :name, max: 255)

  @doc """
  A group's lists that the user can see: open lists newest first, then closed lists, most recently changed first (tasks-v2 decision 23).

  Read through the lists' boundaries with divlab's own query: `ValueFlows.Process.Queries` has no `boundarise/3` (tasks-v2 decision 12).
  """
  def lists(group_id, opts) do
    me = Bonfire.Common.Utils.current_user(opts)

    {closed, open} =
      lists_query(me)
      |> where([process: p], p.context_id == ^group_id)
      |> repo().many()
      |> Enum.split_with(& &1.finished)

    {:ok, Enum.sort_by(open, & &1.id, :desc) ++ Enum.sort_by(closed, & &1.updated_at, {:desc, DateTime})}
  end

  @doc "The items of a list the user can see, in the order they were written."
  def items(list_id, opts) when is_binary(list_id) do
    me = Bonfire.Common.Utils.current_user(opts)
    Intents.many([:deleted, user: me, input_of_id: list_id, order: [asc: :id]])
  end

  @doc "The first `limit` open items of a list the user can see, in the order they were written: what a list's feed card shows."
  def open_items(list_id, limit, opts) when is_binary(list_id) do
    me = Bonfire.Common.Utils.current_user(opts)
    Intents.many([:deleted, user: me, input_of_id: list_id, status: :open, order: [asc: :id], limit: limit])
  end

  @doc """
  How far along each of `list_ids` is, counting the items the user can see: `%{list_id => {done, total}}`, in one query. A list with no items isn't in the map.
  """
  def progress([], _opts), do: %{}

  def progress(list_ids, opts) when is_list(list_ids) do
    me = Bonfire.Common.Utils.current_user(opts)

    from(i in Intent,
      as: :intent,
      where: i.input_of_id in ^list_ids and is_nil(i.deleted_at),
      group_by: i.input_of_id,
      select: {i.input_of_id, filter(count(i.id), i.finished == true), count(i.id)}
    )
    |> boundarise(intent.id, current_user: me)
    |> repo().all()
    |> Map.new(fn {list_id, done, total} -> {list_id, {done, total}} end)
  end

  @doc "Changes a list's name or description (`:note`). Needs `:tag` on its group, as adding items does."
  def update_list(list_id, attrs, opts),
    do: triage_list(list_id, attrs |> Map.new() |> Map.take([:name, :note]), opts)

  @doc "Closes a list. Its open items stay open, shown as left over, and it takes no new items until it's reopened. Needs `:tag` on its group."
  def close_list(list_id, opts), do: triage_list(list_id, %{finished: true}, opts)

  @doc "Opens a closed list again. Needs `:tag` on its group."
  def reopen_list(list_id, opts), do: triage_list(list_id, %{finished: false}, opts)

  @doc """
  Soft-deletes a list and its items, and removes all their activities from the feeds, as `delete/2` does for one task. Only the list's creator, or someone its boundaries give `:delete`, may.
  """
  def delete_list(list_id, opts) do
    me = Bonfire.Common.Utils.current_user(opts)

    with {:ok, list} <- fetch_list(list_id, me),
         :ok <- may_delete(me, list) do
      repo().transact_with(fn ->
        # the list's row is locked first, so items being added to it (`share_lock_list/1`) are either in already, and go with it, or wait and then find it deleted
        with :ok <- update_lock_list(list.id),
             {:ok, _} <- Bonfire.Common.Repo.Delete.soft_delete(list) do
          # every item of the list, not only those the deleter can see: they go with the list
          {_count, item_ids} =
            from(i in Intent, where: i.input_of_id == ^list.id and is_nil(i.deleted_at), select: i.id)
            |> repo().update_all(set: [deleted_at: DateTime.utc_now()])

          # feeds don't hide soft-deleted VF objects (see `delete/2`): every activity of the list and its items goes, in one query
          Bonfire.Social.Activities.delete({:object_id, [list.id | item_ids]})
          :ok
        end
      end)
      # `transact_with/1` wraps the function's `:ok` as `{:ok, :ok}`
      |> case do
        {:ok, _} -> :ok
        error -> error
      end
    end
  end

  @doc "Renames an item. Needs `:tag` on its group."
  def rename(item_id, name, opts), do: triage(item_id, %{name: name}, opts)

  @doc """
  Lists a group's tasks for one of the Tasks tab's views, through the tasks' boundaries.

  Views of open tasks: `:inbox` (nobody has taken it, newest first), `:mine` (I'm doing it) and `:waiting` (I asked someone else to do it), all newest first (tasks-v2 decision 24). `:done` is the latest 50 finished tasks, most recently changed first.
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

  @doc "The ids of `tasks` that `user` may delete, as `may_delete?/2` decides for each, with one boundary query for all the ones they didn't create."
  def deletable(user, tasks) do
    {mine, others} = Enum.split_with(tasks, &(not is_nil(&1.creator_id) and &1.creator_id == Enums.id(user)))

    permitted =
      case others do
        [] -> []
        _ -> Bonfire.Boundaries.load_pointers(Enum.map(others, &Enums.id/1), current_user: user, verbs: [:delete], ids_only: true)
      end

    MapSet.new(Enum.map(mine, &Enums.id/1) ++ Enum.map(permitted, &Enums.id/1))
  end

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
    do: [status: :open, provider_id: me_id, order: [desc: :id]]

  defp view_filters(:waiting, me_id) when is_binary(me_id),
    do: [
      status: :open,
      receiver_id: me_id,
      provider_id: {:not, [me_id]},
      order: [desc: :id]
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
    |> validate_name()
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

  defp run_epic(name, on, opts) do
    Bonfire.Epics.run_epic(__MODULE__, name, Keyword.put(opts, :on, on))
  end

  # one `:create_item` epic per line, inside the caller's transaction, stopping at the first error, which rolls the whole batch back. Increasing ids keep the written order (`Needle.ULID` only orders by the millisecond)
  defp insert_items(items, list_id, opts) do
    now = System.system_time(:millisecond)

    items
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {item, i}, {:ok, acc} ->
      attrs = Map.merge(item, %{input_of_id: list_id, id: Needle.ULID.generate(now + i)})

      case run_epic(:create_item, :task, Keyword.put(opts, :task_attrs, attrs)) do
        {:ok, task} -> {:cont, {:ok, [task | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, items} -> {:ok, Enum.reverse(items)}
      error -> error
    end
  end

  # the lines as items, or an error before anything is created (see `create_list/3`)
  defp check_lines(lines) do
    items = parse_lines(lines)

    if Enum.any?(items, &(String.length(&1.name) > 255)),
      do: {:error, :item_name_too_long},
      else: {:ok, items}
  end

  # `add_items/2` takes a shared lock on the list's row and `delete_list/2` an exclusive one, so they can't interleave. Both read the row again, so a list deleted meanwhile is `:not_found`
  defp share_lock_list(nil), do: :ok

  # also refuses a list closed since `list_in_group/3` read it: a closed list takes no new items (Ivan, 2026-11-09)
  defp share_lock_list(list_id) do
    case repo().one(
           from(p in ValueFlows.Process,
             where: p.id == ^list_id and is_nil(p.deleted_at),
             lock: "FOR SHARE",
             select: p.finished
           )
         ) do
      nil -> {:error, :not_found}
      true -> {:error, :list_closed}
      _open -> :ok
    end
  end

  defp update_lock_list(list_id),
    do: locked(from(p in ValueFlows.Process, where: p.id == ^list_id and is_nil(p.deleted_at), lock: "FOR UPDATE", select: p.id))

  defp locked(query), do: if(repo().one(query), do: :ok, else: {:error, :not_found})

  # an open list the user can see in this group, or `nil` for no list: a closed list takes no new items (Ivan, 2026-11-09)
  defp list_in_group(nil, _group_id, _me), do: {:ok, nil}

  defp list_in_group(list_id, group_id, me) do
    case fetch_list(list_id, me) do
      {:ok, %{context_id: ^group_id, finished: true}} -> {:error, :list_closed}
      {:ok, %{context_id: ^group_id} = list} -> {:ok, list}
      {:ok, _elsewhere} -> {:error, :list_not_in_group}
      error -> error
    end
  end

  defp lists_query(me) do
    from(p in ValueFlows.Process, as: :process, where: is_nil(p.deleted_at))
    |> boundarise(process.id, current_user: me)
  end

  defp fetch_list(list_id, me) do
    case lists_query(me) |> where([process: p], p.id == ^list_id) |> repo().one() do
      nil -> {:error, :not_found}
      list -> {:ok, list}
    end
  end

  # read through the list's boundaries first, as `fetch_to_triage/2` does for a task
  defp triage_list(list_id, attrs, opts) do
    me = Bonfire.Common.Utils.current_user(opts)

    with {:ok, list} <- fetch_list(list_id, me) do
      if Bonfire.Boundaries.can?(me, :tag, list.context_id) do
        # not `Processes.update/2`, which federates an Update
        list
        |> ValueFlows.Process.update_changeset(attrs)
        |> validate_name()
        |> repo().update()
      else
        {:error, :not_permitted}
      end
    end
  end

  defp may_own(user_id, group_id),
    do: if(may_own?(user_id, group_id), do: :ok, else: {:error, :owner_not_a_member})

  defp may_delete(me, task),
    do: if(may_delete?(me, task), do: :ok, else: {:error, :not_permitted})
end
