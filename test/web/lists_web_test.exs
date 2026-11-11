defmodule Bonfire.Divlab.Web.ListsWebTest do
  @moduledoc "A list's card in feeds, its own page, and the Lists tab (tasks-v2 §14)."
  use Bonfire.Divlab.ConnCase, async: false

  import Bonfire.Divlab.TasksFixtures

  alias Bonfire.Divlab.Tasks

  doctest Bonfire.Divlab.Web.Preview.ListLive

  setup do
    account = fake_account!()
    me = fake_user!(account)
    group = tasks_group!(me, [])
    opts = [current_user: me, context_id: group.id, boundary: "members:private"]

    {:ok, %{list: list, items: [first, second]}} =
      Tasks.create_list(
        %{name: "Sprint 47"},
        ["Write the note", "Archive the pad"],
        opts
      )

    %{
      account: account,
      me: me,
      group: group,
      list: list,
      first: first,
      second: second,
      opts: opts,
      path: "/&#{group.character.username}"
    }
  end

  test "in the group's feed a list shows as a list card, with its progress and first open items",
       %{account: account, me: me, list: list, first: first, path: path} do
    {:ok, _} = Tasks.done(first.id, current_user: me)

    conn(user: me, account: account)
    |> visit(path)
    |> assert_has("[data-role=list_preview]", text: "Sprint 47")
    |> assert_has("[data-role=list_preview] [data-role=list_progress]", text: "1 of 2 done")
    |> assert_has("[data-role=list_preview] [data-role=list_open_item]", text: "Archive the pad")
    |> refute_has("[data-role=list_preview] [data-role=list_open_item]", text: "Write the note")
    |> assert_has("[data-role=list_preview] a[href='/discussion/#{list.id}']")
  end

  test "a list's own page shows its items as lines, with a line to add one",
       %{account: account, me: me, list: list, first: first, second: second} do
    conn(user: me, account: account)
    |> visit("/discussion/#{list.id}")
    # its creator may edit, so the name is a line to write in too (decision 26)
    |> assert_has("#list_#{list.id}_name[value='Sprint 47']")
    |> assert_has("#task_#{first.id}_title[value='Write the note']")
    |> assert_has("#task_#{second.id}_title[value='Archive the pad']")
    |> assert_has("#list_#{list.id}_add")
  end

  test "a closed list's page has no line to add an item, since it takes none",
       %{account: account, me: me, list: list} do
    {:ok, _} = Tasks.close_list(list.id, current_user: me)

    conn(user: me, account: account)
    |> visit("/discussion/#{list.id}")
    |> assert_has("[data-role=list_page]", text: "Closed")
    |> refute_has("#list_#{list.id}_add")
  end

  # a list has no dates, only a button to close it, and a description (tasks-v2 §16, decisions 19 and 22)
  test "on the list page, the list can be closed and reopened, and the description edited",
       %{account: account, me: me, list: list} do
    conn(user: me, account: account)
    |> visit("/discussion/#{list.id}")
    |> refute_has("[data-role=list_dates_chip]")
    |> click_button("#list_#{list.id}_close", "Close list")
    |> assert_has("[data-role=list_page] header", text: "Closed")
    |> refute_has("#list_#{list.id}_add")
    |> click_button("#list_#{list.id}_reopen", "Reopen list")
    |> assert_has("#list_#{list.id}_add")
    |> PhoenixTest.unwrap(fn view ->
      view
      |> element("#list_#{list.id}_note")
      |> render_blur(%{"value" => "  What we ship  "})

      render(view)
    end)

    {:ok, [list]} = Tasks.lists(list.context_id, current_user: me)
    refute list.finished
    assert list.note == "What we ship"
  end

  # decision 26: the name is written in place, Enter or blur saves it, and a blank name is ignored
  test "on the list page, the list can be renamed in place",
       %{account: account, me: me, list: list} do
    conn(user: me, account: account)
    |> visit("/discussion/#{list.id}")
    |> assert_has("#list_#{list.id}_rename", text: "Rename")
    |> PhoenixTest.unwrap(fn view ->
      name = element(view, "#list_#{list.id}_name")
      render_keydown(name, %{"key" => "Enter", "value" => "  Sprint 48  "})
      render_blur(name, %{"value" => "   "})
      render(view)
    end)

    assert {:ok, [%{name: "Sprint 48"}]} = Tasks.lists(list.context_id, current_user: me)
  end

  test "deleting a list from its page removes it and its items, and goes back to the Tasks page",
       %{account: account, me: me, group: group, list: list} do
    conn(user: me, account: account)
    |> visit("/discussion/#{list.id}")
    |> click_button("#list_#{list.id}_delete", "Delete list")
    # the group's canonical path (`/group/<name>`), not the `/&<name>` shortcut
    |> assert_path(Bonfire.Divlab.Web.Preview.TaskLive.tasks_path(list))

    assert {:ok, []} = Tasks.lists(group.id, current_user: me)
    assert {:ok, []} = Tasks.items(list.id, current_user: me)
  end

  test "writing a line on the list page adds an item to that list",
       %{account: account, me: me, list: list} do
    conn(user: me, account: account)
    |> visit("/discussion/#{list.id}")
    |> PhoenixTest.unwrap(fn view ->
      view
      |> element("#list_#{list.id}_lines")
      |> render_hook("Bonfire.Divlab:list_add", %{
        "list_id" => list.id,
        "text" => "Book the train"
      })

      render(view)
    end)

    {:ok, items} = Tasks.items(list.id, current_user: me)
    assert List.last(items).name == "Book the train"
  end

  test "ticking an item on the list page marks it done, and the progress follows",
       %{account: account, me: me, list: list, first: first} do
    conn(user: me, account: account)
    |> visit("/discussion/#{list.id}")
    |> assert_has("[data-role=list_page] [data-role=list_progress]", text: "0 of 2 done")
    |> click_button("#task_#{first.id}_done", "Mark done")
    |> assert_has("[data-role=list_page] [data-role=list_progress]", text: "1 of 2 done")
  end

  test "the Tasks page opens on Lists, in the order Tasks.lists/2 gives",
       %{account: account, me: me, group: group, path: path} do
    {:ok, _} =
      Tasks.create_list(%{name: "Launch"}, [],
        current_user: me,
        context_id: group.id,
        boundary: "members:private"
      )

    {:ok, _} =
      Tasks.create_list(%{name: "Someday"}, [],
        current_user: me,
        context_id: group.id,
        boundary: "members:private"
      )

    session =
      conn(user: me, account: account)
      |> visit(path <> "/tasks")
      |> assert_has("#tasks_tab_lists[aria-current=page]")

    PhoenixTest.unwrap(session, fn view ->
      names =
        view
        |> render()
        |> Floki.parse_document!()
        |> Floki.find("#task_lists [data-role=list_row_name]")
        |> Enum.map(&(&1 |> Floki.text() |> String.trim()))

      assert names == ["Someday", "Launch", "Sprint 47"]
      render(view)
    end)
  end

  test "a non-member sees neither the list card nor the list page",
       %{list: list, path: path} do
    account = fake_account!()
    outsider = fake_user!(account)

    conn(user: outsider, account: account)
    |> visit("/discussion/#{list.id}")
    |> refute_has("[data-role=list_page]")

    conn(user: outsider, account: account)
    |> visit(path)
    |> refute_has("[data-role=list_preview]")
  end

  test "an item in the Inbox shows its list's name, linking to the list",
       %{account: account, me: me, list: list, first: first, path: path} do
    conn(user: me, account: account)
    |> visit(path <> "/tasks/inbox")
    |> assert_has("#task_#{first.id} [data-role=task_list]", text: "Sprint 47")
    |> assert_has("#task_#{first.id} a[data-role=task_list][href='/discussion/#{list.id}']")
  end
end
