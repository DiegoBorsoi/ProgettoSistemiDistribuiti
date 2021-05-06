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
      io:format("~p : Received: ~p.~n", [Id, Action]),
      if
        (Flood_gen =/= Id) ->
          case check_flood_validity(flood, Flood_clock, Flood_gen, FT) of
            true -> % flood nuovo
              rules_worker:exec_action(RW, normal, Flood_clock, Action),
              {ok, Active_neighbs} = state_server:get_active_neighb(Server_name),
              spawn(comm_OUT, init, [{flood, Id, Flood_clock, Flood_gen, Action}, Active_neighbs -- [Id_sender]]);
            false ->
              ok
          end;
        true ->
          ok
      end,
      listen(State);
    {transact_rqs, Id_sender, Trans_clock, Trans_id_gen, Action} ->
      io:format("~p : Received transaction request: ~p.~n", [Id, Action]),
      if
        (Trans_id_gen =/= Id) ->
          case check_flood_validity(transaction, Trans_clock, Trans_id_gen, FT) of
            true -> % nuova transazione
              rules_worker:exec_action(RW, {transaction_rqs, Trans_id_gen}, Trans_clock, Action),
              {ok, Active_neighbs} = state_server:get_active_neighb(Server_name),
              spawn(comm_OUT, init, [{transact_rqs, Id, Trans_clock, Trans_id_gen, Action}, Active_neighbs -- [Id_sender]]);
            false ->
              ok
          end;
        true ->
          ok
      end,
      listen(State);
    {transact_req_ack, Id_sender, Action_clock, Id_gen} ->
      io:format("~p : Received transaction req ack: ~p.~n", [Id, {Action_clock, Id_gen}]),
      listen(State);
    {transact_start, Id_sender, Action_clock, Id_gen, Partecipants} ->
      io:format("~p : Received transaction start: ~p.~n", [Id, {Action_clock, Id_gen, Partecipants}]),
      listen(State);
    Msg ->
      io:format("~p : Unespected message: ~p.~n", [Id, Msg]),
      listen(State)
  end.

% controllo se il flood arrivato è già stato visto (false) oppure no (true) e lo salvo nella tabella
check_flood_validity(Type, Flood_clock, Flood_gen, FT) ->
  case ets:insert_new(FT, {{Type, Flood_clock, Flood_gen}}) of
    false -> % questa cosa è molto inutile, basta solo chiamare l'insert
      false;
    true ->
      true
  end.