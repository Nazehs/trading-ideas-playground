#include <Trade\Trade.mqh>   // Import CTrade class for trading operations
CTrade trade;                // Create a trade object for managing orders

// Input parameters for bot configuration
input double alpha = 0.1;            // Learning rate
input double gamma = 0.9;            // Discount factor
input double epsilon = 0.1;          // Exploration rate
input double risk_reward_ratio = 2;  // Risk-reward ratio (1:2)
input int sl_pips = 400;             // Stop-loss in pips
int tp_pips = sl_pips * risk_reward_ratio;  // Take-profit in pips
input double max_daily_loss = 5;     // Max daily loss in percentage of account balance
input int trading_start_hour = 7;    // Trading start hour
input int trading_end_hour = 20;     // Trading end hour

enum Action { BUY = 0, SELL = 1, HOLD = 2 };  // Action space

// Define array sizes as fixed constants
#define RSI_BUCKETS 10         // Fixed size for RSI discretization
#define MA_BUCKETS 10          // Fixed size for MA discretization
#define ACTIONS 3              // Fixed action space size (BUY, SELL, HOLD)

// Q-table for SARSA (State space = RSI_BUCKETS * MA_BUCKETS, Action space = 3 actions)
double Q_table[RSI_BUCKETS][MA_BUCKETS][ACTIONS];  

// Structure representing the state of the market
struct State {
   int rsi_index;      // RSI index (discretized)
   int ma_index;       // Moving average index (discretized)
};

// Track daily loss and total trades
double daily_loss = 0;
int total_trades = 0;

//+------------------------------------------------------------------+
//| Initialization function                                          |
//+------------------------------------------------------------------+
int OnInit() {
   // Initialize Q-table or other required parameters
   Print("SARSA Trading Bot initialized!");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Main function to run on every tick                               |
//+------------------------------------------------------------------+
void OnTick() {
   static double last_price = 0;
   double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Skip processing if the price has not changed
   if (current_price == last_price) return;
   last_price = current_price;

   // Get current time as MqlDateTime structure
   MqlDateTime current_time;
   TimeToStruct(TimeCurrent(), current_time);

   // Check for trade timing filter (avoid low liquidity times)
   if (current_time.hour >= trading_end_hour || current_time.hour < trading_start_hour) {
      Print("Outside trading hours, skipping.");
      return;
   }

   // Check daily loss limit
   if (daily_loss >= max_daily_loss * AccountInfoDouble(ACCOUNT_BALANCE) / 100) {
      Print("Max daily loss reached, halting trading.");
      return;
   }

   // Get current market state
   State current_state;
   GetMarketState(current_state);

   // Adaptive epsilon for exploration-exploitation balance
   double adaptive_epsilon = epsilon / (1 + total_trades * 0.01);  
   Action current_action = (MathRand() / 32767.0 < adaptive_epsilon) ? RandomAction() : BestAction(current_state);

   // If HOLD, do nothing
   if (current_action == HOLD) {
      Print("HOLD action selected, no trade.");
      return;
   }

   // Check for open positions
   if (HasOpenPosition()) {
      ManageOpenPosition();
      return;
   }

   // Execute the selected action (buy or sell)
   ExecuteAction(current_action);
}

//+------------------------------------------------------------------+
//| Function to get the current market state                         |
//+------------------------------------------------------------------+
void GetMarketState(State &state) {
   double rsi_value = iRSI(_Symbol, PERIOD_CURRENT, 14, PRICE_CLOSE); // RSI value
   double ma_value = iMA(_Symbol, PERIOD_CURRENT, 50, 0, MODE_SMA, PRICE_CLOSE);  // Moving Average value

   // Discretize RSI into RSI_BUCKETS
   state.rsi_index = int(rsi_value / 100.0 * RSI_BUCKETS);  
   if (state.rsi_index >= RSI_BUCKETS) state.rsi_index = RSI_BUCKETS - 1;

   // Discretize MA into MA_BUCKETS
   state.ma_index = int(ma_value / 10000.0 * MA_BUCKETS);  
   if (state.ma_index >= MA_BUCKETS) state.ma_index = MA_BUCKETS - 1;
}

//+------------------------------------------------------------------+
//| Function to select best action based on Q-table                  |
//+------------------------------------------------------------------+
Action BestAction(State &state) {
   double max_q = -DBL_MAX;
   Action best_action = HOLD;

   for (int a = 0; a < ACTIONS; a++) {
      if (Q_table[state.rsi_index][state.ma_index][a] > max_q) {
         max_q = Q_table[state.rsi_index][state.ma_index][a];
         best_action = (Action)a;
      }
   }
   return best_action;
}

//+------------------------------------------------------------------+
//| Function to select random action (exploration)                   |
//+------------------------------------------------------------------+
Action RandomAction() {
   return (Action)(MathRand() % 2);  // Random BUY or SELL
}

//+------------------------------------------------------------------+
//| Function to manage open positions (partial close)                |
//+------------------------------------------------------------------+
void ManageOpenPosition() {
   double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
      double tp_price = PositionGetDouble(POSITION_TP);

      // Partial close when halfway to TP
      if (MathAbs(current_price - open_price) >= (tp_price - open_price) / 2) {
         if (PositionGetDouble(POSITION_VOLUME) > 0.01) {  // Ensure position size allows partial close
            trade.PositionClosePartial(ticket, PositionGetDouble(POSITION_VOLUME) / 2);
            Print("Partial close executed.");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Function to execute buy/sell actions with fixed lot size         |
//+------------------------------------------------------------------+
void ExecuteAction(Action action) {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // Fixed lot size of 0.1
   double lot_size = 0.1;

   if (action == BUY) {
      if (!trade.Buy(lot_size, _Symbol, ask, ask - sl_pips * Point(), ask + tp_pips * Point(), "SARSA Buy")) {
         Print("Buy order failed: ", GetLastError());
      } else {
         total_trades++;
      }
   } else if (action == SELL) {
      if (!trade.Sell(lot_size, _Symbol, bid, bid + sl_pips * Point(), bid - tp_pips * Point(), "SARSA Sell")) {
         Print("Sell order failed: ", GetLastError());
      } else {
         total_trades++;
      }
   }
}

//+------------------------------------------------------------------+
//| Check for open positions                                         |
//+------------------------------------------------------------------+
bool HasOpenPosition() {
   return PositionsTotal() > 0;
}

//+------------------------------------------------------------------+
//| Function to get reward for SARSA update                          |
//+------------------------------------------------------------------+
double GetReward(double current_price, double open_price) {
   double price_change = current_price - open_price;
   return (price_change > 0) ? price_change * 1.5 : price_change * 0.5;  // Reward/Penalty system
}