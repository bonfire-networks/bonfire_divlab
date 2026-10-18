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
    provider = fake_user!()
    outsider = fake_user!()

    group =
      Simulate.fake_group!(owner, %{
        visibility: "members:private",
        default_content_visibility: "members:private"
      })

    {:ok, _} = Categories.add_member(owner, group, member)
    {:ok, _} = Categories.add_member(owner, group, provider)
    {:ok, _} = Tasks.set_enabled(group, true, current_user: owner)

    %{owner: owner, member: member, provider: provider, outsider: outsider, group: group}
  end

  describe "create/1 in a private group" do
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

    test "refuses an owner who isn't a member of the group",
         %{member: member, outsider: outsider, group: group} do
      assert {:error, message} =
               create_task(member, group, "members:private", %{provider_id: outsider.id})

      assert message =~ "owner_not_a_member"
    end

    test "checks the owner on the task the epic built, whichever option its attrs came from",
         %{member: member, outsider: outsider, group: group} do
      changeset =
        ValueFlows.Planning.Intent.create_changeset(member, %{
          name: "fix the gate",
          action_id: "work",
          context_id: group.id,
          provider_id: outsider.id
        })

      epic =
        Bonfire.Divlab.Acts.RequireGroup.run(
          %Bonfire.Epics.Epic{
            assigns: %{
              options: [current_user: member, context_id: group.id],
              categories_auto_boost: [group],
              task: changeset
            }
          },
          %Bonfire.Epics.Act{module: Bonfire.Divlab.Acts.RequireGroup, options: [on: :task]}
        )

      assert Enum.any?(epic.errors, &(&1.error == :owner_not_a_member))
    end

    test "makes the creator the receiver of a task for someone else",
         %{member: member, provider: provider, group: group} do
      {:ok, task} = create_task(member, group, "members:private", %{provider_id: provider.id})

      assert task.receiver_id == member.id
    end

    test "sets no receiver on a task the creator gives themselves", %{
      member: member,
      group: group
    } do
      {:ok, task} = create_task(member, group, "members:private", %{provider_id: member.id})

      assert is_nil(task.receiver_id)
    end
  end

  describe "create/1 side effects in a private group" do
    test "puts the task on the group's timeline, like a post", %{member: member, group: group} do
      {:ok, task} = create_task(member, group)

      assert in_group_timeline?(task, group)
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

  describe "create/1 in a public group" do
    setup %{owner: owner, member: member} do
      group = Simulate.fake_group!(owner)

      :ok =
        Bonfire.Classify.Boundaries.replace(group, owner, %{
          membership: "open",
          visibility: "global",
          participation: "anyone",
          default_content_visibility: "public"
        })

      {:ok, _} = Categories.add_member(owner, group, member)
      {:ok, _} = Tasks.set_enabled(group, true, current_user: owner)
      %{public_group: group}
    end

    test "gives the task the same ACLs as a post in the group",
         %{member: member, public_group: group} do
      {:ok, task} = create_task(member, group, "public")
      {:ok, post} = publish_post(member, group, "public")

      assert acl_ids(task) == acl_ids(post)
    end

    test "doesn't federate the task or the group's boost of it, even where a post's are",
         %{member: member, public_group: group} do
      {:ok, task} = create_task(member, group, "public")
      {:ok, post} = publish_post(member, group, "public")
      {:ok, task_boost} = Boosts.get(group, task, skip_boundary_check: true)
      {:ok, post_boost} = Boosts.get(group, post, skip_boundary_check: true)

      assert {:ok, _} = ActivityPub.Object.get_cached(pointer: post),
             "control: the post federates"

      assert {:ok, _} = ActivityPub.Object.get_cached(pointer: post_boost),
             "control: the group's boost of the post is announced"

      assert {:error, :not_found} = ActivityPub.Object.get_cached(pointer: task)
      assert {:error, :not_found} = ActivityPub.Object.get_cached(pointer: task_boost)
    end
  end

  describe "create/1 notifications" do
    test "notifies the owner when someone else creates the task for them",
         %{member: member, provider: provider, group: group} do
      {:ok, task} = create_task(member, group, "members:private", %{provider_id: provider.id})

      assert activity = FeedLoader.feed_contains?(:notifications, task, current_user: provider)
      assert activity.verb_id == Bonfire.Boundaries.Verbs.get(:assign)[:id]

      Oban.Testing.assert_enqueued(Bonfire.Common.Repo,
        worker: Bonfire.Notify.Worker,
        args: %{
          "op" => "fan_out",
          "recipients" => [%{"user_id" => provider.id, "feed" => "notifications"}]
        }
      )
    end

    test "doesn't notify the creator about a task they own", %{member: member, group: group} do
      {:ok, _task} = create_task(member, group, "members:private", %{provider_id: member.id})

      Oban.Testing.refute_enqueued(Bonfire.Common.Repo,
        worker: Bonfire.Notify.Worker,
        args: %{"recipients" => [%{"user_id" => member.id, "feed" => "notifications"}]}
      )
    end
  end

  defp create_task(user, group, boundary \\ "members:private", attrs \\ %{}) do
    Tasks.create(
      current_user: user,
      context_id: group.id,
      boundary: boundary,
      task_attrs: Map.merge(%{name: "Water the plants"}, attrs)
    )
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
