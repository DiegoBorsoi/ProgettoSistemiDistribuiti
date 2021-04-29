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
  i_am_root,
  is_root_alive
}).

start_link(Id, Server_name, HB_name) ->
  Pid = spawn_link(?MODULE, init, [Id, Server_name, HB_name]),
  {ok, Pid}.

init(Id, Server_name, HB_name) ->
  register(HB_name, self()),
  State = #hb_state{id = Id, hb_name = HB_name, server_name = Server_name},
  {ok, Clock} = state_server:get_clock(Server_name),
  case Clock of
    -1 ->
      receive
        {neighb_ready} -> % aspetto che il mio comm_ambiente abbia aggiornato la lista dei vicini
          ok
      end;
    _ -> ok
  end,
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

  % fingo la fine di un timer per dare inizio al protocollo, essendo is_root_alive inizializzato a false
  self() ! {tree_keep_alive_timer_ended},
  self() ! {start_echo},
  listen(State#hb_state{neighb_clocks = Neighbs_clocks, neighb_state = Neighbs_state, i_am_root = false, is_root_alive = false}).

% esecuzione del protocollo di annessione di un nuovo nodo alla rete
enter_network(Neighbs, _State = #hb_state{id = Id, hb_name = HB_name, server_name = Server_name}) ->
  spawn(hb_OUT, init, [{add_new_nd, Id, HB_name}, Neighbs]), % invia un messaggio ad ogni vicino maybe raggiungibile

  Neighbs_clocks = maps:from_list([{Node, -1} || Node <- Neighbs]),  % crea una mappa per il salvataggio del clock dei vicini
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
      [state_server:rm_neighb_with_hb(Server_name, Node) || Node <- maps:keys(maps:filter(fun(_Key, Value) ->
        Value == -1 end, Neighbs_clocks))],
      maps:filter(fun(_Key, Value) -> Value =/= -1 end, Neighbs_clocks)
  end.

% Funzione per estrarre il massimo dei clock dei vicini ed inviare un apposito messaggio a quelli con clock minore
check_clock_values(Neighbs_clocks, HB_name, Server_name) ->
  {_Clock_neighb, Clock} = maps:fold(fun get_max_map_value/3, {undefined, undefined}, Neighbs_clocks),
  case Clock of
    undefined ->
      state_server:update_clock(Server_name, 0);
    _ ->
      state_server:update_clock(Server_name, Clock)
  end,
  % invia un messaggio ad ogni vicino upd_clk maybe raggiungibile
  spawn(hb_OUT, init, [{upd_lmp, HB_name, Clock}, maps:keys(maps:filter(fun(_Key, Value) ->
    Value < Clock end, Neighbs_clocks))]),
  ok.

listen(State = #hb_state{id = Id, hb_name = HB_name, server_name = Server_name, neighb_clocks = NC, neighb_state = NS, i_am_root = Im_root, is_root_alive = Root_alive}) ->
  receive
    {start_echo} ->
%%      io:format("~p: Inizio procedura echo.~n", [Id]),
      New_NS = set_neighbs_state(NS),

      % viene create il processo hb_OUT che si occupa di inviare il messaggio di echo_rqs a tutti i vicini
      {ok, Neighbs_hb} = state_server:get_neighb_hb(Server_name),
      Msg = {echo_rqs, HB_name},
      spawn(hb_OUT, init, [Msg, Neighbs_hb]),

      listen(State#hb_state{neighb_state = New_NS});
    {echo_timer_ended} ->
%%      io:format("~p: Timer dell'ECHO finito.~n", [Id]),
      Updated_NS = update_neighbs_state(NS),  % aggiorna lo stato dei vicini in modo da scoprire se qualcuno non ha risposto
      Neighbs_dead = maps:keys(maps:filter(fun(_Key, Value) -> Value == dead end, Updated_NS)), % lista dei vicini morti

      {ok, Neighbs_map} = state_server:get_neighb_map(Server_name), % mappa con elementi {Id_nodo -> HB_nodo}
      Neighbs_reverse_map = maps:fold(fun(Key, Value, Acc) -> maps:put(Value, Key, Acc) end, maps:new(), Neighbs_map),
      {ok, {_Root_id, _Dist, Id_RP}} = state_server:get_tree_state(Server_name),
      Is_RP_dead = lists:any(fun(Node_hb) -> Id_RP == maps:get(Node_hb, Neighbs_reverse_map) end, Neighbs_dead),
      if
        Is_RP_dead ->
          % se ho rimosso la mia RP devo fare un {start_tree} appena dopo aver resettato la radice salvata
          state_server:reset_tree_state(Server_name),
          self() ! {start_tree};
        true ->
          ok
      end,

      [state_server:rm_neighb_with_hb(Server_name, Node) || Node <- Neighbs_dead],  % elimino i morti dalla tabella nello state_server
      {Maybe_alive_NS, Maybe_alive_NC} = removes_dead(Updated_NS, NC, Neighbs_dead),  % elimino i morti dalla mappa dello stato dei vicini
      self() ! {start_echo},  % iniziamo un nuovo ciclo di ECHO
      listen(State#hb_state{neighb_clocks = Maybe_alive_NC, neighb_state = Maybe_alive_NS});
    {echo_rpl, Id_hb, Clock} ->
%%      io:format("~p: Ricevuta risposta dell'echo_rqs da ~p.~n", [Id, Id_hb]),
      New_NC = maps:put(Id_hb, Clock, NC), % aggiorno il clock salvato del vicino
      New_NS = maps:put(Id_hb, alive, NS), % aggiorno lo stato del vicino ad alive avendo ricevuto una risposta all'ECHO
      listen(State#hb_state{neighb_clocks = New_NC, neighb_state = New_NS});
    {echo_rqs, Id_hb_sender} ->
%%      io:format("~p: HeartBeat ricevuto da ~p.~n", [Id, Id_hb_sender]),
      {ok, Guard} = state_server:check_neighb(Server_name, Id_hb_sender),
      if
        Guard ->
          {ok, Clock} = state_server:get_clock(Server_name),
          try
            Id_hb_sender ! {echo_rpl, HB_name, Clock}
          catch
            _:_ ->
              ok
          end;
        true ->
          ok
      end,
      listen(State);
    {add_new_nd, Id_sender, Id_hb_sender} ->
%%      io:format("~p: Ricevuta richiesta connessione alla rete di ~p.~n", [Id, Id_sender]),
      state_server:add_neighb(Server_name, {Id_sender, Id_hb_sender}),
      {ok, Clock} = state_server:get_clock(Server_name),
      try
        Id_hb_sender ! {add_new_nb, HB_name, Clock}
      catch
        _:_ -> ok
      end,
% aggiorno le due mappe usate presenti nello stato
      New_NC = maps:put(Id_hb_sender, Clock, NC),
      New_NS = maps:put(Id_hb_sender, alive, NS),
      listen(State#hb_state{neighb_clocks = New_NC, neighb_state = New_NS});
    {upd_lmp, Id_hb_sender, Clock_sender} ->
%%      io:format("~p: Ricevuto ordine di aggiornamento del clock:<~p>.~n", [Id, Clock_sender]),
% se il nuovo clock è maggiore del mio, lo aggiorno e inoltro il messaggio ai miei vicini con clock minore
      {ok, Clock} = state_server:get_clock(Server_name),
      if
        Clock < Clock_sender ->
          state_server:update_clock(Server_name, Clock_sender),
          spawn(hb_OUT, init, [
            {upd_lmp, HB_name, Clock_sender},
            maps:to_list(maps:filter(
              fun(Node, Node_clock) -> (Node =/= Id_hb_sender) and (Node_clock < Clock_sender) end,
              NC))
          ]);
        true ->
          ok
      end,
      listen(State);
    {add_timer_ended} ->  % timer della connessione, tutto è andato bene, quindi viene ignorato
      listen(State);
%%%=================================================================================================================
%%% Distributed Spanning Tree messagges handling
%%%=================================================================================================================
    {start_tree} ->
      io:format("~p: Sono entrato in start_tree.~n", [Id]),
      {ok, {Id_root, Dist, _ID_RP}} = state_server:get_tree_state(Server_name),
      {ok, Neighbs_hb} = state_server:get_neighb_hb(Server_name),
      spawn(hb_OUT, init, [{tree_state, HB_name, {Id_root, Dist, Id}}, Neighbs_hb]),
      if
        Id_root == Id ->
          New_Im_root = true,
          self() ! {tree_root_keep_alive_timer_ended};
        true ->
          New_Im_root = false
      end,
      listen(State#hb_state{i_am_root = New_Im_root, is_root_alive = true});
    {tree_state, HB_sender, {Id_root, Dist, Id_sender}} -> % messaggio di aggiornamento della radice dell'albero
      io:format("~p: Ricevuto tree_state: ~p.~n", [Id, {Id_root, Dist, Id_sender}]),
      {ok, {Saved_root, Saved_dist, Saved_RP}} = state_server:get_tree_state(Server_name),
      {ok, Neighbs_map} = state_server:get_neighb_map(Server_name), % mappa con elementi {Id_nodo -> HB_nodo}
      Neighbs_hb = maps:values(Neighbs_map),
      if
        Saved_root < Id_root ->
          spawn(hb_OUT, init, [{tree_state, HB_name, {Saved_root, Saved_dist, Id}}, [HB_sender]]),
          New_Im_root = Im_root;
        (Saved_root == Id_root) andalso (Saved_dist + 1 < Dist) ->
          spawn(hb_OUT, init, [{tree_state, HB_name, {Saved_root, Saved_dist, Id}}, [HB_sender]]),
          New_Im_root = Im_root;
        (Saved_root > Id_root)
          orelse
          ((Saved_root == Id_root) andalso (Saved_dist > Dist + 1))
          orelse
          ((Saved_root == Id_root) andalso (Saved_dist == Dist + 1) andalso (Id_sender < Saved_RP)) ->
% aggiorno lo lo stato dell'albero salvato
          state_server:set_tree_state(Server_name, {Id_root, Dist + 1, Id_sender}),
% avviso la nuova route port che la uso come tale
          spawn(hb_OUT, init, [{tree_ack, Id}, [HB_sender]]),
% avviso la vecchia route port che non la uso più
          if
            Saved_RP == Id ->
              ok;
            true ->
              spawn(hb_OUT, init, [{tree_rm_rp, Id}, [maps:get(Saved_RP, Neighbs_map)]])
          end,
% avviso i vicini che ho cambiato porta
          spawn(hb_OUT, init, [{tree_state, HB_name, {Id_root, Dist + 1, Id}}, Neighbs_hb -- [HB_sender]]),

          New_Im_root = false;
        true ->
          New_Im_root = Im_root
      end,
      listen(State#hb_state{i_am_root = New_Im_root});
    {tree_ack, Id_sender} -> % conferma che Id_port stia usando me come RP
      state_server:set_tree_active_port(Server_name, Id_sender),
      listen(State);
    {tree_rm_rp, Id_sender} -> % indica che Id_port non mi usa più come RP
      state_server:rm_tree_active_port(Server_name, Id_sender),
      listen(State);
    {tree_keep_alive, HB_sender, Id_root_keep_alive} -> % messaggio della radice che dice di essere viva
      io:format("~p: Ricevuto is_root_alive: i'm root (~p).~n", [Id, Im_root]),
      {ok, {Id_root, _Dist, _Id_RP}} = state_server:get_tree_state(Server_name),
      if
        Id_root == Id_root_keep_alive ->
          Is_alive = true,
          {ok, Neighbs_hb} = state_server:get_active_neighb_hb(Server_name),
          spawn(hb_OUT, init, [{tree_keep_alive, HB_name, Id_root_keep_alive}, Neighbs_hb -- [HB_sender]]);
        true ->
          Is_alive = Root_alive
      end,
      listen(State#hb_state{is_root_alive = Is_alive});
    {tree_keep_alive_timer_ended} -> % controllo se ho ricevuto un messaggio della radice che dice di essere viva
      if
        Im_root orelse Root_alive -> % la radice è viva
          Is_alive = false;
        true -> % la radice è morta, sono io la nuova radice e lo dico ai vicini
          io:format("~p: La mia radice è morta.~n", [Id]),
          state_server:reset_tree_state(Server_name),
          self() ! {start_tree},
          Is_alive = true
      end,
      erlang:send_after(10000, self(), {tree_keep_alive_timer_ended}),
      listen(State#hb_state{is_root_alive = Is_alive});
    {tree_root_keep_alive_timer_ended} ->
      if
        Im_root ->
          {ok, Neighbs_hb} = state_server:get_active_neighb_hb(Server_name),
          spawn(hb_OUT, init, [{tree_keep_alive, HB_name, Id}, Neighbs_hb]),
          erlang:send_after(5000, self(), {tree_root_keep_alive_timer_ended});
        true ->
          ok
      end,
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