defmodule Bonfire.Divlab.TasksFixtures do
  @moduledoc "Groups and tasks for the task tests."

  alias Bonfire.Classify.Categories
  alias Bonfire.Classify.Simulate
  alias Bonfire.Divlab.Tasks

  @doc "A private group created by `owner`, with `members` added."
  def private_group!(owner, members) do
    group =
      Simulate.fake_group!(owner, %{
        visibility: "members:private",
        default_content_visibility: "members:private"
      })

    for member <- members,
        do: {:ok, _} = Categories.add_member(owner, group, member, skip_boundary_check: true)

    group
  end

  @doc "A private group with Tasks turned on, which creating a task needs."
  def tasks_group!(owner, members) do
    group = private_group!(owner, members)
    {:ok, _} = Tasks.set_enabled(group, true, current_user: owner)
    group
  end

  @doc """
  A task named `name` that `user` adds to `group` with no list, then with any other Intent fields in `attrs` set directly (`provider_id`, `receiver_id`, `finished`, `note`), so a test can start from any state. Giving it to someone else makes `user` its receiver, as `Tasks.assign/3` does.
  """
  def task!(user, group, name, attrs \\ []) do
    # task ids are ULIDs, which only order by the millisecond (`Needle.ULID.generate/1`), so a millisecond apart keeps "newest first" deterministic
    Process.sleep(1)

    {:ok, [task]} =
      Tasks.add_items([name],
        current_user: user,
        context_id: group.id,
        boundary: "members:private",
        list_id: nil
      )

    case attrs |> Map.new() |> waiting_on(user) do
      empty when empty == %{} ->
        task

      attrs ->
        task
        |> ValueFlows.Planning.Intent.update_changeset(attrs)
        |> Bonfire.Common.Repo.update!()
    end
  end

  defp waiting_on(%{provider_id: provider_id} = attrs, %{id: user_id})
       when is_binary(provider_id) and provider_id != user_id,
       do: Map.put_new(attrs, :receiver_id, user_id)

  defp waiting_on(attrs, _user), do: attrs

  @doc "The names of the tasks `user` sees in one of the Tasks tab's views, in order."
  def names(view, user, group) do
    {:ok, tasks} = Tasks.list(view, group.id, current_user: user)
    Enum.map(tasks, & &1.name)
  end

  @doc "Whether `object` is on `group`'s timeline, checked as `Bonfire.Classify.PublishInGroupTest` does."
  def in_group_timeline?(object, group),
    do:
      !!Bonfire.Social.FeedLoader.feed_contains?(:user_activities, object,
        by: group,
        current_user: group
      )
end
