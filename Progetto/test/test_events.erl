-module(test_events).

%% API
-export([transaction/0, regole_a_cascata/0]).

%%%=================================================================================================================
%%% Viene testato il funzionamento della rete per l'esecuzione di eventi normali della rete, regole globali e transazioni
%%%=================================================================================================================


% viene simulata l'esecuzione di una transazione
% trammite le maodifica dello stato di un nodo viene attivata una regola di transazione presente al suo interno
transaction() ->
  ambiente:start_link("graphs/graph_test"),
  % aspetto che la rete si stabilizzi
  timer:sleep(10000),
  % faccio partire una transazione utilizzando la regola presente in un nodo
  ambiente:send_action(d, 3, {{}, [{x1, 2}, {x2, 3}]}),
  % aspetto che la rete si stabilizzi
  timer:sleep(30000),

  % visualizzo lo stato delle variabili (la transazione pone x8 a 22)
  b_server ! get_vars,
  c_server ! get_vars,
  d_server ! get_vars,
  e_server ! get_vars,
  f_server ! get_vars,

  % pulizia finale
  ambiente:stop_ambiente().

% vengono eseguite più regole a cascata
% il tutto viene fatto partire tramite la modifica dello stato di un ndod
% a seguire una regola locale si attiva che a sua volta ne attiva una globale
% quest'ultima viene inviata ai vicini eseguendo un nuovo flooding
% la regola globale, come possiamo vedere dallo stato delle variabili dei nodi, non è stata eseguita nel nodo che l'ha generata
regole_a_cascata() ->
  ambiente:start_link("graphs/graph_test"),
  % aspetto che la rete si stabilizzi
  timer:sleep(10000),
  % faccio partire diverse regole a casscata
  ambiente:send_action(d, 3, {{}, [{x1, 9}, {x10, 3}]}),
  % aspetto che la rete si stabilizzi
  timer:sleep(10000),

  % visualizzo lo stato delle variabili (la transazione pone x8 a 22)
  b_server ! get_vars,
  c_server ! get_vars,
  d_server ! get_vars,
  e_server ! get_vars,
  f_server ! get_vars,

  % pulizia finale
  ambiente:stop_ambiente().