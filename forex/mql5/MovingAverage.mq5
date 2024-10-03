//+------------------------------------------------------------------+
//|                                              Moving Averages.mq5 |
//|                             Copyright 2000-2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2000-2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade\Trade.mqh>

// Define constants for clarity and maintainability
#define MA_MAGIC 1234501

// Input parameters with descriptive names
input double MaximumRisk = 0.02;       // Maximum risk percentage
input double DecreaseFactor = 3;       // Decrease factor for lot size adjustment
input int    MovingPeriod = 20;       // Moving average period
input int    MovingShift = 9;        // Moving average shift
input double TrailingStopLoss = 20;   // Trailing stop loss in points
input int    TrailingStopLossTrigger = 30; // Trigger for activating trailing stop loss
input int    TakeProfitPoints = 300;  // Take profit in points
input int    StopLossPoints = 250;   // Stop loss in points
input double VolumeConfluenceFactor = 1.5; // Factor for volume confluence (e.g., 1.5)
input double MinDistanceMovement = 20;
// Global variables for easy access
CPositionInfo positionInfo; // Object for position information
CTrade trade; // Object for trade operations
int ExtHandle = 0; // Handle for the moving average indicator
bool ExtHedging = false; // Flag for hedging mode
CTrade ExtTrade; // Trade object for hedging mode

//+------------------------------------------------------------------+
//| Calculate optimal lot size                                       |
//+------------------------------------------------------------------+
double TradeSizeOptimized()
{
   // Get current ask price
   double price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if (price == 0.0)
   {
      Print("Error getting ask price for ", _Symbol);
      return 0.0;
   }

   // Calculate margin required for 1 lot
   double margin = 0.0;
   if (!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, 1.0, price, margin))
   {
      Print("Error calculating margin for ", _Symbol);
      return 0.0;
   }
   if (margin <= 0.0)
   {
      Print("Invalid margin value for ", _Symbol);
      return 0.0;
   }

   // Calculate initial lot size based on maximum risk
   double lot = NormalizeDouble(AccountInfoDouble(ACCOUNT_MARGIN_FREE) * MaximumRisk / margin, 2);

   // Adjust lot size based on decrease factor and recent losses
   if (DecreaseFactor > 0)
   {
      // Get history for analysis
      HistorySelect(0, TimeCurrent());

      // Count losses without a break
      int orders = HistoryDealsTotal();
      int losses = 0;
      for (int i = orders - 1; i >= 0; i--)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if (ticket == 0)
         {
            Print("HistoryDealGetTicket failed, no trade history");
            break;
         }

         // Check if trade is for the current symbol and magic number
         if (HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol ||
             HistoryDealGetInteger(ticket, DEAL_MAGIC) != MA_MAGIC)
         {
            continue;
         }

         // Count losses
         double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
         if (profit > 0.0)
         {
            break;
         }
         if (profit < 0.0)
         {
            losses++;
         }
      }

      // Adjust lot size based on losses
      if (losses > 1)
      {
         lot = NormalizeDouble(lot - lot * losses / DecreaseFactor, 1);
      }
   }

   // Normalize lot size and check limits
   double stepvol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lot = stepvol * NormalizeDouble(lot / stepvol, 0);

   double minvol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   lot = MathMax(lot, minvol);

   double maxvol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   lot = MathMin(lot, maxvol);

   return lot;
}

//+------------------------------------------------------------------+
//| Check for open position conditions                               |
//+------------------------------------------------------------------+
void CheckForOpen()
{
   // Get the last two bars
   MqlRates rt[2];
   if (CopyRates(_Symbol, _Period, 0, 2, rt) != 2)
   {
      Print("CopyRates of ", _Symbol, " failed, no history");
      return;
   }

   // Ignore if not the first tick of the new bar
   if (rt[1].tick_volume > 1)
   {
      return;
   }

   // Get the current moving average value
   double ma[1];
   if (CopyBuffer(ExtHandle, 0, 0, 1, ma) != 1)
   {
      Print("CopyBuffer from iMA failed, no data");
      return;
   }

   // Determine the trading signal
   ENUM_ORDER_TYPE signal = WRONG_VALUE;
  // Buy Signal: Price above MA with minimum distance
   if (rt[0].low > ma[0] && (rt[0].low - ma[0]) > MinDistanceMovement * _Point)
   {
      // Check for volume confluence on buy signal
      //if (rt[0].tick_volume > rt[1].tick_volume * VolumeConfluenceFactor)
     // {
         signal = ORDER_TYPE_BUY; // Buy conditions
      //}
   }

   // Sell Signal: Price below MA with minimum distance
   else if (rt[0].high < ma[0] && (ma[0] - rt[0].high) > MinDistanceMovement * _Point)
   {
      // Check for volume confluence on sell signal
     //if (rt[0].tick_volume > rt[1].tick_volume * VolumeConfluenceFactor)
      //{
         signal = ORDER_TYPE_SELL; // Sell conditions
      //}
   }

   // Open a position if a valid signal is found
   if (signal != WRONG_VALUE)
   {
      double currentPrice = SymbolInfoDouble(_Symbol, signal == ORDER_TYPE_SELL ? SYMBOL_BID : SYMBOL_ASK);
      double stopLoss = NormalizeDouble(signal == ORDER_TYPE_SELL ? currentPrice + StopLossPoints * _Point : currentPrice - StopLossPoints * _Point, _Digits);
      double takeProfit = NormalizeDouble(signal == ORDER_TYPE_SELL ? currentPrice - TakeProfitPoints * _Point : currentPrice + TakeProfitPoints * _Point, _Digits);

      if (TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) && Bars(_Symbol, _Period) > 100)
      {
         ExtTrade.PositionOpen(_Symbol, signal, TradeSizeOptimized(), currentPrice, stopLoss, takeProfit);
      }
   }
}

//+------------------------------------------------------------------+
//| Check for close position conditions                              |
//+------------------------------------------------------------------+
void CheckForClose()
{
   // Get the last two bars
   MqlRates rt[2];
   if (CopyRates(_Symbol, _Period, 0, 2, rt) != 2)
   {
      Print("CopyRates of ", _Symbol, " failed, no history");
      return;
   }

   // Ignore if not the first tick of the new bar
   if (rt[1].tick_volume > 1)
   {
      return;
   }

   // Get the current moving average value
   double ma[1];
   if (CopyBuffer(ExtHandle, 0, 0, 1, ma) != 1)
   {
      Print("CopyBuffer from iMA failed, no data");
      return;
   }

   // Check for close signals based on position type
   bool signal = false;
   long type = PositionGetInteger(POSITION_TYPE);
   if (type == (long)POSITION_TYPE_BUY && rt[0].open > ma[0] && rt[0].close < ma[0])
   {
      signal = true;
   }
   else if (type == (long)POSITION_TYPE_SELL && rt[0].open < ma[0] && rt[0].close > ma[0])
   {
      signal = true;
   }

   // Close the position if a valid signal is found
   if (signal)
   {
      if (TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) && Bars(_Symbol, _Period) > 100)
      {
         ExtTrade.PositionClose(_Symbol, 3);
      }
   }
}

//+------------------------------------------------------------------+
//| Trailing Stop Loss Management                                     |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
   // Calculate trailing stop in price
   double trailingStop = TrailingStopLoss * _Point;

   // Get current bid and ask prices
   double currentPrice = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits);
   double currentAsk = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits);

   // Iterate through all open positions
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      // Select the position by index
      if (positionInfo.SelectByIndex(i))
      {
         ulong ticket = positionInfo.Ticket();
         double takeProfit = positionInfo.TakeProfit();

         // Manage trailing stop for buy and sell positions
         if (positionInfo.Symbol() == _Symbol && positionInfo.PositionType() == POSITION_TYPE_BUY)
         {
            if (currentPrice - positionInfo.PriceOpen() > (TrailingStopLossTrigger * _Point))
            {
               double newStopLoss = NormalizeDouble(currentPrice - trailingStop, _Digits);
               if (newStopLoss > positionInfo.StopLoss() && newStopLoss != 0)
               {
                  if (trade.PositionModify(ticket, newStopLoss, takeProfit))
                  {
                     Print("Trailing stop updated to: ", newStopLoss);
                  }
                  else
                  {
                     Print("Error modifying position: ", GetLastError());
                  }
               }
            }
         }
         else if (positionInfo.Symbol() == _Symbol && positionInfo.PositionType() == POSITION_TYPE_SELL)
         {
            if (currentAsk + (TrailingStopLossTrigger * _Point) < positionInfo.PriceOpen())
            {
               double newStopLoss = NormalizeDouble(currentAsk + trailingStop, _Digits);
               if (newStopLoss < positionInfo.StopLoss() && newStopLoss != 0)
               {
                  if (trade.PositionModify(ticket, newStopLoss, takeProfit))
                  {
                     Print("Sell trailing stop updated to: ", newStopLoss);
                  }
                  else
                  {
                     Print("Error modifying sell position: ", GetLastError());
                  }
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Position select depending on netting or hedging                  |
//+------------------------------------------------------------------+
bool SelectPosition()
{
   // Check for open position in hedging mode
   if (ExtHedging)
   {
      uint total = PositionsTotal();
      for (uint i = 0; i < total; i++)
      {
         string position_symbol = PositionGetSymbol(i);
         if (_Symbol == position_symbol && MA_MAGIC == PositionGetInteger(POSITION_MAGIC))
         {
            return true;
         }
      }
   }
   else
   {
      // Check for open position in netting mode
      if (!PositionSelect(_Symbol))
      {
         return false;
      }
      else
      {
         return (PositionGetInteger(POSITION_MAGIC) == MA_MAGIC); // Check magic number
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize trade objects for hedging and netting modes
   ExtHedging = ((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
   ExtTrade.SetExpertMagicNumber(MA_MAGIC);
   ExtTrade.SetMarginMode();
   ExtTrade.SetTypeFillingBySymbol(Symbol());

   // Initialize the moving average indicator
   ExtHandle = iMA(_Symbol, _Period, MovingPeriod, MovingShift, MODE_SMA, PRICE_CLOSE);
   if (ExtHandle == INVALID_HANDLE)
   {
      Print("Error creating MA indicator");
      return INIT_FAILED;
   }

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if (SelectPosition())
   {
      ManageTrailingStop(); // Call the trailing stop management function
      //CheckForClose();
   }
   else
   {
      CheckForOpen();
   }
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
}
//+------------------------------------------------------------------+