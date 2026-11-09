defmodule Bonfire.Divlab.Tasks.ListsTest do
  use Bonfire.Divlab.DataCase, async: true

  import Bonfire.Me.Fake
  import Bonfire.Divlab.TasksFixtures, only: [tasks_group!: 2, in_group_timeline?: 2]
  import Ecto.Query

  alias Bonfire.Common.Repo
  alias Bonfire.Divlab.Tasks

  setup do
    owner = fake_user!()
    member = fake_user!()
    outsider = fake_user!()
    group = tasks_group!(owner, [member])

    %{owner: owner, member: member, outsider: outsider, group: group}
  end

  describe "create_list/3" do
    test "creates the list and its items, each in the list", %{member: member, group: group} do
      {:ok, %{list: list, items: items}} =
        Tasks.create_list(%{name: "Sprint 47"}, ["Write the note", "Archive the pad"], opts(member, group))

      assert %ValueFlows.Process{name: "Sprint 47"} = list
      assert Enum.map(items, & &1.name) == ["Write the note", "Archive the pad"]
      assert Enum.all?(items, &(&1.input_of_id == list.id))
    end

    test "brings `- [x]` lines in done and skips blank ones", %{member: member, group: group} do
      {:ok, %{items: items}} =
        Tasks.create_list(
          %{name: "Pad"},
          ["- [x] Call the co-op", "", "   ", "- [ ] Send the deck", "* Book the train"],
          opts(member, group)
        )

      assert Enum.map(items, &{&1.name, &1.finished}) == [
               {"Call the co-op", true},
               {"Send the deck", false},
               {"Book the train", false}
             ]
    end

    test "creates nothing when Tasks is off, or when one line fails",
         %{owner: owner, member: member, group: group} do
      too_long = String.duplicate("a", 300)

      assert {:error, _} =
               Tasks.create_list(%{name: "Half"}, ["Fine", too_long], opts(member, group))

      assert counts(group) == {0, 0}

      {:ok, _} = Tasks.set_enabled(group, false, current_user: owner)
      assert {:error, _} = Tasks.create_list(%{name: "Off"}, ["Fine"], opts(member, group))
      assert counts(group) == {0, 0}
    end

    test "hides the list and its items from non-members and guests",
         %{member: member, outsider: outsider, group: group} do
      {:ok, %{list: list}} = Tasks.create_list(%{name: "Private"}, ["Secret"], opts(member, group))

      assert {:ok, []} = Tasks.lists(group.id, current_user: outsider)
      assert {:ok, []} = Tasks.lists(group.id, current_user: nil)
      assert {:ok, []} = Tasks.items(list.id, current_user: outsider)
      assert {:error, _} = Tasks.update_list(list.id, %{name: "Mine now"}, current_user: outsider)
    end

    test "boosts the list onto the group's timeline, not its items, which each get an activity",
         %{member: member, group: group} do
      {:ok, %{list: list, items: [item | _] = items}} =
        Tasks.create_list(%{name: "Sprint"}, ["One", "Two"], opts(member, group))

      assert in_group_timeline?(list, group)
      refute in_group_timeline?(item, group)
      assert Enum.all?(items, &(activity_count(&1.id) == 1))
    end
  end

  describe "parse_lines/1" do
    test "skips bare bullets and markdown rules, reads [X] as done, and splits a text on any line break" do
      assert Tasks.parse_lines(["-", "*", "---", "***", "_ _ _", "- [X] Shout", "[ ] Quiet"]) == [
               %{name: "Shout", finished: true},
               %{name: "Quiet", finished: false}
             ]

      assert Tasks.parse_lines("One\r\nTwo\n\n- Three") ==
               [%{name: "One", finished: false}, %{name: "Two", finished: false}, %{name: "Three", finished: false}]
    end
  end

  describe "add_items/2" do
    test "adds lines to an existing list, or to no list", %{member: member, group: group} do
      {:ok, %{list: list}} = Tasks.create_list(%{name: "Sprint"}, ["One"], opts(member, group))

      {:ok, [added]} = Tasks.add_items(["Two"], opts(member, group, list_id: list.id))
      {:ok, [loose]} = Tasks.add_items(["Loose"], opts(member, group, list_id: nil))

      assert added.input_of_id == list.id
      assert is_nil(loose.input_of_id)
    end
  end

  describe "permissions" do
    test "refuses a non-member adding, editing or closing",
         %{member: member, outsider: outsider, group: group} do
      {:ok, %{list: list}} =
        Tasks.create_list(%{name: "Sprint"}, ["One"], opts(member, group))

      assert {:error, _} = Tasks.add_items(["Sneaky"], opts(outsider, group, list_id: list.id))
      assert {:error, _} = Tasks.update_list(list.id, %{name: "Renamed"}, current_user: outsider)
      assert {:error, _} = Tasks.close_list(list.id, current_user: outsider)
    end
  end

  describe "lists/2" do
    # lists have no dates (tasks-v2 §16, decision 23)
    test "orders open lists newest first, then closed lists", %{member: member, group: group} do
      create_list!(member, group, %{name: "Older"})
      create_list!(member, group, %{name: "Newer"})
      closed = create_list!(member, group, %{name: "Closed"})
      {:ok, _} = Tasks.close_list(closed.id, current_user: member)

      {:ok, lists} = Tasks.lists(group.id, current_user: member)

      assert Enum.map(lists, & &1.name) == ["Newer", "Older", "Closed"]
    end
  end

  describe "items/2" do
    test "returns a list's items in the order they were written", %{member: member, group: group} do
      {:ok, %{list: list}} =
        Tasks.create_list(%{name: "Sprint"}, ["a", "b", "c", "d", "e"], opts(member, group))

      assert {:ok, items} = Tasks.items(list.id, current_user: member)
      assert Enum.map(items, & &1.name) == ["a", "b", "c", "d", "e"]
    end
  end

  describe "close_list/2 and reopen_list/2" do
    test "closing leaves open items open, and reopening undoes it", %{member: member, group: group} do
      {:ok, %{list: list, items: [item]}} =
        Tasks.create_list(%{name: "Sprint"}, ["Left over"], opts(member, group))

      assert {:ok, %{finished: true}} = Tasks.close_list(list.id, current_user: member)
      assert {:ok, [%{id: id, finished: false}]} = Tasks.items(list.id, current_user: member)
      assert id == item.id
      assert {:ok, %{finished: false}} = Tasks.reopen_list(list.id, current_user: member)
    end

    # a closed list takes no new items (Ivan, 2026-11-09, from the tasks statechart), until it's reopened
    test "a closed list refuses new items, until it's reopened", %{member: member, group: group} do
      {:ok, %{list: list}} = Tasks.create_list(%{name: "Shipped"}, ["Done thing"], opts(member, group))
      {:ok, _} = Tasks.close_list(list.id, current_user: member)

      assert {:error, :list_closed} = Tasks.add_items(["Late"], opts(member, group, list_id: list.id))
      assert {:ok, [_]} = Tasks.items(list.id, current_user: member)

      {:ok, _} = Tasks.reopen_list(list.id, current_user: member)
      assert {:ok, [_]} = Tasks.add_items(["Late"], opts(member, group, list_id: list.id))
    end
  end

  describe "delete_list/2" do
    test "soft-deletes the list and its items, and removes all their activities",
         %{member: member, group: group} do
      {:ok, %{list: list, items: items}} =
        Tasks.create_list(%{name: "Gone"}, ["One", "Two"], opts(member, group))

      assert :ok = Tasks.delete_list(list.id, current_user: member)

      ids = [list.id | Enum.map(items, & &1.id)]
      assert Enum.all?(ids, &(activity_count(&1) == 0))
      assert {:ok, []} = Tasks.lists(group.id, current_user: member)
      assert {:ok, []} = Tasks.items(list.id, current_user: member)

      assert from(i in ValueFlows.Planning.Intent,
               where: i.id in ^ids and not is_nil(i.deleted_at),
               select: count()
             )
             |> Repo.one() == length(items)
    end
  end

  defp opts(user, group, extra \\ []),
    do: [current_user: user, context_id: group.id, boundary: "members:private"] ++ extra

  defp create_list!(user, group, attrs) do
    {:ok, %{list: list}} = Tasks.create_list(attrs, [], opts(user, group))
    list
  end

  defp counts(group) do
    {from(p in ValueFlows.Process, where: p.context_id == ^group.id, select: count()) |> Repo.one(),
     from(i in ValueFlows.Planning.Intent, where: i.context_id == ^group.id, select: count())
     |> Repo.one()}
  end

  defp activity_count(id),
    do:
      from(a in Bonfire.Data.Social.Activity, where: a.object_id == ^id, select: count())
      |> Repo.one()
end
