defmodule Bonfire.Divlab.Tasks.CreateTest do
  use Bonfire.Divlab.DataCase, async: true

  import Bonfire.Me.Fake
  import Bonfire.Divlab.TasksFixtures, only: [in_group_timeline?: 2]

  alias Bonfire.Boundaries
  alias Bonfire.Classify.Categories
  alias Bonfire.Classify.Simulate
  alias Bonfire.Divlab.Tasks
  alias Bonfire.Social.Boosts
  alias Bonfire.Social.FeedLoader

  setup do
    owner = fake_user!()
    member = fake_user!()
    outsider = fake_user!()

    group =
      Simulate.fake_group!(owner, %{
        visibility: "members:private",
        default_content_visibility: "members:private"
      })

    {:ok, _} = Categories.add_member(owner, group, member, skip_boundary_check: true)
    {:ok, _} = Tasks.set_enabled(group, true, current_user: owner)

    %{owner: owner, member: member, outsider: outsider, group: group}
  end

  describe "add_items/2 in a private group" do
    test "gives the task the same ACLs as a post in the group", %{member: member, group: group} do
      {:ok, task} = create_task(member, group)
      {:ok, post} = publish_post(member, group, "members:private")

      assert acl_ids(task) == acl_ids(post)
    end

    test "lets members read the task, not non-members or guests",
         %{member: member, outsider: outsider, group: group} do
      {:ok, task} = create_task(member, group)

      assert Boundaries.can?(member, :read, task)
      refute Boundaries.can?(outsider, :read, task)
      refute Boundaries.can?(nil, :read, task)
    end

    test "refuses a group that doesn't exist", %{member: member} do
      assert {:error, message} = create_task(member, %{id: Needle.ULID.generate()})
      assert message =~ "group_not_found_or_not_permitted"
    end

    test "refuses a creator who can't post in the group", %{outsider: outsider, group: group} do
      assert {:error, message} = create_task(outsider, group)
      assert message =~ "group_not_found_or_not_permitted"
    end

    test "refuses a group that hasn't turned Tasks on", %{
      owner: owner,
      member: member,
      group: group
    } do
      {:ok, _} = Tasks.set_enabled(group, false, current_user: owner)

      assert {:error, message} = create_task(member, group)
      assert message =~ "tasks_not_enabled"
    end
  end

  describe "add_items/2 side effects in a private group" do
    # tasks-v2 decision 10: items skip the group's boost, lists keep it (lists_test.exs)
    test "keeps the task off the group's timeline: the group doesn't boost items",
         %{member: member, group: group} do
      {:ok, task} = create_task(member, group)

      refute in_group_timeline?(task, group)
    end

    test "keeps the task off the group's Moderation page",
         %{owner: owner, member: member, group: group} do
      {:ok, task} = create_task(member, group)
      %{character: character} = Bonfire.Common.Repo.maybe_preload(group, :character)

      feed =
        FeedLoader.feed(
          %{
            feed_ids: [character.notifications_id, character.inbox_id],
            show_objects_only_once: false
          },
          current_user: owner
        )

      # feed_contains?/3 is false for a feed that failed to load, so make sure it loaded
      assert %{edges: _} = feed
      refute FeedLoader.feed_contains?(feed, task, current_user: owner)
    end

    test "shows the task in the Local feed to members only",
         %{member: member, outsider: outsider, group: group} do
      {:ok, task} = create_task(member, group)

      assert FeedLoader.feed_contains?(:local, task, current_user: member)
      refute FeedLoader.feed_contains?(:local, task, current_user: outsider)
    end
  end

  describe "add_items/2 in a public group" do
    setup %{owner: owner, member: member} do
      group = Simulate.fake_group!(owner)

      :ok =
        Bonfire.Classify.Boundaries.replace(group, owner, %{
          membership: "open",
          visibility: "global",
          participation: "anyone",
          default_content_visibility: "public"
        })

      {:ok, _} = Categories.add_member(owner, group, member, skip_boundary_check: true)
      {:ok, _} = Tasks.set_enabled(group, true, current_user: owner)
      %{public_group: group}
    end

    test "gives the task the same ACLs as a post in the group",
         %{member: member, public_group: group} do
      {:ok, task} = create_task(member, group, "public")
      {:ok, post} = publish_post(member, group, "public")

      assert acl_ids(task) == acl_ids(post)
    end

    test "doesn't federate the task, and the group doesn't boost it, even where a post's are",
         %{member: member, public_group: group} do
      {:ok, task} = create_task(member, group, "public")
      {:ok, post} = publish_post(member, group, "public")
      {:ok, post_boost} = Boosts.get(group, post, skip_boundary_check: true)

      assert {:ok, _} = ActivityPub.Object.get_cached(pointer: post),
             "control: the post federates"

      assert {:ok, _} = ActivityPub.Object.get_cached(pointer: post_boost),
             "control: the group's boost of the post is announced"

      assert {:error, :not_found} = ActivityPub.Object.get_cached(pointer: task)
      refute match?({:ok, _}, Boosts.get(group, task, skip_boundary_check: true))
    end
  end

  # one item with no list, through the same epic a list's items use
  defp create_task(user, group, boundary \\ "members:private") do
    with {:ok, [task]} <-
           Tasks.add_items(["Water the plants"],
             current_user: user,
             context_id: group.id,
             boundary: boundary,
             list_id: nil
           ),
         do: {:ok, task}
  end

  defp publish_post(user, group, boundary) do
    Bonfire.Posts.publish(
      current_user: user,
      context_id: group.id,
      boundary: boundary,
      post_attrs: %{post_content: %{html_body: "<p>A post in the group</p>"}}
    )
  end

  defp acl_ids(object) do
    object
    |> Bonfire.Common.Repo.maybe_preload(:controlled)
    |> Map.get(:controlled)
    |> Enum.map(& &1.acl_id)
    |> Enum.sort()
  end
end
