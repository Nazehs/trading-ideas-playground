//+------------------------------------------------------------------+
//|                                                         SessionEA |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>
#include <Trade\OrderInfo.mqh>

input double RiskReward       = 2.0;           // Risk-Reward ratio
input ENUM_TIMEFRAMES TimeFrame = PERIOD_M15;  // Time frame (default 15 minutes)
input double LotSize          = 0.1;           // Lot size
input string SymbolsToTrade   = "";            // Symbols to trade (default empty for current symbol)
input double OffsetPips       = 15.0;           // Offset in pips for placing orders above/below the candle
input double DrawdownPercent  = 5.0;          // Drawdown percentage threshold
input int      InputTrailingStop   = 5000;       // Trailing Step (points)
input int      InputTrailingStep   = 1000;       // Trailing Step (points)

CTrade trade;               // Object for trade operations
CPositionInfo positionInfo; // Object for position information
COrderInfo orderInfo;       // Object for order information


// Global variables
double buy_stop_level, sell_stop_level;

// Trading session times in hours (server time)
input int LondonOpen  = 8;
input int NewYorkOpen = 13;
input int TokyoOpen   = 0;
input int SydneyOpen  = 22;

// Magic number for the EA
input uint MAGIC_NUMBER = 123456;


// Define an enum for trading sessions
enum TradingSession
  {
   SESSION_NONE,
   SESSION_LONDON,
   SESSION_NEWYORK,
   SESSION_TOKYO,
   SESSION_SYDNEY
  };

// Global variables for session tracking
TradingSession currentSession          = SESSION_NONE;
datetime       sessionStartTime        = 0;
bool           ordersPlacedThisSession = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   Print("EA Initialized");
    trade.LogLevel(LOG_LEVEL_ERRORS);                 // Set logging level
   trade.SetExpertMagicNumber(MAGIC_NUMBER);          // Set the magic number for trades
   ChartSetInteger(0, CHART_SHOW_GRID, false);       // Hide grid lines
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Print("EA Deinitialized, Reason: ", reason);
// Clean up pending orders
   RemovePendingOrders();
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
  ManageTrailingStop();
   static TradingSession lastSession = SESSION_NONE;
   MqlDateTime timeStruct;
   TimeToStruct(TimeCurrent(), timeStruct);
   int currentHour = timeStruct.hour;
   TradingSession newSession = SESSION_NONE;
   if(currentHour == LondonOpen)
      newSession = SESSION_LONDON;
   else
      if(currentHour == NewYorkOpen)
         newSession = SESSION_NEWYORK;
      else
         if(currentHour == TokyoOpen)
            newSession = SESSION_TOKYO;
         else
            if(currentHour == SydneyOpen)
               newSession = SESSION_SYDNEY;
   if(newSession != SESSION_NONE && newSession != lastSession)
     {
      // New session detected
      currentSession          = newSession;
      sessionStartTime        = TimeCurrent();
      ordersPlacedThisSession = false;
      Print("New session detected: ", EnumToString(currentSession), " at time: ", TimeToString(sessionStartTime));
     }
   lastSession = newSession;
// Now check if we have to place orders
   if(currentSession != SESSION_NONE && !ordersPlacedThisSession)
     {
      // Wait until the first candle after session start has closed
      int       tfSeconds            = PeriodSeconds(TimeFrame);
      datetime  firstCandleCloseTime = sessionStartTime + tfSeconds;
      if(TimeCurrent() >= firstCandleCloseTime)
        {
         // The first candle after session start has closed
         // Now we can proceed to place orders
         // Get the candle data for the first candle after session start
         MqlRates rates[];
         int copied = CopyRates(Symbol(), TimeFrame, sessionStartTime, 1, rates);
         if(copied < 1)
           {
            Print("Failed to copy rates for first candle after session start, Error: ", GetLastError());
            return;
           }
         // Use rates[0] as the first candle after session start
         double candleHigh = rates[0].high;
         double candleLow  = rates[0].low;
         // Now set levels for buy and sell stops with offset
         buy_stop_level  = NormalizeDouble(candleHigh + OffsetPips * _Point, _Digits);
         sell_stop_level = NormalizeDouble(candleLow - OffsetPips * _Point, _Digits);
         // Calculate stop loss and take profit
         double sl_buy  = NormalizeDouble(candleLow, _Digits);   // For buy stop, SL is the low of the candle
         double sl_sell = NormalizeDouble(candleHigh, _Digits);  // For sell stop, SL is the high of the candle
         // Calculate the SL in pips
         double sl_pips_buy  = (buy_stop_level - sl_buy) / _Point;
         double sl_pips_sell = (sl_sell - sell_stop_level) / _Point;
         // Calculate TP based on RR
         double tp_pips_buy  = sl_pips_buy * RiskReward;
         double tp_pips_sell = sl_pips_sell * RiskReward;
         double tp_level_buy  = NormalizeDouble(buy_stop_level + tp_pips_buy * _Point, _Digits);
         double tp_level_sell = NormalizeDouble(sell_stop_level - tp_pips_sell * _Point, _Digits);
         // Place buy and sell stops
         PlaceBuyStop(buy_stop_level, sl_buy, tp_level_buy);
         PlaceSellStop(sell_stop_level, sl_sell, tp_level_sell);
         ordersPlacedThisSession = true;
        }
     }
     // Check and handle drawdown
   CloseTradesOnDrawdown();
  }


//+------------------------------------------------------------------+
//| Place a Buy Stop order                                           |
//+------------------------------------------------------------------+
void PlaceBuyStop(double price, double sl_level, double tp_level)
  {
   double lot = LotSize;
   Print("Placing Buy Stop Order at Price: ", price, " SL: ", sl_level, " TP: ", tp_level);
   if(!trade.BuyStop(lot, price, Symbol(), sl_level, tp_level))
     {
      Print("Failed to place Buy Stop Order, Error: ", GetLastError());
     }
   else
     {
      Print("Successfully placed Buy Stop Order at Price: ", price);
     }
  }

//+------------------------------------------------------------------+
//| Place a Sell Stop order                                          |
//+------------------------------------------------------------------+
void PlaceSellStop(double price, double sl_level, double tp_level)
  {
   double lot = LotSize;
   Print("Placing Sell Stop Order at Price: ", price, " SL: ", sl_level, " TP: ", tp_level);
   if(!trade.SellStop(lot, price, Symbol(), sl_level, tp_level))
     {
      Print("Failed to place Sell Stop Order, Error: ", GetLastError());
     }
   else
     {
      Print("Successfully placed Sell Stop Order at Price: ", price);
     }
  }

//+------------------------------------------------------------------+
//| Remove Pending Orders                                            |
//+------------------------------------------------------------------+
void RemovePendingOrders()
  {
// Delete pending orders for the current symbol
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong orderTicket = OrderGetTicket(i);
      if(orderTicket == 0)
        {
         Print("Failed to get order ticket at index ", i, ", Error: ", GetLastError());
         continue;
        }
      if(OrderSelect(orderTicket))
        {
         if(OrderGetString(ORDER_SYMBOL) != Symbol())
            continue;  // Skip if not the current symbol
         long orderType = OrderGetInteger(ORDER_TYPE);
         if(orderType == ORDER_TYPE_BUY_STOP || orderType == ORDER_TYPE_SELL_STOP)
           {
            if(!trade.OrderDelete(orderTicket))
              {
               Print("Failed to delete order: ", orderTicket, ", Error: ", GetLastError());
              }
            else
              {
               Print("Successfully deleted order: ", orderTicket);
              }
           }
        }
      else
        {
         Print("Failed to select order with ticket ", orderTicket, ", Error: ", GetLastError());
        }
     }
  }
  
  //+------------------------------------------------------------------+
//| Close trades on drawdown                                         |
//+------------------------------------------------------------------+
void CloseTradesOnDrawdown()
  {
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double drawdownLimit  = accountBalance * DrawdownPercent / 100.0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(!positionInfo.SelectByIndex(i))
         continue;

      double positionLoss = PositionGetDouble(POSITION_PROFIT);
      if(positionLoss < 0 && MathAbs(positionLoss) > drawdownLimit)
        {
         ulong ticket = PositionGetInteger(POSITION_TICKET);
         if(trade.PositionClose(ticket))
            Print("Closed position due to drawdown: ", ticket);
         else
            Print("Failed to close position: ", ticket, ", Error: ", GetLastError());
        }
     }
  }

//+------------------------------------------------------------------+
//| OnTradeTransaction function                                      |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans, const MqlTradeRequest& request, const MqlTradeResult& result)
  {
// Check if the transaction is a new deal added
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
     {
      RemovePendingOrders();
     }
  }
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Manage trailing stop                                              |
//+------------------------------------------------------------------+
void ManageTrailingStop() {
    if (!positionInfo.Select(_Symbol)) {
        Print("No position found for symbol: ", _Symbol);
        return; // No position to manage
    }
    
    double currentSL = positionInfo.StopLoss();
    double openPrice = positionInfo.PriceOpen();
    double currentPrice;
    double newSL;
    
    // Handle Buy Positions
    if (positionInfo.PositionType() == POSITION_TYPE_BUY) {
        currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        newSL = NormalizeDouble(currentPrice - InputTrailingStop * _Point, _Digits);
        
        // Update SL only if the new SL is higher than the current SL by Trailing Step
        if ((currentSL == 0 && newSL > openPrice) || (newSL > currentSL + InputTrailingStep * _Point)) {
            if (trade.PositionModify(positionInfo.Ticket(), newSL, positionInfo.TakeProfit())) {
                Print("Trailing Stop updated for BUY position: New SL = ", newSL);
            } else {
                Print("Failed to modify Trailing Stop for BUY position, Error: ", GetLastError());
            }
        }
    }
    // Handle Sell Positions
    else if (positionInfo.PositionType() == POSITION_TYPE_SELL) {
        currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
        newSL = NormalizeDouble(currentPrice + InputTrailingStop * _Point, _Digits);
        
        // Update SL only if the new SL is lower than the current SL by Trailing Step
        if ((currentSL == 0 && newSL < openPrice) || (newSL < currentSL - InputTrailingStep * _Point)) {
            if (trade.PositionModify(positionInfo.Ticket(), newSL, positionInfo.TakeProfit())) {
                Print("Trailing Stop updated for SELL position: New SL = ", newSL);
            } else {
                Print("Failed to modify Trailing Stop for SELL position, Error: ", GetLastError());
            }
        }
    }
}