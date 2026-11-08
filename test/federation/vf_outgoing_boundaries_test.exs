defmodule Bonfire.Divlab.Federation.VfOutgoingBoundariesTest do
  @moduledoc """
  `ValueFlows.Util.Federation` must respect each object's boundary when federating out: a VF object that isn't public sends nothing.

  These test `bonfire_valueflows` code from here because its own test support doesn't compile in the app, see `Bonfire.Divlab.Tasks.ReadBoundariesTest`.
  """
  use Bonfire.Divlab.DataCase, async: false

  import Bonfire.Me.Fake

  alias Bonfire.Federate.ActivityPub.AdapterUtils
  alias ValueFlows.Proposal.Proposals

  setup do
    Process.put(:federating, true)

    user = fake_user!() |> Bonfire.Common.Repo.maybe_preload([:peered, :shared_user, character: :peered])

    # ember and social compile the GraphQL schema without VF's types (`config/ember.exs:44`), so `fetch_api_object/4` crashes there before addressing. Stubbed so that what's checked here is the addressing.
    Repatch.patch(
      ValueFlows.Util.Federation,
      :fetch_api_object,
      [mode: :shared],
      fn id, _type, _depth, _filters -> %{"__typename" => "Proposal", "id" => id, "name" => "Offer"} end
    )

    %{user: user}
  end

  # Called directly because `Outgoing.maybe_federate/3` can't reach it under test: `AdapterUtils.preload_peered/1` asks for `created: [creator: :peered]`, which on a Proposal is a date field, and `Untangle.err/2` raises in the test env (it recovers elsewhere).
  defp federate(user, proposal, verb \\ :create),
    do: Proposals.ap_publish_activity(user, verb, Bonfire.Common.Repo.maybe_preload(%{proposal | creator: user}, :peered))

  defp to_public?({:ok, %{data: data}}), do: AdapterUtils.public_uri() in List.wrap(data["to"])
  defp to_public?(_), do: false

  defp cc_followers?({:ok, %{data: data}}, user) do
    {:ok, actor} = ActivityPub.Actor.get_cached(pointer: user.id)
    actor.data["followers"] in List.wrap(data["cc"])
  end

  defp cc_followers?(_, _), do: false

  test "a public proposal federates, addressed to the public and followers", %{user: user} do
    {:ok, proposal} = Proposals.create(user, %{name: "Open offer", to_boundaries: "public"})

    result = federate(user, proposal)

    assert to_public?(result)
    assert cc_followers?(result, user)
  end

  test "a local proposal sends nothing out", %{user: user} do
    {:ok, proposal} = Proposals.create(user, %{name: "Quiet offer", to_boundaries: "local"})

    assert :ignore = federate(user, proposal)
  end

  test "an update isn't lost when federation ignores it", %{user: user} do
    {:ok, proposal} = Proposals.create(user, %{name: "Local offer", to_boundaries: "local"})

    Repatch.patch(Bonfire.Federate.ActivityPub.Outgoing, :maybe_federate, [mode: :shared], fn _, _, _ ->
      :ignore
    end)

    assert {:ok, %{name: "Renamed"}} = Proposals.update(%{proposal | creator: user}, %{name: "Renamed"})
  end
end
