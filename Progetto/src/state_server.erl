-module(state_server).
-behaviour(gen_server).

%% API
-export([start_link/3]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% client functions
-export([exec_action/3, exec_action_from_local_rule/3, check_rule_cond/3, update_clock/2, get_clock/1, get_rules/1]).
-export([get_neighb/1, get_neighb_hb/1, add_neighb/2, add_neighbs/2, rm_neighb/2, rm_neighb_with_hb/2, check_neighb/2, get_neighb_map/1]).
-export([get_tree_state/1, reset_tree_state/1, set_tree_state/2, set_tree_active_port/2, rm_tree_active_port/2]).
-export([get_active_neighb/1, get_active_neighb_hb/1]).
-export([ignore_neighb/2, get_ignored_neighb_hb/1]).

-record(server_state, {
  id,
  vars_table,
  rules_table,
  neighb_table,
  node_params_table,
  lost_connections
}).

%%%===================================================================
%%% API
%%%===================================================================

start_link(Name, Id, State_tables) when is_atom(Name) ->
  gen_server:start_link({local, Name}, ?MODULE, [Id, State_tables], []);
start_link(Name, _Id, _State_table) ->
  io:format("Errore nella creazione dello state_server: ~p non è un nome valido.~n", [Name]).

%%%===================================================================
%%% Funzioni usate dai client
%%%===================================================================

exec_action(Name, Action_clock, Action) ->
  gen_server:call(Name, {exec_action, Action_clock, Action}).

exec_action_from_local_rule(Name, Action_clock, Action) ->
  gen_server:call(Name, {exec_action_from_local_rule, Action_clock, Action}).

check_rule_cond(Name, Rule_clock, Cond) ->
  gen_server:call(Name, {check_rule_cond, Rule_clock, Cond}).


% Esegue una chiamata sincrona per ricevere la lista di vicini
get_neighb(Name) ->
  gen_server:call(Name, {get_neighb}).

% Esegue una chiamata sincrona per ricevere la lista di vicini
get_neighb_hb(Name) ->
  gen_server:call(Name, {get_neighb_hb}).

% Esegue una chiamata sincrona per l'aggiunta di un vicino alla tabella corrispondente
add_neighb(Name, Node = {_Node_ID, _Node_HB_name}) ->
  gen_server:call(Name, {add_neighb, Node}).

% Esegue una chiamata sincrona per l'aggiunta di una lista di vicini alla tabella corrispondente
add_neighbs(Name, Nodes = [_ | _]) ->
  gen_server:call(Name, {add_neighbs, Nodes}).

% Esegue una chiamata sincrona per l'eliminazione di un vicino dalla tabella corrispondente
rm_neighb(Name, Neighb) ->
  gen_server:call(Name, {rm_neighb, Neighb}).

% Esegue una chiamata sincrona per l'eliminazione di un vicino dalla tabella corrispondente
rm_neighb_with_hb(Name, Neighb) ->
  gen_server:call(Name, {rm_neighb_with_hb, Neighb}).

check_neighb(Name, Neighb_hb) ->
  gen_server:call(Name, {check_neighb, Neighb_hb}).

% Esegue una chiamata sincrona per ottenere un mappa contenente per ogni vicino {Id -> HB}
get_neighb_map(Name) ->
  gen_server:call(Name, {get_neighb_map}).


% Esegue una chiamata sincrona per ricevere la lista delle regole
get_rules(Name) ->
  gen_server:call(Name, {get_rules}).


% Esegue una chiamata sincrona per ricevere il clock locale
get_clock(Name) ->
  gen_server:call(Name, {get_clock}).

% Esegue una chiamata sincrona per aggiornare il valore del clock salvato
update_clock(Name, Clock) ->
  gen_server:call(Name, {update_clock, Clock}).


% Esegue una chiamata sincrona per ottenre lo stato dell'albero di comunicazione,
% cioè una tupla del tipo {Id_root, dist, Id_route_port}
get_tree_state(Name) ->
  gen_server:call(Name, {get_tree_state}).

% Esegue una chiamata sincrona per resettare il valore salvato per l'albero di comunicazione
reset_tree_state(Name) ->
  gen_server:call(Name, {reset_tree_state}).

% Esegue una chiamata sincrona per impostare il valore salvato per l'albero di comunicazione ad un nuovo valore
set_tree_state(Name, Tree_state) ->
  gen_server:call(Name, {set_tree_state, Tree_state}).

% Esegue una chiamata sincrona per impostare ad active un determinato vicino
set_tree_active_port(Name, ID_port) ->
  gen_server:call(Name, {set_tree_active_port, ID_port}).

% Esegue una chiamata sincrona per impostare a disable un determinato vicino
rm_tree_active_port(Name, ID_port) ->
  gen_server:call(Name, {rm_tree_active_port, ID_port}).


% Eseguo una chiamata sincrona per ottenre la lista di vicini attivi (con stato active o route_port)
get_active_neighb(Name) ->
  gen_server:call(Name, {get_active_neighb}).

% Eseguo una chiamata sincrona per ottenre la lista degli HB dei vicini attivi (con stato active o route_port)
get_active_neighb_hb(Name) ->
  gen_server:call(Name, {get_active_neighb_hb}).


% Permette di aggiungere un vicino alla lista di nodi ignorati
% (funzione utile per siulare una perdita del canale di comunicazione)
ignore_neighb(Name, Neighb) ->
  gen_server:cast(Name, {ignore_neighb, Neighb}).

% Esegue una chiamata sincrona per ottenere la lista degli hb dei vicini ignorati (connessione persa)
get_ignored_neighb_hb(Name) ->
  gen_server:call(Name, {get_ignored_neighb_hb}).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([Id, State_tables]) ->
  process_flag(trap_exit, true),  % per effettuare la pulizia prima della terminazione (viene chiamata terminate/2)
  {Vars, Rules, Neighb, NodeParams} = State_tables,
  {ok, #server_state{id = Id, vars_table = Vars, rules_table = Rules, neighb_table = Neighb, node_params_table = NodeParams, lost_connections = []}}.

handle_call({exec_action, Action_clock, Action}, _From, State = #server_state{vars_table = VT, rules_table = RT}) ->
  io:format("State_server - Ricevuta call con azione: ~p.~n", [Action]),

  Valid_action = case Action of % in questo caso l'azione avrà sempre una guardia, essendo arrivante da comm_IN
                   {Guard, Actions} when is_list(Actions) ->
                     % controllo se le variabili in guard hanno un clock adeguato
                     case check_external_guard_vars_clock(Action_clock, Guard, VT) of
                       true -> % ora controllo se la guardia è soddisfatta
                         case check_condition(Guard, VT) of
                           true -> % infine controllo se l'azione non usa variabili con clock più nuovo o uguale
                             check_action_vars_clock(Action_clock, Actions, VT);
                           false ->
                             false
                         end;
                       false ->
                         false
                     end;
                   _ ->
                     io:format("State server - azione non riconosciuta: ~p.~n", [Action]),
                     false
                 end,
  Rules = case Valid_action of
            true ->
              {_, Action_list} = Action, % estraggo la lista di azioni
              lists:foreach(fun({Var, New_value}) ->
                ets:insert(VT, {Var, New_value, Action_clock}) end, Action_list), % eseguo le azioni

              % la lista dei trigger equivale alle variabili che compaiono nella lista di azioni
              Trigger = [Var || {Var, _Value} <- Action_list],

              % cerco le regole triggerate da quest'azione
              ets:foldl(
                fun(Elem = {_, Elem_trigger, _, _}, Acc) ->
                  case Elem_trigger -- Trigger of
                    [] ->
                      [Elem | Acc];
                    _ ->
                      Acc
                  end
                end,
                [],
                RT);
            false ->
              []
          end,
  {reply, {ok, Rules}, State};
handle_call({exec_action_from_local_rule, Action_clock, Action}, _From, State = #server_state{vars_table = VT, rules_table = RT}) ->
  io:format("State_server - Ricevuta call con azione (da una regola locale): ~p.~n", [Action]),

  Valid_action = case Action of % in questo caso l'azione non avrà mai una guardia, essendo proveniente da una regola locale
                   Actions when is_list(Actions) ->
                     % controllo se l'azione non usa variabili con clock più nuovo
                     check_rules_action_vars_clock(Action_clock, Actions, VT);
                   _ ->
                     io:format("State server - azione locale non riconosciuta: ~p.~n", [Action]),
                     false
                 end,
  Rules = case Valid_action of
            true ->
              lists:foreach(fun({Var, New_value}) ->
                ets:insert(VT, {Var, New_value, Action_clock}) end, Action), % eseguo le azioni

              % la lista dei trigger equivale alle variabili che compaiono nella lista di azioni
              Trigger = [Var || {Var, _Value} <- Action],

              % cerco le regole triggerate da quest'azione
              ets:foldl(
                fun(Elem = {_, Elem_trigger, _, _}, Acc) ->
                  case Elem_trigger -- Trigger of
                    [] ->
                      [Elem | Acc];
                    _ ->
                      Acc
                  end
                end,
                [],
                RT);
            false ->
              []
          end,
  {reply, {ok, Rules}, State};
handle_call({check_rule_cond, Rule_clock, Cond}, _From, State = #server_state{vars_table = VT}) ->
  % inizialmente viene controllato se le variabili usate non siano state modificate da clock maggiori
  case check_cond_vars_clock(Rule_clock, Cond, VT) of
    true -> % a questo punto controllo se la condizione è soddisfatta
      Ris = check_condition(Cond, VT);
    false ->
      Ris = false
  end,
  {reply, {ok, Ris}, State};
handle_call({get_neighb}, _From, State = #server_state{neighb_table = NT}) ->  % Restituisce la lista dei vicini salvata nella tabella neighb_table dello stato
  Neighb_list = [Node_ID || {Node_ID, _Node_HB_name, _State} <- ets:tab2list(NT)],
  {reply, {ok, Neighb_list}, State};
handle_call({get_neighb_hb}, _From, State = #server_state{neighb_table = NT}) ->  % Restituisce la lista dei vicini salvata nella tabella neighb_table dello stato
  Neighb_list = [Node_HB_name || {_Node_ID, Node_HB_name, _State} <- ets:tab2list(NT)],
  {reply, {ok, Neighb_list}, State};
handle_call({add_neighb, {Node_ID, Node_HB_name}}, _From, State = #server_state{neighb_table = NT}) ->  % Aggiunge un nodo vicino alla lista salvata nella tabella
  ets:insert(NT, {Node_ID, Node_HB_name, disable}),
  {reply, ok, State};
handle_call({add_neighbs, Nodes = [_ | _]}, _From, State = #server_state{neighb_table = NT}) ->  % Aggiunge una lista di nodi vicino alla lista salvata nella tabella
  [ets:insert(NT, {Node_ID, Node_HB_name, disable}) || {Node_ID, Node_HB_name} <- Nodes],
  {reply, ok, State};
handle_call({rm_neighb, Neighb}, _From, State = #server_state{neighb_table = NT, lost_connections = LC}) ->
  [[Node_hb]] = ets:match(NT, {Neighb, '$1', '_'}),
  ets:delete(NT, Neighb),
  {reply, ok, State#server_state{lost_connections = LC -- [Node_hb]}};
handle_call({rm_neighb_with_hb, Neighb_hb}, _From, State = #server_state{neighb_table = NT, lost_connections = LC}) ->
  [[Node_id]] = ets:match(NT, {'$1', Neighb_hb, '_'}),
  ets:delete(NT, Node_id),
  {reply, ok, State#server_state{lost_connections = LC -- [Neighb_hb]}};
handle_call({check_neighb, Neighb_hb}, _From, State = #server_state{neighb_table = NT, lost_connections = LC}) ->
  Node_id = ets:match(NT, {'$1', Neighb_hb, '_'}),
  Found = (Node_id =/= []) and (([Neighb_hb] -- LC) =/= []),
  {reply, {ok, Found}, State};
handle_call({get_neighb_map}, _From, State = #server_state{neighb_table = NT}) ->  % Restituisce la map dei vicini
  Neighb_map = maps:from_list([{Node_ID, Node_HB} || {Node_ID, Node_HB, _State} <- ets:tab2list(NT)]),
  {reply, {ok, Neighb_map}, State};
handle_call({get_rules}, _From, State = #server_state{rules_table = NrT}) ->
  {reply, {ok, ets:tab2list(NrT)}, State};
handle_call({get_clock}, _From, State = #server_state{node_params_table = NpT}) ->
  [[Clock]] = ets:match(NpT, {clock, '$1'}),
  {reply, {ok, Clock}, State};
handle_call({update_clock, Clock}, _From, State = #server_state{node_params_table = NpT}) ->
  [[Old_clock]] = ets:match(NpT, {clock, '$1'}),
  if
    Clock > Old_clock -> % questa cosa va bene? si
      ets:insert(NpT, {clock, Clock});
    true ->
      ok
  end,
  {reply, ok, State};
handle_call({get_tree_state}, _From, State = #server_state{node_params_table = NpT}) ->
  [[Tree_state]] = ets:match(NpT, {tree_state, '$1'}),
  {reply, {ok, Tree_state}, State};
handle_call({reset_tree_state}, _From, State = #server_state{id = Id, neighb_table = NT, node_params_table = NpT}) ->
  % resetto gli stati di tutti i vicini
  ets:foldl(fun({Node_id, Node_hb, _}, _Acc) -> ets:insert(NT, {Node_id, Node_hb, disable}) end, ok, NT),
  ets:insert(NpT, {tree_state, {Id, 0, Id}}),
  {reply, ok, State};
handle_call({set_tree_state, Tree_state = {Id_root, _Dist, Id_RP}}, _From, State = #server_state{neighb_table = NT, node_params_table = NpT}) ->
  [[{Old_root, _Old_dist, Old_RP}]] = ets:match(NpT, {tree_state, '$1'}), % cerco il vecchio stato dell'albero
  if
    Old_root == Id_root -> % imposto lo stato della vecchia RP a disable (era route_port)
      try
        [[Old_RP_HB_]] = ets:match(NT, {Old_RP, '$1', '_'}),
        ets:insert(NT, {Old_RP, Old_RP_HB_, disable})
      catch
        _:_ -> ok
      end;
    true ->
      % resetto gli stati di tutti i vicini
      ets:foldl(fun({Node_id, Node_hb, _}, _Acc) -> ets:insert(NT, {Node_id, Node_hb, disable}) end, ok, NT)
  end,
  ets:insert(NpT, {tree_state, Tree_state}), % aggiorno lo stato dell'albero salvato
  % cerco e aggiorno lo stato della nuova route port
  [[HB_RP]] = ets:match(NT, {Id_RP, '$1', '_'}),
  ets:insert(NT, {Id_RP, HB_RP, route_port}),
  {reply, ok, State};
handle_call({set_tree_active_port, ID_port}, _From, State = #server_state{neighb_table = NT}) ->
  try
    [[HB_port]] = ets:match(NT, {ID_port, '$1', '_'}),
    ets:insert(NT, {ID_port, HB_port, active})
  catch
    _:_ -> ok
  end,
  {reply, ok, State};
handle_call({rm_tree_active_port, ID_port}, _From, State = #server_state{neighb_table = NT}) ->
  try
    [[HB_port]] = ets:match(NT, {ID_port, '$1', '_'}),
    ets:insert(NT, {ID_port, HB_port, disable})
  catch
    _:_ -> ok
  end,
  {reply, ok, State};
handle_call({get_active_neighb}, _From, State = #server_state{neighb_table = NT}) ->  % Restituisce la lista dei vicini attivi
  Neighb_list = [Node_ID || {Node_ID, _Node_HB_name, Node_state} <- ets:tab2list(NT), Node_state =/= disable],
  {reply, {ok, Neighb_list}, State};
handle_call({get_active_neighb_hb}, _From, State = #server_state{neighb_table = NT}) ->  % Restituisce la lista dei vicini attivi
  Neighb_hb_list = [Node_HB_name || {_Node_ID, Node_HB_name, Node_state} <- ets:tab2list(NT), Node_state =/= disable],
  {reply, {ok, Neighb_hb_list}, State};
handle_call({get_ignored_neighb_hb}, _From, State = #server_state{lost_connections = LC}) ->  % Restituisce la lista dei vicini attivi
  {reply, {ok, LC}, State};
handle_call(Msg, _From, State) ->  % per gestire messaggi syncroni sconosciuti
  io:format("Messaggio sconosciuto in handle_call. (Non sto 'mbriacato) : ~p.~n", [Msg]),
  {reply, done, State}.

handle_cast({ignore_neighb, Neighb}, State = #server_state{neighb_table = NT, lost_connections = LC}) ->
  [[Neighb_hb]] = ets:match(NT, {Neighb, '$1', '_'}),
  New_LC = [Neighb_hb | LC],
  {noreply, State#server_state{lost_connections = New_LC}};
handle_cast(_Msg, State) ->  % per gestire messaggi asyncroni sconosciuti
  {noreply, State}.

handle_info(get_neighb_all, State = #server_state{neighb_table = NT}) -> % debug
  Neighbs = ets:tab2list(NT),
  io:format("Vicini: ~p.~n", [Neighbs]),
  {noreply, State};
handle_info(get_vars, State = #server_state{vars_table = VT}) -> % debug
  io:format("Vars table: ~p.~n", [ets:tab2list(VT)]),
  {noreply, State};
handle_info(Msg, State) ->  % per gestire messaggi sconosciuti
  io:format("Unknown msg: ~p.~n", [Msg]),
  {noreply, State}.

terminate(shutdown, _State) ->
  % inserire codice per la pulizia prima della terminazione
  ok;
terminate(_Reason, _State) ->
  ok.

code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

% TODO: unire le due funzioni

% controlla se le variabili all'interno della guardia non sono state modificate dopo Action_clock
check_external_guard_vars_clock(Action_clock, Guard, VT) ->
  case Guard of
    {_, Var1, Var2} ->
      Var1_ris = case is_atom(Var1) of
                   true ->
                     case ets:lookup(VT, Var1) of
                       [{Var1, _Value_var1, Upd_clock_var1}] ->
                         if
                           Action_clock > Upd_clock_var1 ->
                             true;
                           true ->
                             false
                         end;
                       [] ->
                         io:format("State server - variabile non presente: ~p.~n", [Var1]),
                         false
                     end;
                   false ->
                     true
                 end,
      Var2_ris = case is_atom(Var2) of
                   true ->
                     case ets:lookup(VT, Var2) of
                       [{Var2, _Value_var2, Upd_clock_var2}] ->
                         if
                           Action_clock > Upd_clock_var2 ->
                             true;
                           true ->
                             false
                         end;
                       [] ->
                         io:format("State server - variabile non presente: ~p.~n", [Var2]),
                         false
                     end;
                   false ->
                     true
                 end,
      Var1_ris and Var2_ris;
    _ ->
      io:format("State server - check_cond_vars_clock condizione sbagliata: ~p.~n", [Guard]),
      false
  end.

% controlla se le variabili all'interno della condizione cond non sono state modificate dopo Rule_clock
check_cond_vars_clock(Rule_clock, Cond, VT) ->
  case Cond of
    {_, Var1, Var2} ->
      Var1_ris = case is_atom(Var1) of
                   true ->
                     case ets:lookup(VT, Var1) of
                       [{Var1, _Value_var1, Upd_clock_var1}] ->
                         if
                           Rule_clock >= Upd_clock_var1 ->
                             true;
                           true ->
                             false
                         end;
                       [] ->
                         io:format("State server - variabile non presente: ~p.~n", [Var1]),
                         false
                     end;
                   false ->
                     true
                 end,
      Var2_ris = case is_atom(Var2) of
                   true ->
                     case ets:lookup(VT, Var2) of
                       [{Var2, _Value_var2, Upd_clock_var2}] ->
                         if
                           Rule_clock >= Upd_clock_var2 ->
                             true;
                           true ->
                             false
                         end;
                       [] ->
                         io:format("State server - variabile non presente: ~p.~n", [Var2]),
                         false
                     end;
                   false ->
                     true
                 end,
      Var1_ris and Var2_ris;
    _ ->
      io:format("State server - check_cond_vars_clock condizione sbagliata: ~p.~n", [Cond]),
      false
  end.

% controlla se le variabili che verrebbero modificate dalle azioni non siano già state modificate da azioni più nuove o uguali
check_action_vars_clock(Action_clock, Action_list, VT) ->
  lists:foldl(fun({Var, _New_value}, Acc) ->
    case ets:lookup(VT, Var) of
      [{Var, _Value, Clock}] ->
        (Action_clock > Clock) andalso Acc;
      [] ->
        false
    end
              end,
    true,
    Action_list).


% controlla se le variabili verrebbero modificate dalle azioni non siano già state modificate da azioni più nuove
check_rules_action_vars_clock(Action_clock, Action_list, VT) ->
  lists:foldl(fun({Var, _New_value}, Acc) ->
    case ets:lookup(VT, Var) of
      [{Var, _Value, Clock}] ->
        (Action_clock >= Clock) andalso Acc;
      [] ->
        false
    end
              end,
    true,
    Action_list).

% esegue la condizione per ottenerne il risultato
check_condition(Cond, VT) ->
  case Cond of
    {Op, Var1, Var2} -> % operazioni di arità 2: lt, lte, gt, gte, eq, neq
      % nel caso in cui le variabili siano atomi (quindi vere e proprie variabili) devo ottenere il valore corrispondente
      % altrimenti sono dei semplici numeri e quindi li uso così come sono
      Real_var1 = if
                    is_atom(Var1) ->
                      [{Var1, Var1_value, _Var1_clock}] = ets:lookup(VT, Var1),
                      Var1_value;
                    true ->
                      Var1
                  end,
      Real_var2 = if
                    is_atom(Var2) ->
                      [{Var2, Var2_value, _Var2_clock}] = ets:lookup(VT, Var2),
                      Var2_value;
                    true ->
                      Var2
                  end,
      % ritorna il valore corrispondente all'operazione eseguita sulle variabili
      case Op of
        lt ->
          Real_var1 < Real_var2;
        lte ->
          Real_var1 =< Real_var2;
        gt ->
          Real_var1 > Real_var2;
        gte ->
          Real_var1 >= Real_var2;
        eq ->
          Real_var1 == Real_var2;
        neq ->
          Real_var1 =/= Real_var2
      end;
    _ ->
      io:format("State server - check_condition condizione non riconosciuta: ~p.~n", [Cond]),
      false
  end.