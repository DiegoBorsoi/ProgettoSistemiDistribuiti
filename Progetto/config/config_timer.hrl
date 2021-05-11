%%% File di configurazione contenenete tutte le macro per ogni timer utilizzato

-define(TIMER_ECHO, 5000).
-define(TIMER_WAIT_ADD, 5000).

-define(TIMER_TREE_KEEP_ALIVE, 2000).
-define(TIMER_WAIT_TREE_KEEP_ALIVE, 4000).
-define(TIMER_TREE_RESET_ROUTE, 6000).

-define(TIMER_WAIT_FLOOD_TOO_HIGH, 1000).

-define(TIMER_WAIT_TRANSACTION_ACK_LISTENING, 3000).
-define(TIMER_WAIT_TRANSACTION_COMMIT, 5000). % deve essere per forze maggiore di TIMER_WAIT_TRANSACTION_ACK_LISTENING

-define(TIMER_WAIT_TREE_STABILITY, 6500). % deve essere maggiore di TIMER_TREE_RESET_ROUTE