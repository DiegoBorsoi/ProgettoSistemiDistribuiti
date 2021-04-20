-module(comm_IN).

%% API
-export([start_link/3]).
-export([init/3]).

-record(comm_IN_state, {server, rules_worker, flood_table}).

start_link(Id, State_server, Rules_worker) ->
  Pid = spawn_link(?MODULE, init, [Id, State_server, Rules_worker]),
  {ok, Pid}.

init(Id, State_server, Rules_worker) ->
  register(Id, self()),
  FloodTable = ets:new(flood_table , [
    set,
    public,
    {keypos,1},
    {heir,none},
    {write_concurrency,false},
    {read_concurrency,false},
    {decentralized_counters,false}
  ]),
  listen(#comm_IN_state{server = State_server, rules_worker = Rules_worker, flood_table = FloodTable}).

listen(State) ->
  receive
    {msg, Val} ->
      io:format("Received: ~p.~n", [Val]),
      listen(State);
    _ ->
      io:format("Unespected message.~n")
  end.