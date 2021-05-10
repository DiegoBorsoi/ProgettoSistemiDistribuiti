-module(comm_IN).

%% API
-export([start_link/3]).
-export([init/3]).
-export([clean_old_values/2]).

-record(comm_IN_state, {id, server, rules_worker, flood_table}).

start_link(Id, State_server, Rules_worker) ->
  Pid = spawn_link(?MODULE, init, [Id, State_server, Rules_worker]),
  {ok, Pid}.

init(Id, State_server, Rules_worker) ->
  register(Id, self()),
  FloodTable = ets:new(flood_table, [
    ordered_set,
    public,
    {keypos, 1},
    {heir, none},
    {write_concurrency, true},
    {read_concurrency, true},
    {decentralized_counters, true}
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
          case check_flood_validity(transaction_rqs, Trans_clock, Trans_id_gen, FT) of
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
    {transact_ack, Id_sender, Trans_clock, Trans_id_gen, Trans_id_ack} ->
      io:format("~p : Received transaction req ack: ~p.~n", [Id, {Trans_clock, Trans_id_gen}]),
      case check_flood_validity({transaction_ack, Trans_id_ack}, Trans_clock, Trans_id_gen, FT) of
        true ->
          if
            (Trans_id_gen == Id) -> % se è un ack di una mia transazione
              rules_worker:transact_ack(RW, Trans_id_ack, Trans_clock, Trans_id_gen);
            true -> % altrimenti lo invio agli altri vicini
              {ok, Active_neighbs} = state_server:get_active_neighb(Server_name),
              spawn(comm_OUT, init, [{transact_ack, Id, Trans_clock, Trans_id_gen, Trans_id_ack}, Active_neighbs -- [Id_sender]])
          end;
        _ ->
          ok
      end,
      listen(State);
    {transact_start, Id_sender, Trans_clock, Trans_id_gen, Participants} ->
      io:format("~p : Received transaction start: ~p.~n", [Id, {Trans_clock, Trans_id_gen, Participants}]),
      if
        (Trans_id_gen =/= Id) ->
          case check_flood_validity(transaction_start, Trans_clock, Trans_id_gen, FT) of
            true ->
              case [Id] -- Participants of
                [] -> % faccio parte della transazione
                  rules_worker:transact_commit(RW, Trans_id_gen, Trans_clock);
                _ -> % non ne faccio parte
                  ok
              end,
              % in ogni caso invio il messaggio ai vicini
              {ok, Active_neighbs} = state_server:get_active_neighb(Server_name),
              spawn(comm_OUT, init, [{transact_start, Id, Trans_clock, Trans_id_gen, Participants}, Active_neighbs -- [Id_sender]]);
            _ ->
              ok
          end;
        true ->
          ok
      end,
      listen(State);
    Msg ->
      io:format("~p : Unespected message: ~p.~n", [Id, Msg]),
      listen(State)
  end.

% controllo se il flood arrivato è già stato visto (false) oppure no (true) e lo salvo nella tabella
check_flood_validity(Type, Flood_clock, Flood_gen, FT) ->
  % controllo il numero di elementi della tabella, se sono troppi ne elimino un tot
  Counter = length(ets:select(FT, [{{'_', '_'}, [], [a]}])),
  case Counter > 200 of
    true ->
      spawn(comm_IN, clean_old_values, [FT, 100]);
    false ->
      ok
  end,

  % cerco se il messaggio letto è già stato visto in precedenza
  Found = ets:select(FT, [{{'$4', {'$1', '$2', '$3'}}, [{'andalso', {'==', '$1', Type}, {'andalso', {'==', '$2', Flood_clock}, {'==', '$3', Flood_gen}}}], ['$4']}]),
  case length(Found) =/= 0 of
    true -> % elimino le vecchie occorrenze (dovrebbe essere sempre solo 1)
      [ets:delete(FT, Elem) || Elem <- Found];
    false ->
      ok
  end,

  % lo inserisco con una chiave monotona crescente per ordinare in base al tempo
  % anche se c'era già va bene inserirlo di nuovo, in modo da "aggiornare" la chiave
  ets:insert(FT, {erlang:monotonic_time(), {Type, Flood_clock, Flood_gen}}),

  Found == 0.

%%%===================================================================
%%% ets cleaning functions
%%%===================================================================

clean_old_values(Table, Delete_num) when Delete_num > 0 ->
  ets:delete(Table, ets:first(Table)),
  clean_old_values(Table, Delete_num - 1);
clean_old_values(_Table, 0) ->
  ok.