-module(hb_IN).

%% API
-export([start_link/3]).
-export([init/3]).

-record(hb_state, {
                    id,
                    hb_name,
                    server_name,
                    neighb_clocks,
                    neighb_state
                  }).

start_link(Id, Server_name, HB_name) ->
  Pid = spawn_link(?MODULE, init, [Id, Server_name, HB_name]),
  {ok, Pid}.

init(Id, Server_name, HB_name) ->
  register(HB_name, self()),
  State = #hb_state{id = Id, hb_name = HB_name, server_name = Server_name},
  receive
    {neighb_ready} -> % aspetto che il mio comm_ambiente abbia aggiornato la lista dei vicini
      ok
  end,
  {ok, Clock} = state_server:get_clock(Server_name),
  {ok, Neighbs} = state_server:get_neighb_hb(Server_name),
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
  listen(State#hb_state{neighb_clocks = Neighbs_clocks, neighb_state = Neighbs_state}).

% esecuzione del protocollo di annessione di un nuovo nodo alla rete
enter_network(Neighbs, _State = #hb_state{id = Id, hb_name = HB_name, server_name = Server_name}) ->
  [Node ! {add_new_nd, Id, HB_name} || Node <- Neighbs], % invia un messaggio ad ogni vicino raggiungibile
  Neighbs_clocks = maps:from_list([{Node, -1} || Node <- Neighbs]),  % crea una mappa per il salvataggio del clock dei vicini
  % dopo 10 secondi un messaggio viene inviato, serve per mettere un tempo massimo nell'attesa dei messaggi di risposta nella connessione alla rete
  erlang:send_after(10000, self(), {add_timer_ended}),
  New_neighbs_clocks = wait_for_all_neighbs(Neighbs_clocks, Server_name),
  check_clock_values(New_neighbs_clocks, HB_name, Server_name),
  New_neighbs_clocks.

% Funzione per la ricezione delle risposte dei vicini al momento della connessione alla rete
wait_for_all_neighbs(Neighbs_clocks, Server_name) ->
  receive
    {add_new_nb, Id_hb, Clock} ->
      io:format("Ricevuta risposta in aggiunta alla rete dai vicini.~n"),
      New_Neighbs_clocks = maps:put(Id_hb, Clock, Neighbs_clocks),
      case maps:size(maps:filter(fun(_Key, Value) -> Value == -1 end, New_Neighbs_clocks)) of
        0 -> % ho ricevuto tutte le risposte dai vicini, posso continuare con il protocollo
          New_Neighbs_clocks;
        _ -> % non ho ancora ricevuto tutte le risposte, quindi ritorno in ricezione
          wait_for_all_neighbs(New_Neighbs_clocks, Server_name)
      end;
    {add_timer_ended} -> % il tempo massimo è scaduto, i nodi che non hanno risposto sono considerati morti
      [state_server:rm_neighb_with_hb(Server_name, Node) || Node <- maps:keys(maps:filter(fun(_Key, Value) -> Value == -1 end, Neighbs_clocks))],
      maps:filter(fun(_Key, Value) -> Value =/= -1 end, Neighbs_clocks)
  end.

% Funzione per estrarre il massimo dei clock dei vicini ed inviare un apposito messaggio a quelli con clock minore
check_clock_values(Neighbs_clocks, HB_name, Server_name) ->
  {_Clock_neighb, Clock} = maps:fold(fun get_max_map_value/3, {undefined, undefined}, Neighbs_clocks),
  state_server:update_clock(Server_name, Clock),
  [Node ! {upd_lmp, HB_name, Clock} || Node <- maps:keys(maps:filter(fun(_Key, Value) -> Value < Clock end, Neighbs_clocks))],
  ok.

listen(State = #hb_state{id = Id, hb_name = HB_name, server_name = Server_name, neighb_clocks = NC, neighb_state = NS}) ->
  receive
    {start_echo} ->
      io:format("~p: Inizio procedura echo.~n", [Id]),
      New_NS = set_neighbs_state(NS),
      % viene create il processo hb_OUT che si occupa di inviare il messaggio di echo_rqs a tutti i vicini
      spawn(hb_OUT, init, [Server_name, HB_name]),
      listen(State#hb_state{neighb_state = New_NS});
    {echo_timer_ended} ->
      io:format("~p: Timer dell'ECHO finito.~n", [Id]),
      Updated_NS = update_neighbs_state(NS),  % aggiorna lo stato dei vicini in modo da scoprire se qualcuno non ha risposto
      Neighbs_dead = maps:keys(maps:filter(fun(_Key, Value) -> Value == dead end, Updated_NS)), % lista dei vicini morti
      [state_server:rm_neighb_with_hb(Server_name, Node) || Node <- Neighbs_dead],  % elimino i morti dalla tabella nello state_server
      {Maybe_alive_NS, Maybe_alive_NC} = removes_dead(Updated_NS, NC, Neighbs_dead),  % elimino i morti dalla mappa dello stato dei vicini

      self() ! {start_echo},  % iniziamo un nuovo ciclo di ECHO
      listen(State#hb_state{neighb_clocks = Maybe_alive_NC, neighb_state = Maybe_alive_NS});
    {echo_rpl, Id_hb, Clock} ->
      io:format("~p: Ricevuta risposta dell'echo_rqs da ~p.~n", [Id, Id_hb]),
      New_NC = maps:put(Id_hb, Clock, NC), % aggiorno il clock salvato del vicino
      New_NS = maps:put(Id_hb, alive, NS), % aggiorno lo stato del vicino ad alive avendo ricevuto una risposta all'ECHO
      listen(State#hb_state{neighb_clocks = New_NC, neighb_state = New_NS});
    {echo_rqs, Id_hb_sender} ->
      io:format("~p: HeartBeat ricevuto da ~p.~n", [Id, Id_hb_sender]),
      {ok, Guard} = state_server:check_neighb(Server_name, Id_hb_sender),
      if
        Guard ->
          {ok, Clock} = state_server:get_clock(Server_name),
          Id_hb_sender ! {echo_rpl, HB_name, Clock};
        true ->
          ok
      end,
      listen(State);
    {add_new_nd, Id_sender, Id_hb_sender} ->
      io:format("~p: Ricevuta richiesta connessione alla rete di ~p.~n", [Id, Id_sender]),
      state_server:add_neighb(Server_name, {Id_sender, Id_hb_sender}),
      Clock = state_server:get_clock(Server_name),
      Id_hb_sender ! {add_new_nb, HB_name, Clock},
      % aggiorno le due mappe usate presenti nello stato
      New_NC = maps:put(Id_hb_sender, Clock, NC),
      New_NS = maps:put(Id_hb_sender, alive, NS),
      listen(State#hb_state{neighb_clocks = New_NC, neighb_state = New_NS});
    {upd_lmp, Id_hb_sender, Clock_sender} ->
      io:format("~p: Ricevuto ordine di aggiornamento del clock.~n", [Id]),
      % se il nuovo clock è maggiore del mio, lo aggiorno e inoltro il messaggio ai miei vicini con clock minore
      Clock = state_server:get_clock(Server_name),
      if
        Clock < Clock_sender ->
          state_server:update_clock(Server_name, Clock_sender),
          [Node ! {upd_lmp, HB_name, Clock_sender} || {Node, Node_clock} <- maps:to_list(NC), Node_clock < Clock_sender];
        true ->
          ok
      end,
      listen(State);
    {add_timer_ended} ->  % timer della connessione, tutto è andato bene, quindi viene ignorato
      listen(State);
    Msg ->
      io:format("~p: Unespected message on HeartBeat: ~p.~n", [Id, Msg]),
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


update_neighbs_state(Neighbs_state) ->
  maps:fold(fun update_neighbs_state_aux/3, maps:new(), Neighbs_state).

update_neighbs_state_aux(Key, unknown, Acc) ->
  maps:put(Key, maybe_dead, Acc);
update_neighbs_state_aux(Key, maybe_dead, Acc) ->
  maps:put(Key, dead, Acc);
update_neighbs_state_aux(Key, Value, Acc) -> % Value in questo caso può valere solamente alive
  maps:put(Key, Value, Acc).


removes_dead(Updated_NS, NC, _Neighbs_dead = [First_neighb | Tail]) ->
  removes_dead(maps:remove(First_neighb, Updated_NS), maps:remove(First_neighb, NC), Tail);
removes_dead(Updated_NS, NC, _) ->
  {Updated_NS, NC}.