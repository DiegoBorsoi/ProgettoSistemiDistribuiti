-module(test_add_node).

%% API
-export([add_foglia/0, add_radice/0]).

%%%=================================================================================================================
%%% Viene testato il funzionamento della rete nel momento in cui un nodo viene aggiunto alla rete
%%%=================================================================================================================


% viene aggiunto un nodo foglia della rete
% essendo il nodo un nodo foglia (non sarà la radice) la rete non dovrebbe modificarsi,
% perciò vedremo messaggi inviati solamente localmente al nuovo nodo
add_foglia() ->
  ambiente:start_link("graphs/graph_test"),
  % aspetto che la rete si stabilizzi
  timer:sleep(10000),
  % aggiungo un nodo foglia alla rete
  ambiente:add_node(g, gen, [e,d]),
  % aspetto che la rete si stabilizzi
  timer:sleep(20000),

  % visualizzo lo stato dei vicini secondo il nuovo nodo
  f_server ! get_neighb_all,

  % pulizia finale
  ambiente:stop_ambiente().

% viene aggiunto un nuovo nodo che dovrà diventare la nuova radice
% quindi al momento dell'aggiunta il messaggio della nuova radice dovrà propagarsi a tutti i nodi
add_radice() ->
  ambiente:start_link("graphs/graph_test"),
  % aspetto che la rete si stabilizzi
  timer:sleep(10000),
  % aggiungo un nodo nuova radice alla rete
  ambiente:add_node(a, gen, [e]),
  % aspetto che la rete si stabilizzi
  timer:sleep(20000),

  % visualizzo lo stato dei vicini secondo il nuovo nodo
  a_server ! get_neighb_all,
  e_server ! get_neighb_all,

  % pulizia finale
  ambiente:stop_ambiente().