-module(bigset_handoff_test).

-export([confirm/0]).

-define(SET, <<"test_set">>).

-include_lib("eunit/include/eunit.hrl").

confirm() ->
    lager:info("Testing handoff"),

    lager:info("Start cluster"),


    Config = [{riak_core, [ {ring_creation_size, 16},
                            {vnode_management_timer, 1000} ]}],

    [N1, N2]=Nodes = rt:deploy_nodes(2, Config, [bigset]),
    rt:join_cluster(Nodes),

    N1Client = bigset_client:new(N1),
    N2Client = bigset_client:new(N2),

    %% add some data
    ok = bigset_client:update(?SET, [<<"1">>, <<"2">>, <<"3">>, <<"4">>, <<"5">>], N1Client),
    ok = bigset_client:update(?SET, [<<"6">>], N2Client),

    E1 = read(N1Client),
    E2 = read(N2Client),

    ?assertEqual(E1, E2),

    lager:info("partition"),
    %% partition the cluster

    PartInfo = rt:partition([N1], [N2]),

    lager:info("update ~p", [N1]),
    %% add and remove from one side only
    ToRem = lists:keyfind(<<"1">>, 1, E1), %% contains the ctx

    ?assertNotEqual(false, ToRem),

    ok = bigset_client:update(?SET, [<<"7">>], [ToRem], [], N1Client),

    PRead = read(N1Client),

    ?assertMatch({_, _}, lists:keyfind(<<"7">>, 1, PRead)),
    ?assertEqual(false, lists:keyfind(<<"1">>, 1, PRead)),

    %% @TODO(rdb) add tunable R for reads, or not_found_ok=false
    ?assertEqual(E2, read(N2Client)), %% ie no change yet (partitioned)

    %% Heal and wait for hand-off
    lager:info("Healing"),

    ok = rt:heal(PartInfo),
    ok = rt:wait_for_cluster_service(Nodes, bigset),

    rt:wait_until_no_pending_changes([N1, N2]),
    rt:wait_until_transfers_complete([N1]),
    rt:wait_until_transfers_complete([N2]),

    %% re-partition, and read the side that was not written too (since
    %% that is the only way to get a read without the updated node

    lager:info("Partition again"),
    PartInfo = rt:partition([N1], [N2]),

    lager:info("fetch and verify from ~p", [N2Client]),
    Res  = bigset_client:read(?SET, [], N2Client),
    {ok, {ctx, undefined}, {elems, E3}} = Res,
    ?assertMatch({_, _}, lists:keyfind(<<"7">>, 1, E3)),
    %% Remove should have been propagated by hand off
    ?assertEqual(false, lists:keyfind(<<"1">>, 1, E3)),

    pass.

read(Client) ->
    {ok, {ctx, undefined}, {elems, E1}} = bigset_client:read(?SET, [], Client),
    E1.
