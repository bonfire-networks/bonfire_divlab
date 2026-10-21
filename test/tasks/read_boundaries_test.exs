defmodule Bonfire.Divlab.Tasks.ReadBoundariesTest do
  @moduledoc """
  G2: valueflows' Intent queries and the GraphQL `intent`, `intents` and `intents_pages` fields only return a task to people its boundaries allow.

  These test `bonfire_valueflows` code from here because its own test support doesn't compile in the app: `ValueFlows.Test.Faking` imports `Bonfire.API.GraphQL.Test.GraphQLFields`, which `bonfire_api_graphql` only defines when Grumble is loaded, and it isn't when that extension compiles as a dependency.
  """
  use Bonfire.Divlab.DataCase, async: true

  import Bonfire.Me.Fake

  alias Bonfire.API.GraphQL.Schema
  alias Bonfire.Classify.Categories
  alias Bonfire.Classify.Simulate
  alias Bonfire.Divlab.Tasks
  alias ValueFlows.Planning.Intent.Intents

  @intent """
  query($id: ID!) {
    intent(id: $id) { id }
  }
  """

  @intents """
  query {
    intents { id }
  }
  """

  @intents_pages """
  query {
    intents_pages { edges { id } }
  }
  """

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

    {:ok, task} =
      Tasks.create(
        current_user: member,
        context_id: group.id,
        boundary: "members:private",
        task_attrs: %{name: "Water the plants"}
      )

    %{member: member, outsider: outsider, task: task}
  end

  describe "Intents.by_id/2" do
    test "returns the task to a member", %{member: member, task: task} do
      assert {:ok, %{id: id}} = Intents.by_id(task.id, member)
      assert id == task.id
    end

    test "returns nothing to a non-member or a guest", %{outsider: outsider, task: task} do
      assert {:error, :not_found} = Intents.by_id(task.id, outsider)
      assert {:error, :not_found} = Intents.by_id(task.id, nil)
    end
  end

  describe "Intents.many/1" do
    test "lists the task for a member, not for a non-member or a guest",
         %{member: member, outsider: outsider, task: task} do
      assert task.id in listed_ids(member)
      refute task.id in listed_ids(outsider)
      refute task.id in listed_ids(nil)
    end
  end

  describe "GraphQL" do
    @describetag skip:
                   "the valueflows GraphQL API is off in this app (`config :bonfire_valueflows_api_schema, modularity: :disabled` in config/ember.exs:45), so these fields aren't in the schema"

    test "`intent` returns the task to a member, not to a non-member or a guest",
         %{member: member, outsider: outsider, task: task} do
      variables = %{"id" => task.id}
      result = graphql(@intent, member, variables)

      refute result[:errors]
      assert %{"id" => id} = get_in(result, [:data, "intent"])
      assert id == task.id
      refute graphql(@intent, outsider, variables) |> get_in([:data, "intent"])
      refute graphql(@intent, nil, variables) |> get_in([:data, "intent"])
    end

    test "`intents` lists the task for a member, not for a non-member or a guest",
         %{member: member, outsider: outsider, task: task} do
      assert task.id in graphql_ids(@intents, member, ["intents"])
      refute task.id in graphql_ids(@intents, outsider, ["intents"])
      refute task.id in graphql_ids(@intents, nil, ["intents"])
    end

    test "`intents_pages` lists the task for a member, not for a non-member or a guest",
         %{member: member, outsider: outsider, task: task} do
      path = ["intents_pages", "edges"]

      assert task.id in graphql_ids(@intents_pages, member, path)
      refute task.id in graphql_ids(@intents_pages, outsider, path)
      refute task.id in graphql_ids(@intents_pages, nil, path)
    end
  end

  defp listed_ids(user) do
    {:ok, intents} = Intents.many([:default, user: user])
    Enum.map(intents, & &1.id)
  end

  defp graphql(query, user, variables \\ %{}) do
    {:ok, result} =
      Absinthe.run(query, Schema,
        variables: variables,
        context: Schema.context(%{current_user: user})
      )

    result
  end

  # a list query doesn't error for anyone: it just leaves out what they can't see
  defp graphql_ids(query, user, path) do
    result = graphql(query, user)
    refute result[:errors]

    result
    |> get_in([:data | path])
    |> List.wrap()
    |> Enum.map(& &1["id"])
  end
end
