%%%-------------------------------------------------------------------
%%% @author igor
%%% @copyright (C) 2021, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 23. apr 2021 16:16
%%%-------------------------------------------------------------------
-module(utils).
-author("igor").

%% API
-export([check_graph/2]).

%%%-------------------------------------------------------------------
%%% funzioni per controllare la correttezza del grafo dei nodi
%%%-------------------------------------------------------------------
get_nodes(Xs) -> lists:foldr(
  fun({X, _, _}, Acc) -> [X | Acc] end,
  [],
  Xs
).

% controlla che tutti i vicini di un nodo esistano come nodi e non abbia self-loop
check_nb(Local, Nodes, Nb_lst) ->
  [] == (Nb_lst -- (Nodes -- [Local])).

% controlla che tutti i nodi abbiano tipo definito correttamente
check_type(Ltype, Types) ->
  [] == [Ltype] -- Types
.

% dato lista dei tipi e descrizione del grafo, ritorna valore booleano di correttezza
check_graph(Types, Graph) ->
  Nodes = get_nodes(Graph),
  Result = lists:foldr(
    fun({Local, Type, Nbs}, Acc) ->
      check_type(Type, Types) and check_nb(Local,Nodes,Nbs) and Acc
      end,
    true,
    Graph
  ),
  Result
.
