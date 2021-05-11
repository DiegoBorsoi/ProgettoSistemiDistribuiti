-module(test_ignore).

%% API
-export([remove_connection/0]).

%%%=================================================================================================================
%%% Viene testato il funzionamento della rete nel momento in cui un collegamento fra due nodi viene a mancare
%%%=================================================================================================================


% viene simulata la caduta di un collegamento fra due nodi della rete
% per fare ciò vengono utilizzate delle funzioni apposite che dicono al nodo di ignorare i messaggi di un determinato vicino
remove_connection() ->
  ambiente:start_link("graphs/graph_test"),
  % aspetto che la rete si stabilizzi
  timer:sleep(10000),
  % connessione caduta
  ambiente:ignore_neighb(c, b),
  % aspetto che la rete si stabilizzi
  timer:sleep(30000),

  % visualizzo lo stato dei vicini
  c_server ! get_neighb_all,

  % pulizia finale
  ambiente:stop_ambiente().
