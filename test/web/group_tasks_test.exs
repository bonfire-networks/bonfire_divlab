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
      task!(ivan, group, "Call the printer", provider_id: mayel.id)

      session = conn(user: ivan, account: account) |> visit(path <> "/inbox")

      for tab <- ~w(inbox mine waiting),
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

    # `/tasks` now opens on Lists (tasks-v2 §1, lists_web_test.exs); Mine keeps its own path
    test "Mine shows my open tasks only", %{
      account: account,
      ivan: ivan,
      group: group,
      path: path
    } do
      task!(ivan, group, "Fix the gate", provider_id: ivan.id)
      task!(ivan, group, "Water the plants")

      conn(user: ivan, account: account)
      |> visit(path <> "/mine")
      |> assert_has("#tasks_tab_mine[aria-current=page]")
      |> assert_has("#tasks_list", text: "Fix the gate")
      |> refute_has("#tasks_list", text: "Water the plants")
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
      task = task!(ivan, group, "Fix the gate", provider_id: ivan.id)

      session =
        conn(user: ivan, account: account)
        |> visit(path <> "/mine")
        |> click_button("#task_#{task.id}_done", "Mark done")
        |> refute_has("#task_#{task.id}")

      for view <- ~w(inbox mine waiting),
          do: session |> visit("#{path}/#{view}") |> refute_has("#task_#{task.id}")
    end

    # the owner menu is Bonfire's LiveSelect user picker (`TaskOwnerPickerLive`), driven as `group_settings_overview_test.exs` drives the add-person picker (`pick_owner/3` below)
    test "the owner menu gives the task to a member: it's in their Mine and my Waiting on",
         %{account: account, ivan: ivan, mayel: mayel, group: group, path: path} do
      task = task!(ivan, group, "Call the printer")

      {:ok, view, _html} = live(conn(user: ivan, account: account), path <> "/inbox")

      pick_owner(view, task, mayel)

      refute has_element?(view, "#task_#{task.id}")
      assert names(:mine, mayel, group) == ["Call the printer"]
      assert names(:waiting, ivan, group) == ["Call the printer"]
    end

    test "the owner menu's search offers only the group's members",
         %{account: account, ivan: ivan} do
      member = fake_user!(account, %{name: "zqownermember"})
      _outsider = fake_user!(account, %{name: "zqowneroutsider"})
      group = tasks_group!(ivan, [member])
      task = task!(ivan, group, "Call the printer")

      {:ok, view, _html} =
        live(conn(user: ivan, account: account), "/&#{group.character.username}/tasks/inbox")

      ls_id =
        live_select_simulate_search(
          view,
          "#task_#{task.id}_assign",
          "zqowner",
          "owner_#{task.id}_owner_live_select_component"
        )

      assert has_element?(view, "##{ls_id} li", "zqownermember"), "control: a member is offered"
      refute has_element?(view, "##{ls_id} li", "zqowneroutsider"), "someone outside the group"
    end

    test "the server refuses an owner who isn't a member",
         %{account: account, ivan: ivan, group: group, path: path} do
      task = task!(ivan, group, "Call the printer")
      outsider = fake_user!(account)
      {:ok, view, _html} = live(conn(user: ivan, account: account), path <> "/inbox")

      pick_owner(view, task, outsider)

      assert has_element?(view, "#task_#{task.id}")
      assert names(:inbox, ivan, group) == ["Call the printer"]
    end

    test "the owner menu is one list of members, shown before typing",
         %{account: account, ivan: ivan, mayel: mayel, group: group, path: path} do
      task = task!(ivan, group, "Call the printer")
      ls_id = "owner_#{task.id}_owner_live_select_component"
      {:ok, view, _html} = live(conn(user: ivan, account: account), path <> "/inbox")

      refute has_element?(view, "datalist")

      # LiveSelect draws its list once the input has focus, before anything is typed
      view |> with_target("##{ls_id}") |> render_hook("focus", %{})

      assert has_element?(view, "##{ls_id} li", mayel.profile.name)
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

  # what LiveSelect sends when someone is picked in a row's owner menu
  defp pick_owner(view, task, user) do
    form = "owner_#{task.id}"

    view
    |> element("#task_#{task.id}_assign")
    |> render_change(%{
      "_target" => [form, "owner"],
      form => %{"owner" => Jason.encode!(%{"id" => user.id})}
    })
  end
end
