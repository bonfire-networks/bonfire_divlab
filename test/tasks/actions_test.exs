defmodule Bonfire.Divlab.Tasks.ActionsTest do
  @moduledoc "Assign, done, set date and delete on a group's tasks (step 5 in tasks-v1.md)."
  use Bonfire.Divlab.DataCase, async: true

  import Bonfire.Me.Fake
  import Bonfire.Divlab.TasksFixtures

  alias Bonfire.Divlab.Tasks

  setup do
    owner = fake_user!()
    ivan = fake_user!()
    mayel = fake_user!()

    %{
      owner: owner,
      ivan: ivan,
      mayel: mayel,
      outsider: fake_user!(),
      group: tasks_group!(owner, [ivan, mayel])
    }
  end

  describe "assign/3" do
    test "taking an Inbox task moves it to my Mine", %{mayel: mayel, ivan: ivan, group: group} do
      task = task!(mayel, group, "water the plants")

      assert {:ok, _} = Tasks.assign(task.id, ivan.id, current_user: ivan)
      assert names(:mine, ivan, group) == ["water the plants"]
      assert names(:inbox, ivan, group) == []
    end

    test "refuses an owner who isn't a member of the group",
         %{ivan: ivan, outsider: outsider, group: group} do
      task = task!(ivan, group, "water the plants")

      assert {:error, :owner_not_a_member} =
               Tasks.assign(task.id, outsider.id, current_user: ivan)

      assert names(:inbox, ivan, group) == ["water the plants"]
    end

    test "Ivan assigns a task to Mayel: it's in Ivan's Waiting on and Mayel's Mine",
         %{ivan: ivan, mayel: mayel, group: group} do
      task = task!(ivan, group, "fix the pump")

      assert {:ok, assigned} = Tasks.assign(task.id, mayel.id, current_user: ivan)
      assert assigned.receiver_id == ivan.id
      assert names(:waiting, ivan, group) == ["fix the pump"]
      assert names(:mine, mayel, group) == ["fix the pump"]
    end

    test "keeps the receiver someone already set",
         %{owner: owner, ivan: ivan, mayel: mayel, group: group} do
      task = task!(mayel, group, "order seeds", receiver_id: mayel.id)

      assert {:ok, assigned} = Tasks.assign(task.id, owner.id, current_user: ivan)
      assert assigned.receiver_id == mayel.id
    end

    test "refuses someone who can't post in the group",
         %{ivan: ivan, outsider: outsider, group: group} do
      task = task!(ivan, group, "fix the pump")

      assert {:error, _} = Tasks.assign(task.id, outsider.id, current_user: outsider)
    end
  end

  describe "done/2" do
    test "takes the task off every view", %{ivan: ivan, mayel: mayel, group: group} do
      task = task!(ivan, group, "sweep", provider_id: ivan.id, due: in_days(1))

      assert {:ok, _} = Tasks.done(task.id, current_user: mayel)

      for view <- [:inbox, :mine, :waiting, :due_soon],
          do: assert(names(view, ivan, group) == [], "still in #{view}")
    end

    test "refuses someone who can't post in the group",
         %{ivan: ivan, outsider: outsider, group: group} do
      task = task!(ivan, group, "sweep")

      assert {:error, _} = Tasks.done(task.id, current_user: outsider)
    end
  end

  describe "set_due/3" do
    test "puts an undated task in Due soon", %{ivan: ivan, mayel: mayel, group: group} do
      task = task!(ivan, group, "call the plumber")

      assert {:ok, _} = Tasks.set_due(task.id, in_days(2), current_user: mayel)
      assert names(:due_soon, ivan, group) == ["call the plumber"]
    end

    test "refuses someone who can't post in the group",
         %{ivan: ivan, outsider: outsider, group: group} do
      task = task!(ivan, group, "call the plumber")

      assert {:error, _} = Tasks.set_due(task.id, in_days(2), current_user: outsider)
    end
  end

  describe "unassign/2" do
    test "puts the task back in the Inbox", %{ivan: ivan, mayel: mayel, group: group} do
      task = task!(ivan, group, "call the printer", provider_id: mayel.id)

      assert {:ok, _} = Tasks.unassign(task.id, current_user: ivan)
      assert names(:inbox, ivan, group) == ["call the printer"]
      assert names(:mine, mayel, group) == []
    end

    test "forgets who was waiting on it, so whoever takes it next isn't in their Waiting on",
         %{owner: owner, ivan: ivan, mayel: mayel, group: group} do
      task = task!(ivan, group, "call the printer", provider_id: mayel.id)
      {:ok, _} = Tasks.unassign(task.id, current_user: mayel)
      {:ok, _} = Tasks.assign(task.id, owner.id, current_user: owner)

      assert names(:waiting, ivan, group) == []
    end

    test "refuses someone who can't post in the group",
         %{ivan: ivan, mayel: mayel, outsider: outsider, group: group} do
      task = task!(ivan, group, "call the printer", provider_id: mayel.id)

      assert {:error, _} = Tasks.unassign(task.id, current_user: outsider)
      assert names(:mine, mayel, group) == ["call the printer"]
    end
  end

  describe "reopen/2" do
    test "puts a finished task back in its view", %{ivan: ivan, group: group} do
      task = task!(ivan, group, "fix the gate", provider_id: ivan.id)
      {:ok, _} = Tasks.done(task.id, current_user: ivan)

      assert {:ok, _} = Tasks.reopen(task.id, current_user: ivan)
      assert names(:mine, ivan, group) == ["fix the gate"]
      assert names(:done, ivan, group) == []
    end

    test "refuses someone who can't post in the group",
         %{ivan: ivan, outsider: outsider, group: group} do
      task = task!(ivan, group, "fix the gate", provider_id: ivan.id)
      {:ok, _} = Tasks.done(task.id, current_user: ivan)

      assert {:error, _} = Tasks.reopen(task.id, current_user: outsider)
      assert names(:done, ivan, group) == ["fix the gate"]
    end
  end

  describe "clear_due/2" do
    test "takes the task off Due soon", %{ivan: ivan, group: group} do
      task = task!(ivan, group, "fix the gate", provider_id: ivan.id, due: in_days(1))

      assert {:ok, _} = Tasks.clear_due(task.id, current_user: ivan)
      assert names(:due_soon, ivan, group) == []
      assert names(:mine, ivan, group) == ["fix the gate"]
    end
  end

  describe "delete/2" do
    test "lets the creator delete the task, which leaves every view",
         %{ivan: ivan, group: group} do
      task = task!(ivan, group, "old idea")

      assert {:ok, _} = Tasks.delete(task.id, current_user: ivan)
      assert names(:inbox, ivan, group) == []
    end

    test "lets a group moderator delete someone else's task",
         %{owner: owner, ivan: ivan, group: group} do
      task = task!(ivan, group, "old idea")

      assert {:ok, _} = Tasks.delete(task.id, current_user: owner)
    end

    test "refuses another member", %{ivan: ivan, mayel: mayel, group: group} do
      task = task!(ivan, group, "old idea")

      assert {:error, _} = Tasks.delete(task.id, current_user: mayel)
      assert names(:inbox, ivan, group) == ["old idea"]
    end

    test "takes the task off the group's timeline", %{ivan: ivan, group: group} do
      task = task!(ivan, group, "Fix the gate")
      assert in_group_timeline?(task, group)

      {:ok, _} = Tasks.delete(task.id, current_user: ivan)

      refute in_group_timeline?(task, group)
    end
  end
end
