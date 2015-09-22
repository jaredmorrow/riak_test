%% -*- Mode: Erlang -*-
%% -------------------------------------------------------------------
%%
%% Copyright (c) 2015 Basho Technologies, Inc.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------
%% @doc A util module for riak_ts basic CREATE TABLE Actions
-module(timeseries_util).

-compile(export_all).

-include_lib("eunit/include/eunit.hrl").

-define(MAXVARCHARLEN, 16).
-define(MAXTIMESTAMP,  trunc(math:pow(2, 63))).
-define(MAXFLOAT,      math:pow(2, 63)).

confirm_create(single, DDL, Expected) ->

    ClusterSize = 1,
    lager:info("Building cluster of 1"),

    [Node] =build_cluster(ClusterSize),

    Props = io_lib:format("{\\\"props\\\": {\\\"n_val\\\": 3, \\\"table_def\\\": \\\"~s\\\"}}", [DDL]),
    Got = rt:admin(Node, ["bucket-type", "create", get_bucket(), lists:flatten(Props)]),
    ?assertEqual(Expected, Got),

    pass.

confirm_activate(single, DDL, Expected) ->
    
    [Node]  = build_cluster(1),
    {ok, _} = create_bucket(Node, DDL),
    Got     = activate_bucket(Node, DDL),
    ?assertEqual(Expected, Got),

    pass.

confirm_put(single, normal, DDL, Obj, Expected) ->

    [Node]  = build_cluster(1),
    {ok, _} = create_bucket(Node, DDL),
    {ok, _} = activate_bucket(Node, DDL),

    Bucket = list_to_binary(get_bucket()),
    io:format("writing to bucket ~p with:~n- ~p~n", [Bucket, Obj]),
    C = rt:pbc(Node),
    Get = riakc_ts:put(C, Bucket, Obj),
    ?assertEqual(Expected, Get),
    
    pass;
confirm_put(single, no_ddl, _DDL, Obj, Expected) ->
    [Node]  = build_cluster(1),
    Bucket = list_to_binary(get_bucket()),
    io:format("writing to bucket ~p with:~n- ~p~n", [Bucket, Obj]),
    C = rt:pbc(Node),
    Get = riakc_ts:put(C, Bucket, Obj),
    ?assertEqual(Expected, Get),
    
    pass.    

confirm_select(single, _DDL, _Expected) ->

    ?assertEqual(fish, fash),
    
    pass.

%%
%% Helper funs
%%

activate_bucket(Node, _DDL) ->
    rt:admin(Node, ["bucket-type", "activate", get_bucket()]).

create_bucket(Node, DDL) ->
    Props = io_lib:format("{\\\"props\\\": {\\\"n_val\\\": 3, " ++
			      "\\\"table_def\\\": \\\"~s\\\"}}", [DDL]),
    rt:admin(Node, ["bucket-type", "create", get_bucket(), 
		    lists:flatten(Props)]).

%% @ignore
%% copied from ensemble_util.erl
-spec build_cluster(non_neg_integer()) -> [node()].
build_cluster(Size) ->
    lager:info("Building cluster of ~p~n", [Size]),
    build_cluster(Size, []).
-spec build_cluster(non_neg_integer(), list()) -> [node()].
build_cluster(Size, Config) ->
    [_Node1|_] = Nodes = rt:deploy_nodes(Size, Config),
    rt:join_cluster(Nodes),
    Nodes.

get_bucket() ->
    "GeoCheckin".

%% a valid DDL - the one used in the documents
get_ddl(docs) ->
    _SQL = "CREATE TABLE GeoCheckin (" ++
	"myfamily    varchar   not null, " ++
	"myseries    varchar   not null, " ++
	"time        timestamp not null, " ++
	"weather     varchar   not null, " ++
	"temperature float, " ++
	"PRIMARY KEY ((quantum(time, 15, 'm'), myfamily, myseries), " ++
	"time, myfamily, myseries))";
%% another valid DDL - one with all the good stuff like
%% different types and optional blah-blah
get_ddl(variety) ->
    _SQL = "CREATE TABLE GeoCheckin (" ++
	"myfamily    varchar     not null, " ++
	"myseries    varchar     not null, " ++
	"time        timestamp   not null, " ++
	"myint       integer     not null, " ++
	"myfloat     float       not null, " ++
	"mybool      boolean     not null, " ++
	"mytimestamp timestamp   not null, " ++
	"myany       any         not null, " ++
	"myoptional  integer, " ++
	"PRIMARY KEY ((quantum(time, 15, 'm'), myfamily, myseries), " ++
	"time, myfamily, myseries))";
%% an invalid TS DDL becuz family and series not both in key
get_ddl(shortkey_fail) ->
    _SQL = "CREATE TABLE GeoCheckin (" ++
	"myfamily    varchar   not null, " ++
	"myseries    varchar   not null, " ++
	"time        timestamp not null, " ++
	"weather     varchar   not null, " ++
	"temperature float, " ++
	"PRIMARY KEY ((quantum(time, 15, 'm'), myfamily), " ++
	"time, myfamily))";
%% an invalid TS DDL becuz partition and local keys dont cover the same space
get_ddl(splitkey_fail) ->
    _SQL = "CREATE TABLE GeoCheckin (" ++
	"myfamily    varchar   not null, " ++
	"myseries    varchar   not null, " ++
	"time        timestamp not null, " ++
	"weather     varchar   not null, " ++
	"temperature float, " ++
	"PRIMARY KEY ((quantum(time, 15, 'm'), myfamily, myseries), " ++
	"time, myfamily, myseries, temperature))";
%% another invalid TS DDL because family/series must be varchar
%% or is this total bollox???
get_ddl(keytype_fail_mebbies_or_not_eh_check_it_properly_muppet_boy) ->
    _SQL = "CREATE TABLE GeoCheckin (" ++
	"myfamily    integer   not null, " ++
	"myseries    varchar   not null, " ++
	"time        timestamp not null, " ++
	"weather     varchar   not null, " ++
	"temperature float, " ++
	"PRIMARY KEY ((quantum(time, 15, 'm'), myfamily, myseries), " ++
	"time, myfamily, myseries))".

get_valid_obj() ->
    [get_varchar(),
     get_varchar(),
     get_timestamp(),
     get_varchar(),
     get_float()].

get_invalid_obj() ->
    [get_varchar(),
     get_integer(),   % this is the duff field
     get_timestamp(),
     get_varchar(),
     get_float()].

get_varchar() ->
    Len = random:uniform(?MAXVARCHARLEN),
    String = get_string(Len),
    list_to_binary(String).

get_string(Len) ->
    get_s(Len, []).

get_integer() ->
    get_timestamp().

get_s(0, Acc) ->
    Acc;
get_s(N, Acc) when is_integer(N) andalso N > 0 ->
    get_s(N - 1, [random:uniform(255) | Acc]).

get_timestamp() ->
    random:uniform(?MAXTIMESTAMP).

get_float() ->
    F1 = random:uniform(trunc(?MAXFLOAT)),
    F2 = random:uniform(trunc(?MAXFLOAT)),
    F1 - F2 + random:uniform().