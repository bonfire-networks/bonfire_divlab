defmodule Bonfire.Divlab.Tasks.ListTest do
  @moduledoc "The Tasks tab's four views, each a query on a group's open tasks (step 4 in tasks-v1.md)."
  use Bonfire.Divlab.DataCase, async: true

  import Bonfire.Me.Fake
  import Bonfire.Divlab.TasksFixtures

  alias Bonfire.Divlab.Tasks

  setup do
    owner = fake_user!()
    me = fake_user!()
    other = fake_user!()

    %{
      me: me,
      other: other,
      group: tasks_group!(owner, [me, other]),
      other_group: tasks_group!(owner, [me])
    }
  end

  test "Inbox lists unassigned open tasks, newest first",
       %{me: me, group: group, other_group: other_group} do
    task!(me, group, "older")
    task!(me, group, "newer")
    task!(me, group, "mine", provider_id: me.id)
    task!(me, group, "done", finished: true)
    task!(me, other_group, "elsewhere")

    assert names(:inbox, me, group) == ["newer", "older"]
  end

  # tasks have no due dates (tasks-v2 §17): Mine and Waiting on are newest first, as the Inbox is
  test "Mine lists my open tasks, newest first", %{me: me, other: other, group: group} do
    task!(me, group, "older", provider_id: me.id)
    task!(me, group, "newer", provider_id: me.id)
    task!(me, group, "done", provider_id: me.id, finished: true)
    task!(me, group, "someone else's", provider_id: other.id)

    assert names(:mine, me, group) == ["newer", "older"]
  end

  test "Waiting on lists what I asked someone else to do, newest first",
       %{me: me, other: other, group: group} do
    task!(me, group, "chase first", receiver_id: me.id, provider_id: other.id)
    task!(me, group, "chase second", receiver_id: me.id, provider_id: other.id)
    task!(me, group, "my own", receiver_id: me.id, provider_id: me.id)
    task!(me, group, "nobody yet", receiver_id: me.id)
    task!(me, group, "not mine to chase", receiver_id: other.id, provider_id: other.id)

    assert names(:waiting, me, group) == ["chase second", "chase first"]
  end

  test "Done lists finished tasks, the most recently changed first",
       %{me: me, group: group, other_group: other_group} do
    finished_last = task!(me, group, "finished last")
    finished_first = task!(me, group, "finished first")
    task!(me, group, "still open")
    elsewhere = task!(me, other_group, "elsewhere")

    for task <- [finished_first, elsewhere, finished_last],
        do: {:ok, _} = Tasks.done(task.id, current_user: me)

    assert names(:done, me, group) == ["finished last", "finished first"]
  end

  test "a guest has no Mine or Waiting on, rather than an error", %{group: group} do
    assert {:ok, []} = Tasks.list(:mine, group.id, current_user: nil)
    assert {:ok, []} = Tasks.list(:waiting, group.id, current_user: nil)
  end
end
