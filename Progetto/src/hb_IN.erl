-module(hb_IN).

%% API
-export([start_link/3]).
-export([init/3]).

-record(hb_state, {
                    id,
                    hb_name,
                    server_name,
                    neighb_clocks,
                    neighb_state,
                    timer_counter
                  }).

start_link(Id, Server_name, HB_name) ->
  Pid = spawn_link(?MODULE, init, [Id, Server_name, HB_name]),
  {ok, Pid}.

init(Id, Server_name, HB_name) ->
  register(HB_name, self()),
  State = #hb_state{id = Id, hb_name = HB_name, server_name = Server_name},
  {ok, Clock} = state_server:get_clock(Server_name),
  {ok, Neighbs} = state_server:get_neighb(Server_name),
  case {Clock, Neighbs} of
    {-1, []} -> % siamo gli unici nella rete
      state_server:update_clock(Server_name, 0),
      Neighbs_clocks = maps:new();
    {-1, _} ->
      Neighbs_clocks = enter_network(Neighbs, State);
    _ ->
      Neighbs_clocks = maps:from_list([{Node, -1} || Node <- Neighbs])
  end,
  Neighbs_state = maps:from_list([{Key, alive} || Key <- maps:keys(Neighbs_clocks)]),
  self() ! {start_echo},
  listen(State#hb_state{neighb_clocks = Neighbs_clocks, neighb_state = Neighbs_state, timer_counter = 0}).

% esecuzione del protocollo di annessione di un nuovo nodo alla rete
enter_network(Neighbs, _State = #hb_state{id = Id, server_name = Server_name}) ->
  [Node ! {add_new_nd, Id} || Node <- Neighbs], % invia un messaggio ad ogni vicino raggiungibile
  Neighbs_clocks = maps:from_list([{Node, -1} || Node <- Neighbs]),  % crea una mappa per il salvataggio del clock dei vicini
  % dopo 10 secondi un messaggio viene inviato, serve per mettere un tempo massimo nell'attesa dei messaggi di risposta nella connessione alla rete
  erlang:send_after(10000, self(), {add_timer_ended}),
  New_neighbs_clocks = wait_for_all_neighbs(Neighbs_clocks, Server_name),
  check_clock_values(New_neighbs_clocks, Id, Server_name),
  New_neighbs_clocks.

% Funzione per la ricezione delle risposte dei vicini al momento della connessione alla rete
wait_for_all_neighbs(Neighbs_clocks, Server_name) ->
  receive
    {add_new_nb, Id, Clock} ->
      io:format("Ricevuta risposta in aggiunta alla rete dai vicini.~n"),
      New_Neighbs_clocks = maps:put(Id, Clock, Neighbs_clocks),
      case maps:size(maps:filter(fun(_Key, Value) -> Value == -1 end, New_Neighbs_clocks)) of
        0 -> % ho ricevuto tutte le risposte dai vicini, posso continuare con il protocollo
          New_Neighbs_clocks;
        _ -> % non ho ancora ricevuto tutte le risposte, quindi ritorno in ricezione
          wait_for_all_neighbs(New_Neighbs_clocks, Server_name)
      end;
    {add_timer_ended} -> % il tempo massimo è scaduto, i nodi che non hanno risposto sono considerati morti
      [state_server:rm_neighb(Server_name, Node) || Node <- maps:keys(maps:filter(fun(_Key, Value) -> Value == -1 end, Neighbs_clocks))],
      maps:filter(fun(_Key, Value) -> Value =/= -1 end, Neighbs_clocks)
  end.

% Funzione per estrarre il massimo dei clock dei vicini ed inviare un apposito messaggio a quelli con clock minore
check_clock_values(Neighbs_clocks, Id, Server_name) ->
  {_Clock_neighb, Clock} = maps:fold(fun get_max_map_value/3, {undefined, undefined}, Neighbs_clocks),
  state_server:update_clock(Server_name, Clock),
  [Node ! {upd_lmp, Clock, Id} || Node <- maps:keys(maps:filter(fun(_Key, Value) -> Value < Clock end, Neighbs_clocks))],
  ok.

listen(State = #hb_state{id = Id, hb_name = HB_name, server_name = Server_name, neighb_state = NS}) ->
  receive
    {start_echo} ->
      io:format("Inizio procedura echo.~n"),
      New_NS = set_neighbs_state(NS),
      % viene create il processo hb_OUT che si occupa di inviare il messaggio di echo_rqs a tutti i vicini
      spawn(hb_OUT, init, [Id, Server_name, HB_name]),
      listen(State#hb_state{neighb_state = New_NS});
    {add_new_nd, Id} ->
      io:format("Ricevuta richiesta connessione alla rete di ~p.~n", [Id]),
      listen(State);
    {upd_lmp, Id, Clock} ->
      io:format("Ricevuto ordine di aggiornamento del clock.~n"),
      listen(State);
    {echo_rqs, Id} ->
      io:format("HeartBeat ricevuto da ~p.~n", [Id]),
      listen(State);
    {echo_rpl, Id, Clock} ->
      io:format("Ricevuta risposta dell'echo_rqs da ~p.~n", [Id]),
      listen(State);
    {echo_timer_ended, Neighbour} ->
      io:format("Timer di risposta del vicino ~p finito.~n", [Neighbour]),
      listen(State);
    {add_timer_ended} ->  % timer della connessione, tutto è andato bene, quindi viene ignorato
      listen(State);
    Msg ->
      io:format("Unespected message on HeartBeat: ~p.~n", [Msg]),
      listen(State)
  end.

%%%===================================================================
%%% Utility functions
%%%===================================================================

get_max_map_value(Key, Value, {undefined, undefined}) ->
  {Key, Value};
get_max_map_value(Key, Value, _Acc = {_Max_Key, Max_Value}) when Value > Max_Value ->
  {Key, Value};
get_max_map_value(_Key, _Value, Acc) ->
  Acc.

set_neighbs_state(Neighbs_state) ->
  maps:fold(fun set_neighbs_state_aux/3, maps:new(), Neighbs_state).

set_neighbs_state_aux(Key, alive, Acc) ->
  maps:put(Key, unknown, Acc);
set_neighbs_state_aux(Key, Value, Acc) -> % Value in questo caso può valere solamente maybe_dead
  maps:put(Key, Value, Acc).
