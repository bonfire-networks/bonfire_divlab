defmodule Bonfire.Divlab.Web.GroupTasksTest do
  @moduledoc "The group's Tasks page: its two views, Lists and My tasks, and what a row does (step 8 in tasks-v1.md)."
  use Bonfire.Divlab.ConnCase, async: false

  import Bonfire.Divlab.TasksFixtures

  alias Bonfire.Divlab.Tasks

  require Ecto.Query

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
    test "Lists counts the open lists, My tasks counts my open tasks and shows only those",
         %{account: account, ivan: ivan, mayel: mayel, group: group, path: path} do
      task!(mayel, group, "Water the plants")
      task!(ivan, group, "Fix the gate", provider_id: ivan.id)
      task!(ivan, group, "Call the printer", provider_id: mayel.id)
      opts = [current_user: ivan, context_id: group.id, boundary: "members:private"]
      {:ok, _} = Tasks.create_list(%{name: "Sprint 47"}, [], opts)
      {:ok, %{list: closed}} = Tasks.create_list(%{name: "Last year"}, [], opts)
      {:ok, _} = Tasks.close_list(closed.id, current_user: ivan)

      conn(user: ivan, account: account)
      |> visit(path)
      |> assert_has("#tasks_tab_lists [data-role=count]", text: "1")
      |> assert_has("#tasks_tab_mine [data-role=count]", text: "1")
      |> click_link("#tasks_tab_mine", "My tasks")
      |> assert_path(Bonfire.Common.URIs.path(group) <> "/tasks/mine")
      |> assert_has("#tasks_list", text: "Fix the gate")
      |> refute_has("#tasks_list", text: "Water the plants")
      |> refute_has("#tasks_list", text: "Call the printer")
    end

    # `/tasks` opens on Lists (tasks-v2 §1, lists_web_test.exs); My tasks keeps its own path
    test "My tasks shows my open tasks only", %{
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

    test "an empty My tasks says so", %{account: account, ivan: ivan, path: path} do
      conn(user: ivan, account: account)
      |> visit(path <> "/mine")
      |> assert_has("#tasks_empty")
      |> assert_has("#group_tasks_new")
    end

    # the Inbox, Waiting on and Done tabs went on 2026-11-13; their old links still land somewhere
    test "the old Inbox, Waiting on and Done links open Lists",
         %{account: account, ivan: ivan, path: path} do
      session = conn(user: ivan, account: account)

      for view <- ~w(inbox waiting done),
          do:
            session
            |> visit("#{path}/#{view}")
            |> assert_has("#tasks_tab_lists[aria-current=page]")
    end
  end

  describe "tasks outside the lists" do
    # tasks from before every task had a list (tasks-v2 §15) have no list page, so Lists shows the open ones nobody has
    test "Lists shows open tasks without a list that nobody has, and Take it puts one in My tasks",
         %{account: account, ivan: ivan, mayel: mayel, group: group, path: path} do
      loose = task!(mayel, group, "Water the plants")
      task!(mayel, group, "Fix the gate", provider_id: mayel.id)
      task!(mayel, group, "Old chore", finished: true)

      conn(user: ivan, account: account)
      |> visit(path)
      |> assert_has("#tasks_loose #task_#{loose.id}")
      |> refute_has("#tasks_loose", text: "Fix the gate")
      |> refute_has("#tasks_loose", text: "Old chore")
      |> click_button("#task_#{loose.id}_take", "Take it")
      |> refute_has("#tasks_loose")
      |> visit(path <> "/mine")
      |> assert_has("#tasks_list #task_#{loose.id}")
    end

    test "a task of mine whose list I can't see still shows in My tasks",
         %{account: account, ivan: ivan, group: group, path: path} do
      {:ok, %{list: list, items: [item]}} =
        Tasks.create_list(%{name: "Sprint 47"}, ["Write the note"],
          current_user: ivan,
          context_id: group.id,
          boundary: "members:private"
        )

      {:ok, _} = Tasks.assign(item.id, ivan.id, current_user: ivan)
      # the list alone gone, its item left: `Tasks.lists/2` no longer returns it
      list |> Ecto.Changeset.change(deleted_at: DateTime.utc_now()) |> Bonfire.Common.Repo.update!()

      conn(user: ivan, account: account)
      |> visit(path <> "/mine")
      |> assert_has("#tasks_tab_mine [data-role=count]", text: "1")
      |> assert_has("#tasks_list #task_#{item.id}")
      |> refute_has("#tasks_list a[href='/discussion/#{list.id}']")
    end
  end

  describe "a row" do
    test "Take it on a list's page puts the task in My tasks",
         %{account: account, ivan: ivan, mayel: mayel, group: group, path: path} do
      {:ok, %{list: list, items: [item]}} =
        Tasks.create_list(%{name: "Sprint 47"}, ["Water the plants"],
          current_user: mayel,
          context_id: group.id,
          boundary: "members:private"
        )

      conn(user: ivan, account: account)
      |> visit("/discussion/#{list.id}")
      |> click_button("#task_#{item.id}_take", "Take it")
      |> refute_has("#task_#{item.id}_take")
      |> visit(path <> "/mine")
      |> assert_has("#tasks_list #task_#{item.id}")
    end

    test "checking a task off takes it out of my open tasks",
         %{account: account, ivan: ivan, group: group, path: path} do
      task = task!(ivan, group, "Fix the gate", provider_id: ivan.id)

      conn(user: ivan, account: account)
      |> visit(path <> "/mine")
      |> click_button("#task_#{task.id}_done", "Mark done")
      |> refute_has("#tasks_list #task_#{task.id}")
      |> assert_has("#tasks_tab_mine [data-role=count]", text: "0")
    end

    # the owner menu is Bonfire's LiveSelect user picker (`TaskOwnerPickerLive`), driven as `group_settings_overview_test.exs` drives the add-person picker (`pick_owner/3` below)
    test "the owner menu gives my task to a member: it leaves my tasks for theirs",
         %{account: account, ivan: ivan, mayel: mayel, group: group, path: path} do
      task = task!(ivan, group, "Call the printer", provider_id: ivan.id)

      {:ok, view, _html} = live(conn(user: ivan, account: account), path <> "/mine")

      pick_owner(view, task, mayel)

      refute has_element?(view, "#task_#{task.id}")
      assert names(:mine, mayel, group) == ["Call the printer"]
      assert names(:mine, ivan, group) == []
    end

    test "the owner menu's search offers only the group's members",
         %{account: account, ivan: ivan} do
      member = fake_user!(account, %{name: "zqownermember"})
      _outsider = fake_user!(account, %{name: "zqowneroutsider"})
      group = tasks_group!(ivan, [member])
      task = task!(ivan, group, "Call the printer", provider_id: ivan.id)

      {:ok, view, _html} =
        live(conn(user: ivan, account: account), "/&#{group.character.username}/tasks/mine")

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
      task = task!(ivan, group, "Call the printer", provider_id: ivan.id)
      outsider = fake_user!(account)
      {:ok, view, _html} = live(conn(user: ivan, account: account), path <> "/mine")

      pick_owner(view, task, outsider)

      assert has_element?(view, "#task_#{task.id}")
      assert names(:mine, ivan, group) == ["Call the printer"]
    end

    test "the owner menu is one list of members, shown before typing",
         %{account: account, ivan: ivan, mayel: mayel, group: group, path: path} do
      task = task!(ivan, group, "Call the printer", provider_id: ivan.id)
      ls_id = "owner_#{task.id}_owner_live_select_component"
      {:ok, view, _html} = live(conn(user: ivan, account: account), path <> "/mine")

      refute has_element?(view, "datalist")

      # LiveSelect draws its list once the input has focus, before anything is typed
      view |> with_target("##{ls_id}") |> render_hook("focus", %{})

      assert has_element?(view, "##{ls_id} li", mayel.profile.name)
    end

    test "Nobody takes the task off its owner",
         %{account: account, ivan: ivan, group: group, path: path} do
      task = task!(ivan, group, "Call the printer", provider_id: ivan.id)

      conn(user: ivan, account: account)
      |> visit(path <> "/mine")
      |> click_button("#task_#{task.id}_unassign", "Nobody")
      |> refute_has("#task_#{task.id}")

      assert names(:inbox, ivan, group) == ["Call the printer"]
    end

    test "Delete takes the task off the page and the group's timeline",
         %{account: account, ivan: ivan, group: group, path: path} do
      task = task!(ivan, group, "Fix the gate", provider_id: ivan.id)

      conn(user: ivan, account: account)
      |> visit(path <> "/mine")
      |> click_button("#task_#{task.id}_delete", "Delete")
      |> refute_has("#task_#{task.id}")

      refute in_group_timeline?(task, group)
    end

    test "Delete is only offered to the task's creator and the group's moderators",
         %{account: account, ivan: ivan, mayel: mayel, group: group, path: path} do
      ivans = task!(ivan, group, "Fix the gate", provider_id: mayel.id)
      mayels = task!(mayel, group, "Water the plants", provider_id: mayel.id)

      conn(user: mayel, account: account)
      |> visit(path <> "/mine")
      |> refute_has("#task_#{ivans.id}_delete")
      |> assert_has("#task_#{mayels.id}_delete")
    end
  end

  describe "Done" do
    test "a task I check off is in my Done, under My tasks, with a count",
         %{account: account, ivan: ivan, group: group, path: path} do
      task = task!(ivan, group, "Fix the gate", provider_id: ivan.id)

      conn(user: ivan, account: account)
      |> visit(path <> "/mine")
      |> click_button("#task_#{task.id}_done", "Mark done")
      |> assert_has("#tasks_done [data-role=count]", text: "1")
      |> assert_has("#tasks_done #task_#{task.id}[data-done]")
    end

    test "checking a task in my Done reopens it",
         %{account: account, ivan: ivan, group: group, path: path} do
      task = task!(ivan, group, "Fix the gate", provider_id: ivan.id)
      {:ok, _} = Tasks.done(task.id, current_user: ivan)

      conn(user: ivan, account: account)
      |> visit(path <> "/mine")
      |> click_button("#task_#{task.id}_reopen", "Mark not done")
      |> assert_has("#tasks_list #task_#{task.id}")
      |> refute_has("#tasks_done")
    end

    # `Tasks.list(:mine_done, …)` stops at the latest 50
    test "my Done counts 50+ once it reaches the latest 50",
         %{account: account, ivan: ivan, group: group, path: path} do
      {:ok, items} =
        Tasks.add_items(Enum.map(1..50, &"Done #{&1}"),
          current_user: ivan,
          context_id: group.id,
          boundary: "members:private",
          list_id: nil
        )

      Bonfire.Common.Repo.update_all(
        Ecto.Query.where(ValueFlows.Planning.Intent, [i], i.id in ^Enum.map(items, & &1.id)),
        set: [provider_id: ivan.id, finished: true]
      )

      conn(user: ivan, account: account)
      |> visit(path <> "/mine")
      |> assert_has("#tasks_done [data-role=count]", text: "50+")
    end
  end

  # the PreviewActivity hook opens the discussion in the preview modal, which is JS these tests can't run; this checks what it's given
  test "a row opens the task's discussion in the preview",
       %{account: account, ivan: ivan, group: group, path: path} do
    task = task!(ivan, group, "Fix the gate", provider_id: ivan.id)

    conn(user: ivan, account: account)
    |> visit(path <> "/mine")
    |> assert_has(
      "#task_#{task.id}[phx-hook='Bonfire.UI.Common.PreviewContentLive#PreviewActivity'][data-href='/discussion/#{task.id}']"
    )
    |> assert_has("#task_#{task.id} a[href='/discussion/#{task.id}']")
  end

  test "a non-member and a guest see no tasks of a private group",
       %{account: account, ivan: ivan, group: group, path: path} do
    task!(ivan, group, "Fix the gate", provider_id: ivan.id)
    outsider = fake_user!(account)

    for session <- [conn(user: outsider, account: account), conn()] do
      session
      |> visit(path <> "/mine")
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
