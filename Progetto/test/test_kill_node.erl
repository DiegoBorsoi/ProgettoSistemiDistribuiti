-module(test_kill_node).

%% API
-export([kill_foglia/0, kill_node/0, kill_root/0]).

%%%=================================================================================================================
%%% Viene testato il funzionamento della rete nel momento in cui un nodo muore/si scollega dalla rete
%%%=================================================================================================================


% viene ucciso un nodo foglia della rete
% essendo il nodo un nodo foglia (non ha figli) la rete non dovrebbe modificarsi, perciò non vedremo messaggi inviati
kill_foglia() ->
  ambiente:start_link("graphs/graph_test"),
  % aspetto che la rete si stabilizzi
  timer:sleep(10000),
  % uccido un nodo foglia della rete
  ambiente:kill_node(f),
  % aspetto che la rete si stabilizzi
  timer:sleep(2000),

  % pulizia finale
  ambiente:stop_ambiente().

% viene ucciso un nodo normale della rete (cioè ne foglia ne radice)
% vederemo come il nodo figlio del nodo mancante cercherà di riconnettersi alla rete tramite gli altri vicini che ha a disposizione
% la radice non verrà però accettata subito, essendo la medesima, ma solamente una volta passato il timer (TODO)
% verrà eseguita nuovamente una proposta ai vicini, i quali proporranno in risposta la giusta radice
kill_node() ->
  ambiente:start_link("graphs/graph_test"),
  % aspetto che la rete si stabilizzi
  timer:sleep(10000),
  % uccido un nodo normale della rete
  ambiente:kill_node(c),
  % aspetto che la rete si stabilizzi
  timer:sleep(10000),

  % pulizia finale
  ambiente:stop_ambiente().

% viene uccisa la radice della rete
% quindi una volta che i nodi se ne accorgeranno inizieranno tutti ad eseguire una nuova elezione
kill_root() ->
  ambiente:start("graphs/graph_test"),
  % aspetto che la rete si stabilizzi
  timer:sleep(10000),
  % uccido la radice della rete
  ambiente:kill_node(b),
  % aspetto che la rete si stabilizzi
  timer:sleep(20000),

  % pulizia finale
  ambiente:stop_ambiente().