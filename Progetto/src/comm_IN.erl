-module(comm_IN).

%% API
-export([start_link/3]).
-export([init/3]).

-record(comm_IN_state, {id, server, rules_worker, flood_table}).

start_link(Id, State_server, Rules_worker) ->
  Pid = spawn_link(?MODULE, init, [Id, State_server, Rules_worker]),
  {ok, Pid}.

init(Id, State_server, Rules_worker) ->
  register(Id, self()),
  FloodTable = ets:new(flood_table, [ % TODO: mettere un massimo alle tuple salvate
    set,
    public,
    {keypos, 1},
    {heir, none},
    {write_concurrency, false},
    {read_concurrency, false},
    {decentralized_counters, false}
  ]),
  listen(#comm_IN_state{id = Id, server = State_server, rules_worker = Rules_worker, flood_table = FloodTable}).

listen(State = #comm_IN_state{id = Id, server = Server_name, rules_worker = RW, flood_table = FT}) ->
  receive
    {flood, Id_sender, Flood_clock, Flood_gen, Action} ->
      io:format("Received: ~p.~n", [Action]),
      if
        (Flood_gen =/= Id) ->
          case check_flood_validity(Flood_clock, Flood_gen, FT) of
            true -> % flood nuovo
              rules_worker:exec_action(RW, Flood_clock, Action),
              {ok, Active_neighbs} = state_server:get_active_neighb(Server_name),
              spawn(comm_OUT, init, [{flood, Id, Flood_clock, Flood_gen, Action}, Active_neighbs -- [Id_sender]]);
            false ->
              ok
          end;
        true ->
          ok
      end,
      listen(State);
    _ ->
      io:format("Unespected message.~n")
  end.

% controllo se il flood arrivato è già stato visto (false) oppure no (true) e lo salvo nella tabella
check_flood_validity(Flood_clock, Flood_gen, FT) ->
  case ets:insert_new(FT, {{Flood_clock, Flood_gen}}) of
    false -> % TODO: questa cosa è molto inutile, basta solo chiamare l'insert
      false;
    true ->
      true
  end.