defmodule Bonfire.Divlab.Web.GroupTasksTest do
  @moduledoc "The group's Tasks page: its views and what a row does (step 8 in tasks-v1.md)."
  use Bonfire.Divlab.ConnCase, async: false

  import Bonfire.Divlab.TasksFixtures

  alias Bonfire.Divlab.Tasks

  doctest Bonfire.Divlab.Web.TasksBoardLive
  doctest Bonfire.Divlab.Web.TaskRowLive

  setup do
    account = fake_account!()
    ivan = fake_user!(account)
    mayel = fake_user!(account)
    group = tasks_group!(ivan, [mayel])

    %{
      account: account,
      ivan: ivan,
      mayel: mayel,
      group: group,
      path: "/&#{group.character.username}/tasks"
    }
  end

  describe "the views" do
    test "each view lists its tasks, and each tab counts them",
         %{account: account, ivan: ivan, mayel: mayel, group: group, path: path} do
      task!(mayel, group, "Water the plants")
      task!(ivan, group, "Fix the gate", provider_id: ivan.id)
      task!(ivan, group, "Call the printer", provider_id: mayel.id, due: in_days(2))

      session = conn(user: ivan, account: account) |> visit(path <> "/inbox")

      for tab <- ~w(inbox mine waiting due_soon),
          do: assert_has(session, "#tasks_tab_#{tab} [data-role=count]", text: "1")

      session
      |> assert_has("#tasks_list", text: "Water the plants")
      |> refute_has("#tasks_list", text: "Fix the gate")
      |> click_link("#tasks_tab_mine", "Mine")
      |> assert_path(Bonfire.Common.URIs.path(group) <> "/tasks/mine")
      |> assert_has("#tasks_list", text: "Fix the gate")
      |> refute_has("#tasks_list", text: "Water the plants")
      |> click_link("#tasks_tab_waiting", "Waiting on")
      |> assert_has("#tasks_list", text: "Call the printer")
      |> assert_has("#tasks_list [data-role=task_owner]", text: mayel.profile.name)
    end

    test "/tasks opens Mine", %{account: account, ivan: ivan, group: group, path: path} do
      task!(ivan, group, "Fix the gate", provider_id: ivan.id)
      task!(ivan, group, "Water the plants")

      conn(user: ivan, account: account)
      |> visit(path)
      |> assert_has("#tasks_tab_mine[aria-current=page]")
      |> assert_has("#tasks_list", text: "Fix the gate")
      |> refute_has("#tasks_list", text: "Water the plants")
    end

    test "Due soon shows overdue tasks and the next 7 days, soonest first, and nothing later",
         %{account: account, ivan: ivan, group: group, path: path} do
      task!(ivan, group, "Overdue", provider_id: ivan.id, due: in_days(-2))
      task!(ivan, group, "This week", due: in_days(3))
      task!(ivan, group, "Next month", due: in_days(30))
      task!(ivan, group, "Undated")

      conn(user: ivan, account: account)
      |> visit(path <> "/due-soon")
      |> assert_has("#tasks_list > li:nth-child(1)", text: "Overdue")
      |> assert_has("#tasks_list > li:nth-child(1) [data-role=task_due][data-overdue]")
      |> assert_has("#tasks_list > li:nth-child(2)", text: "This week")
      |> refute_has("#tasks_list > li:nth-child(2) [data-role=task_due][data-overdue]")
      |> refute_has("#tasks_list", text: "Next month")
      |> refute_has("#tasks_list", text: "Undated")
    end

    test "an empty view says so", %{account: account, ivan: ivan, path: path} do
      conn(user: ivan, account: account)
      |> visit(path <> "/inbox")
      |> assert_has("#tasks_empty")
      |> assert_has("#group_tasks_new")
    end
  end

  describe "a row" do
    test "Take it moves a task from the Inbox to Mine",
         %{account: account, ivan: ivan, mayel: mayel, group: group, path: path} do
      task = task!(mayel, group, "Water the plants")

      conn(user: ivan, account: account)
      |> visit(path <> "/inbox")
      |> click_button("#task_#{task.id}_take", "Take it")
      |> refute_has("#task_#{task.id}")
      |> click_link("#tasks_tab_mine", "Mine")
      |> assert_has("#task_#{task.id}")
    end

    test "checking a task off takes it off every view",
         %{account: account, ivan: ivan, group: group, path: path} do
      task = task!(ivan, group, "Fix the gate", provider_id: ivan.id, due: in_days(1))

      session =
        conn(user: ivan, account: account)
        |> visit(path <> "/mine")
        |> click_button("#task_#{task.id}_done", "Mark done")
        |> refute_has("#task_#{task.id}")

      for view <- ~w(inbox mine waiting due-soon),
          do: session |> visit("#{path}/#{view}") |> refute_has("#task_#{task.id}")
    end

    test "the owner menu gives the task to a member: it's in their Mine and my Waiting on",
         %{account: account, ivan: ivan, mayel: mayel, group: group, path: path} do
      task = task!(ivan, group, "Call the printer")

      conn(user: ivan, account: account)
      |> visit(path <> "/inbox")
      |> click_button("#task_#{task.id}_owner_#{mayel.id}", mayel.profile.name)
      |> refute_has("#task_#{task.id}")

      assert names(:mine, mayel, group) == ["Call the printer"]
      assert names(:waiting, ivan, group) == ["Call the printer"]
    end

    test "the owner menu's search assigns the member typed in",
         %{account: account, ivan: ivan, mayel: mayel, group: group, path: path} do
      task = task!(ivan, group, "Call the printer")

      conn(user: ivan, account: account)
      |> visit(path <> "/inbox")
      |> within("#task_#{task.id}_assign", fn session ->
        session
        |> fill_in("Owner", with: mayel.character.username)
        |> submit()
      end)

      assert names(:mine, mayel, group) == ["Call the printer"]
    end

    test "the owner menu offers only members, and the server refuses anyone else",
         %{account: account, ivan: ivan, group: group, path: path} do
      task = task!(ivan, group, "Call the printer")
      outsider = fake_user!(account)

      conn(user: ivan, account: account)
      |> visit(path <> "/inbox")
      |> refute_has("#task_#{task.id}_owner_#{outsider.id}")
      |> within("#task_#{task.id}_assign", fn session ->
        session
        |> fill_in("Owner", with: outsider.character.username)
        |> submit()
      end)
      |> assert_has("#task_#{task.id}")

      assert names(:inbox, ivan, group) == ["Call the printer"]
    end

    test "Nobody puts an assigned task back in the Inbox",
         %{account: account, ivan: ivan, mayel: mayel, group: group, path: path} do
      task = task!(ivan, group, "Call the printer", provider_id: mayel.id)

      conn(user: ivan, account: account)
      |> visit(path <> "/waiting")
      |> click_button("#task_#{task.id}_unassign", "Nobody, back to the Inbox")
      |> refute_has("#task_#{task.id}")

      assert names(:inbox, ivan, group) == ["Call the printer"]
    end

    test "Tomorrow in the date menu puts an undated task in Due soon",
         %{account: account, ivan: ivan, group: group, path: path} do
      task = task!(ivan, group, "Fix the gate", provider_id: ivan.id)

      conn(user: ivan, account: account)
      |> visit(path <> "/mine")
      |> click_button("#task_#{task.id}_due_tomorrow", "Tomorrow")
      |> click_link("#tasks_tab_due_soon", "Due soon")
      |> assert_has("#task_#{task.id} [data-role=task_due]", text: "Tomorrow")
    end

    test "a date picked in the date menu sets it",
         %{account: account, ivan: ivan, group: group, path: path} do
      task = task!(ivan, group, "Fix the gate", provider_id: ivan.id)
      in_two_days = Date.utc_today() |> Date.add(2) |> Date.to_iso8601()

      conn(user: ivan, account: account)
      |> visit(path <> "/mine")
      |> within("#task_#{task.id}_due_form", &fill_in(&1, "Pick a date", with: in_two_days))
      |> click_link("#tasks_tab_due_soon", "Due soon")
      |> assert_has("#task_#{task.id}")
    end

    test "clearing the date input takes the task off Due soon",
         %{account: account, ivan: ivan, group: group, path: path} do
      task = task!(ivan, group, "Fix the gate", provider_id: ivan.id, due: in_days(1))

      conn(user: ivan, account: account)
      |> visit(path <> "/due-soon")
      |> within("#task_#{task.id}_due_form", &fill_in(&1, "Pick a date", with: ""))
      |> refute_has("#task_#{task.id}")
    end

    test "No date takes a task off Due soon",
         %{account: account, ivan: ivan, group: group, path: path} do
      task = task!(ivan, group, "Fix the gate", provider_id: ivan.id, due: in_days(1))

      conn(user: ivan, account: account)
      |> visit(path <> "/due-soon")
      |> click_button("#task_#{task.id}_no_due", "No date")
      |> refute_has("#task_#{task.id}")
    end

    test "Delete takes the task off every view and the group's timeline",
         %{account: account, ivan: ivan, group: group, path: path} do
      task = task!(ivan, group, "Fix the gate")

      conn(user: ivan, account: account)
      |> visit(path <> "/inbox")
      |> click_button("#task_#{task.id}_delete", "Delete")
      |> refute_has("#task_#{task.id}")

      refute in_group_timeline?(task, group)
    end

    test "Delete is only offered to the task's creator and the group's moderators",
         %{account: account, ivan: ivan, mayel: mayel, group: group, path: path} do
      ivans = task!(ivan, group, "Fix the gate")
      mayels = task!(mayel, group, "Water the plants")

      conn(user: mayel, account: account)
      |> visit(path <> "/inbox")
      |> refute_has("#task_#{ivans.id}_delete")
      |> assert_has("#task_#{mayels.id}_delete")
    end
  end

  describe "Done" do
    test "a task checked off is in Done, whose tab has no count",
         %{account: account, ivan: ivan, group: group, path: path} do
      task = task!(ivan, group, "Fix the gate", provider_id: ivan.id)

      conn(user: ivan, account: account)
      |> visit(path <> "/mine")
      |> click_button("#task_#{task.id}_done", "Mark done")
      |> refute_has("#tasks_tab_done [data-role=count]")
      |> click_link("#tasks_tab_done", "Done")
      |> assert_path(Bonfire.Common.URIs.path(group) <> "/tasks/done")
      |> assert_has("#task_#{task.id}[data-done]")
    end

    test "checking a task in Done reopens it",
         %{account: account, ivan: ivan, group: group, path: path} do
      task = task!(ivan, group, "Fix the gate", provider_id: ivan.id)
      {:ok, _} = Tasks.done(task.id, current_user: ivan)

      conn(user: ivan, account: account)
      |> visit(path <> "/done")
      |> click_button("#task_#{task.id}_reopen", "Mark not done")
      |> refute_has("#task_#{task.id}")
      |> click_link("#tasks_tab_mine", "Mine")
      |> assert_has("#task_#{task.id}")
    end
  end

  # the PreviewActivity hook opens the discussion in the preview modal, which is JS these tests can't run; this checks what it's given
  test "a row opens the task's discussion in the preview",
       %{account: account, ivan: ivan, group: group, path: path} do
    task = task!(ivan, group, "Fix the gate")

    conn(user: ivan, account: account)
    |> visit(path <> "/inbox")
    |> assert_has(
      "#task_#{task.id}[phx-hook='Bonfire.UI.Common.PreviewContentLive#PreviewActivity'][data-href='/discussion/#{task.id}']"
    )
    |> assert_has("#task_#{task.id} a[href='/discussion/#{task.id}']")
  end

  test "a non-member and a guest see no tasks of a private group",
       %{account: account, ivan: ivan, group: group, path: path} do
    task!(ivan, group, "Fix the gate")
    outsider = fake_user!(account)

    for session <- [conn(user: outsider, account: account), conn()] do
      session
      |> visit(path <> "/inbox")
      |> refute_has("#group_tasks")
      |> refute_has("body", text: "Fix the gate")
    end
  end
end
